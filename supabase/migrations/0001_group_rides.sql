-- Ride Together: group ride lifecycle, membership, durable messaging, and Realtime
-- authorization for the private `group-ride:<id>` broadcast/presence channel.
--
-- Design notes (see docs/RideTogether.md for the full write-up):
--   * Tables are RLS-enabled but NOT force-RLS'd. All mutation goes through the
--     SECURITY DEFINER functions below, which are owned by the migration role and therefore
--     bypass RLS for their own internal writes (the standard Postgres "table owner bypasses
--     RLS" behavior) while `authenticated`/`anon` remain fully subject to the SELECT-only (plus
--     two narrow, explicitly-scoped UPDATE/INSERT) policies defined for those roles.
--   * No table stores rider coordinates. Live location only ever travels over Realtime
--     Broadcast and is never written to Postgres.
--   * Assumes `pgcrypto` is installed in the `extensions` schema, which is Supabase's default
--     location for it. If a project has it elsewhere, adjust the `extensions.` qualifications
--     below accordingly.
--   * The Realtime Authorization policies at the bottom assume the `realtime.topic()` helper
--     exposed by Supabase's private-channel Realtime Authorization feature. This is the one
--     piece of this migration that could not be verified against a live project from this
--     environment — see docs/RideTogether.md for the manual verification steps.

create extension if not exists pgcrypto with schema extensions;

create schema if not exists app_private;
comment on schema app_private is 'Helper functions for RLS/RPC checks. Not exposed via PostgREST.';

-- =============================================================================================
-- Tables
-- =============================================================================================

create table if not exists public.group_rides (
    id                  uuid primary key default gen_random_uuid(),
    host_user_id        uuid not null references auth.users (id) on delete cascade,
    status              text not null default 'lobby'
                        check (status in ('lobby', 'active', 'ended', 'cancelled')),
    title               text,
    destination_name    text not null,
    destination_latitude  double precision not null,
    destination_longitude double precision not null,
    route_snapshot      jsonb not null,
    route_snapshot_version integer not null default 1,
    max_members         integer not null default 8 check (max_members between 2 and 12),
    -- SHA-256 hex digest of the raw invite token. The raw token is returned exactly once, by
    -- create_group_ride / rotate_group_ride_invite, and never stored.
    invite_token_hash   text,
    invite_expires_at   timestamptz,
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now(),
    started_at          timestamptz,
    ended_at            timestamptz
);

create table if not exists public.group_ride_members (
    ride_id       uuid not null references public.group_rides (id) on delete cascade,
    user_id       uuid not null references auth.users (id) on delete cascade,
    role          text not null default 'rider' check (role in ('host', 'rider')),
    status        text not null default 'joined' check (status in ('joined', 'left', 'removed')),
    display_name  text not null,
    avatar_seed   text not null,
    joined_at     timestamptz not null default now(),
    left_at       timestamptz,
    last_seen_at  timestamptz,
    primary key (ride_id, user_id)
);

create table if not exists public.group_ride_messages (
    id                uuid primary key default gen_random_uuid(),
    ride_id           uuid not null references public.group_rides (id) on delete cascade,
    sender_user_id    uuid not null references auth.users (id) on delete cascade,
    -- Denormalized at send time so the message list never needs a join, and a later display-name
    -- change doesn't rewrite history — the same tradeoff most chat apps make.
    sender_display_name text not null,
    kind              text not null check (kind in ('preset', 'dictated', 'system')),
    body              text not null check (char_length(body) <= 160 and char_length(body) > 0),
    preset_key        text,
    client_message_id uuid not null,
    created_at        timestamptz not null default now(),
    -- Optional retention marker. No cleanup job ships in this MVP; left as an extension point.
    expires_at        timestamptz,
    unique (ride_id, sender_user_id, client_message_id)
);

create index if not exists group_ride_members_ride_id_idx on public.group_ride_members (ride_id);
create index if not exists group_ride_messages_ride_id_created_at_idx
    on public.group_ride_messages (ride_id, created_at desc);
create index if not exists group_rides_host_user_id_idx on public.group_rides (host_user_id);

-- =============================================================================================
-- Helper functions (app_private schema — not exposed via PostgREST)
-- =============================================================================================

create or replace function app_private.is_active_group_ride_member(p_ride_id uuid)
returns boolean
language sql
security definer
stable
set search_path = pg_catalog, public
as $$
    select exists (
        select 1
        from public.group_ride_members m
        where m.ride_id = p_ride_id
          and m.user_id = auth.uid()
          and m.status = 'joined'
    );
$$;

revoke all on function app_private.is_active_group_ride_member(uuid) from public;
grant execute on function app_private.is_active_group_ride_member(uuid) to authenticated;

create or replace function app_private.hash_invite_token(p_token text)
returns text
language sql
immutable
set search_path = pg_catalog, extensions
as $$
    select encode(extensions.digest(p_token, 'sha256'), 'hex');
$$;

create or replace function app_private.generate_invite_token()
returns text
language sql
volatile
set search_path = pg_catalog, extensions
as $$
    select rtrim(replace(replace(encode(extensions.gen_random_bytes(24), 'base64'), '+', '-'), '/', '_'), '=');
$$;

-- =============================================================================================
-- RLS
-- =============================================================================================

alter table public.group_rides enable row level security;
alter table public.group_ride_members enable row level security;
alter table public.group_ride_messages enable row level security;

-- group_rides: readable by the host or any active member. No direct INSERT/UPDATE/DELETE policy
-- exists for authenticated/anon — every mutation goes through a SECURITY DEFINER function below.
create policy group_rides_select_member_or_host on public.group_rides
    for select
    to authenticated
    using (
        host_user_id = auth.uid()
        or app_private.is_active_group_ride_member(id)
    );

-- group_ride_members: a rider can always see their own row; any active member of the ride can
-- see the full membership list (needed for the lobby/participant sheet).
create policy group_ride_members_select on public.group_ride_members
    for select
    to authenticated
    using (
        user_id = auth.uid()
        or app_private.is_active_group_ride_member(ride_id)
    );

-- Defense-in-depth direct path for "a member can mark their own membership as left" — the app
-- normally calls leave_group_ride() instead (it also handles the host-leaving-ends-ride cascade),
-- but this keeps the capability enforceable at the RLS layer independent of that RPC.
create policy group_ride_members_self_leave on public.group_ride_members
    for update
    to authenticated
    using (user_id = auth.uid() and status = 'joined')
    with check (user_id = auth.uid() and status = 'left');

-- group_ride_messages: any active member can read the ride's messages, and can insert a message
-- only as themselves, only while an active member, within the body length limit, and rate
-- limited to 5 messages per 10 seconds — enforced directly in the INSERT policy so no extra
-- infrastructure (no pg_cron, no separate rate-limit table) is required.
create policy group_ride_messages_select on public.group_ride_messages
    for select
    to authenticated
    using (app_private.is_active_group_ride_member(ride_id));

create policy group_ride_messages_insert on public.group_ride_messages
    for insert
    to authenticated
    with check (
        sender_user_id = auth.uid()
        and app_private.is_active_group_ride_member(ride_id)
        and char_length(body) <= 160
        -- Prevents a member from labeling their message with someone else's display name —
        -- the name shown must match what the ride actually has on file for them right now.
        and sender_display_name = (
            select m.display_name from public.group_ride_members m
            where m.ride_id = group_ride_messages.ride_id and m.user_id = auth.uid()
        )
        and (
            select count(*)
            from public.group_ride_messages existing
            where existing.ride_id = group_ride_messages.ride_id
              and existing.sender_user_id = auth.uid()
              and existing.created_at > now() - interval '10 seconds'
        ) < 5
    );

-- =============================================================================================
-- RPCs
-- =============================================================================================

create or replace function public.create_group_ride(
    p_destination_name text,
    p_destination_latitude double precision,
    p_destination_longitude double precision,
    p_route_snapshot jsonb,
    p_max_members integer default 8,
    p_title text default null,
    p_display_name text default null,
    p_avatar_seed text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
    v_uid uuid := auth.uid();
    v_ride_id uuid := gen_random_uuid();
    v_raw_token text;
    v_max_members integer := least(greatest(coalesce(p_max_members, 8), 2), 12);
    v_display_name text := coalesce(nullif(trim(p_display_name), ''), 'Host');
    v_avatar_seed text := coalesce(nullif(trim(p_avatar_seed), ''), v_uid::text);
    v_ride public.group_rides;
begin
    if v_uid is null then
        raise exception 'Authentication required' using errcode = '28000';
    end if;

    if p_destination_name is null or length(trim(p_destination_name)) = 0 then
        raise exception 'destination_name is required' using errcode = '22023';
    end if;

    if p_route_snapshot is null then
        raise exception 'route_snapshot is required' using errcode = '22023';
    end if;

    v_raw_token := app_private.generate_invite_token();

    insert into public.group_rides (
        id, host_user_id, status, title, destination_name,
        destination_latitude, destination_longitude, route_snapshot, route_snapshot_version,
        max_members, invite_token_hash, invite_expires_at, created_at, updated_at
    ) values (
        v_ride_id, v_uid, 'lobby', nullif(trim(p_title), ''), trim(p_destination_name),
        p_destination_latitude, p_destination_longitude, p_route_snapshot,
        coalesce((p_route_snapshot ->> 'schemaVersion')::integer, 1),
        v_max_members, app_private.hash_invite_token(v_raw_token), now() + interval '24 hours',
        now(), now()
    )
    returning * into v_ride;

    insert into public.group_ride_members (
        ride_id, user_id, role, status, display_name, avatar_seed, joined_at
    ) values (
        v_ride_id, v_uid, 'host', 'joined', v_display_name, v_avatar_seed, now()
    );

    return jsonb_build_object(
        'ride', to_jsonb(v_ride) - 'invite_token_hash',
        'raw_invite_token', v_raw_token
    );
end;
$$;

revoke all on function public.create_group_ride(
    text, double precision, double precision, jsonb, integer, text, text, text
) from public;
grant execute on function public.create_group_ride(
    text, double precision, double precision, jsonb, integer, text, text, text
) to authenticated;

-- Callable before joining: validates the token and returns just enough to render the join
-- preview screen. Deliberately raises the same generic error for "no such ride", "wrong token",
-- and "expired token" so a caller can't use this endpoint to enumerate private ride IDs.
create or replace function public.preview_group_ride_invite(
    p_ride_id uuid,
    p_invite_token text
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog, public, extensions
as $$
declare
    v_ride public.group_rides;
    v_host_name text;
    v_active_member_count integer;
begin
    select * into v_ride from public.group_rides where id = p_ride_id;

    if v_ride.id is null
       or v_ride.invite_token_hash is null
       or v_ride.invite_token_hash <> app_private.hash_invite_token(coalesce(p_invite_token, ''))
       or v_ride.invite_expires_at is null
       or v_ride.invite_expires_at < now()
    then
        raise exception 'This invite link is invalid or has expired' using errcode = 'PGRST';
    end if;

    select display_name into v_host_name
    from public.group_ride_members
    where ride_id = v_ride.id and role = 'host'
    limit 1;

    select count(*) into v_active_member_count
    from public.group_ride_members
    where ride_id = v_ride.id and status = 'joined';

    return jsonb_build_object(
        'ride_id', v_ride.id,
        'status', v_ride.status,
        'destination_name', v_ride.destination_name,
        'destination_latitude', v_ride.destination_latitude,
        'destination_longitude', v_ride.destination_longitude,
        'route_snapshot', v_ride.route_snapshot,
        'max_members', v_ride.max_members,
        'active_member_count', v_active_member_count,
        'host_display_name', coalesce(v_host_name, 'Host')
    );
end;
$$;

revoke all on function public.preview_group_ride_invite(uuid, text) from public;
grant execute on function public.preview_group_ride_invite(uuid, text) to authenticated;

create or replace function public.join_group_ride(
    p_ride_id uuid,
    p_invite_token text,
    p_display_name text default null,
    p_avatar_seed text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
    v_uid uuid := auth.uid();
    v_ride public.group_rides;
    v_existing public.group_ride_members;
    v_active_member_count integer;
    v_display_name text := coalesce(nullif(trim(p_display_name), ''), 'Rider');
    v_avatar_seed text := coalesce(nullif(trim(p_avatar_seed), ''), v_uid::text);
begin
    if v_uid is null then
        raise exception 'Authentication required' using errcode = '28000';
    end if;

    select * into v_ride from public.group_rides where id = p_ride_id;

    if v_ride.id is null
       or v_ride.invite_token_hash is null
       or v_ride.invite_token_hash <> app_private.hash_invite_token(coalesce(p_invite_token, ''))
       or v_ride.invite_expires_at is null
       or v_ride.invite_expires_at < now()
    then
        raise exception 'This invite link is invalid or has expired' using errcode = 'PGRST';
    end if;

    if v_ride.status = 'ended' then
        raise exception 'This group ride has ended' using errcode = 'PGRST';
    elsif v_ride.status = 'cancelled' then
        raise exception 'This group ride was cancelled' using errcode = 'PGRST';
    end if;

    select * into v_existing
    from public.group_ride_members
    where ride_id = p_ride_id and user_id = v_uid;

    if v_existing.user_id is not null and v_existing.status = 'removed' then
        raise exception 'You can''t rejoin this group ride' using errcode = 'PGRST';
    end if;

    if v_existing.user_id is not null and v_existing.status = 'joined' then
        -- Idempotent retry: already joined, just return current state.
        update public.group_ride_members
        set last_seen_at = now()
        where ride_id = p_ride_id and user_id = v_uid;
    else
        select count(*) into v_active_member_count
        from public.group_ride_members
        where ride_id = p_ride_id and status = 'joined';

        if v_active_member_count >= v_ride.max_members then
            raise exception 'This group ride is full' using errcode = 'PGRST';
        end if;

        if v_existing.user_id is not null then
            -- Rejoin: restore the previous row atomically rather than inserting a duplicate.
            update public.group_ride_members
            set status = 'joined', left_at = null, last_seen_at = now(),
                display_name = v_display_name, avatar_seed = v_avatar_seed
            where ride_id = p_ride_id and user_id = v_uid;
        else
            insert into public.group_ride_members (
                ride_id, user_id, role, status, display_name, avatar_seed, joined_at, last_seen_at
            ) values (
                p_ride_id, v_uid, 'rider', 'joined', v_display_name, v_avatar_seed, now(), now()
            );
        end if;
    end if;

    return jsonb_build_object(
        'ride', to_jsonb(v_ride) - 'invite_token_hash',
        'membership', (
            select to_jsonb(m) from public.group_ride_members m
            where m.ride_id = p_ride_id and m.user_id = v_uid
        )
    );
end;
$$;

revoke all on function public.join_group_ride(uuid, text, text, text) from public;
grant execute on function public.join_group_ride(uuid, text, text, text) to authenticated;

create or replace function public.rotate_group_ride_invite(p_ride_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
    v_uid uuid := auth.uid();
    v_ride public.group_rides;
    v_raw_token text;
    v_expires_at timestamptz := now() + interval '24 hours';
begin
    select * into v_ride from public.group_rides where id = p_ride_id;

    if v_ride.id is null or v_ride.host_user_id <> v_uid then
        raise exception 'Only the host can rotate this invite' using errcode = '42501';
    end if;

    if v_ride.status not in ('lobby', 'active') then
        raise exception 'This group ride can no longer be invited to' using errcode = 'PGRST';
    end if;

    v_raw_token := app_private.generate_invite_token();

    update public.group_rides
    set invite_token_hash = app_private.hash_invite_token(v_raw_token),
        invite_expires_at = v_expires_at,
        updated_at = now()
    where id = p_ride_id;

    return jsonb_build_object('raw_invite_token', v_raw_token, 'invite_expires_at', v_expires_at);
end;
$$;

revoke all on function public.rotate_group_ride_invite(uuid) from public;
grant execute on function public.rotate_group_ride_invite(uuid) to authenticated;

create or replace function public.update_group_ride_route(
    p_ride_id uuid,
    p_route_snapshot jsonb,
    p_destination_name text default null,
    p_destination_latitude double precision default null,
    p_destination_longitude double precision default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
    v_uid uuid := auth.uid();
    v_ride public.group_rides;
begin
    select * into v_ride from public.group_rides where id = p_ride_id;

    if v_ride.id is null or v_ride.host_user_id <> v_uid then
        raise exception 'Only the host can update this ride''s route' using errcode = '42501';
    end if;

    if v_ride.status <> 'lobby' then
        raise exception 'The route can only be changed before the ride starts' using errcode = 'PGRST';
    end if;

    update public.group_rides
    set route_snapshot = p_route_snapshot,
        route_snapshot_version = coalesce((p_route_snapshot ->> 'schemaVersion')::integer, route_snapshot_version),
        destination_name = coalesce(nullif(trim(p_destination_name), ''), destination_name),
        destination_latitude = coalesce(p_destination_latitude, destination_latitude),
        destination_longitude = coalesce(p_destination_longitude, destination_longitude),
        updated_at = now()
    where id = p_ride_id
    returning * into v_ride;

    return jsonb_build_object('ride', to_jsonb(v_ride) - 'invite_token_hash');
end;
$$;

revoke all on function public.update_group_ride_route(uuid, jsonb, text, double precision, double precision) from public;
grant execute on function public.update_group_ride_route(uuid, jsonb, text, double precision, double precision) to authenticated;

create or replace function public.start_group_ride(p_ride_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
    v_uid uuid := auth.uid();
    v_ride public.group_rides;
begin
    select * into v_ride from public.group_rides where id = p_ride_id;

    if v_ride.id is null or v_ride.host_user_id <> v_uid then
        raise exception 'Only the host can start this ride' using errcode = '42501';
    end if;

    if v_ride.status <> 'lobby' then
        raise exception 'This ride can no longer be started' using errcode = 'PGRST';
    end if;

    update public.group_rides
    set status = 'active', started_at = now(), updated_at = now()
    where id = p_ride_id
    returning * into v_ride;

    return jsonb_build_object('ride', to_jsonb(v_ride) - 'invite_token_hash');
end;
$$;

revoke all on function public.start_group_ride(uuid) from public;
grant execute on function public.start_group_ride(uuid) to authenticated;

create or replace function public.end_group_ride(p_ride_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
    v_uid uuid := auth.uid();
    v_ride public.group_rides;
begin
    select * into v_ride from public.group_rides where id = p_ride_id;

    if v_ride.id is null or v_ride.host_user_id <> v_uid then
        raise exception 'Only the host can end this ride' using errcode = '42501';
    end if;

    if v_ride.status <> 'active' then
        raise exception 'This ride is not active' using errcode = 'PGRST';
    end if;

    update public.group_rides
    set status = 'ended', ended_at = now(), updated_at = now()
    where id = p_ride_id
    returning * into v_ride;

    return jsonb_build_object('ride', to_jsonb(v_ride) - 'invite_token_hash');
end;
$$;

revoke all on function public.end_group_ride(uuid) from public;
grant execute on function public.end_group_ride(uuid) to authenticated;

create or replace function public.cancel_group_ride(p_ride_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
    v_uid uuid := auth.uid();
    v_ride public.group_rides;
begin
    select * into v_ride from public.group_rides where id = p_ride_id;

    if v_ride.id is null or v_ride.host_user_id <> v_uid then
        raise exception 'Only the host can cancel this ride' using errcode = '42501';
    end if;

    if v_ride.status not in ('lobby', 'active') then
        raise exception 'This ride can no longer be cancelled' using errcode = 'PGRST';
    end if;

    update public.group_rides
    set status = 'cancelled', ended_at = now(), updated_at = now()
    where id = p_ride_id
    returning * into v_ride;

    return jsonb_build_object('ride', to_jsonb(v_ride) - 'invite_token_hash');
end;
$$;

revoke all on function public.cancel_group_ride(uuid) from public;
grant execute on function public.cancel_group_ride(uuid) to authenticated;

create or replace function public.leave_group_ride(p_ride_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
    v_uid uuid := auth.uid();
    v_ride public.group_rides;
    v_member public.group_ride_members;
    v_new_ride_status text;
begin
    select * into v_ride from public.group_rides where id = p_ride_id;
    select * into v_member from public.group_ride_members
        where ride_id = p_ride_id and user_id = v_uid;

    if v_ride.id is null or v_member.user_id is null or v_member.status <> 'joined' then
        raise exception 'You are not an active member of this ride' using errcode = 'PGRST';
    end if;

    update public.group_ride_members
    set status = 'left', left_at = now()
    where ride_id = p_ride_id and user_id = v_uid;

    if v_member.role = 'host' then
        -- No leader transfer in this MVP: the host leaving ends the ride outright.
        v_new_ride_status := case when v_ride.status = 'active' then 'ended' else 'cancelled' end;
        update public.group_rides
        set status = v_new_ride_status,
            ended_at = case when v_new_ride_status in ('ended', 'cancelled') then now() else ended_at end,
            updated_at = now()
        where id = p_ride_id;
    end if;

    return jsonb_build_object('left', true, 'host_left', v_member.role = 'host');
end;
$$;

revoke all on function public.leave_group_ride(uuid) from public;
grant execute on function public.leave_group_ride(uuid) to authenticated;

create or replace function public.remove_group_ride_member(p_ride_id uuid, p_member_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
    v_uid uuid := auth.uid();
    v_ride public.group_rides;
begin
    select * into v_ride from public.group_rides where id = p_ride_id;

    if v_ride.id is null or v_ride.host_user_id <> v_uid then
        raise exception 'Only the host can remove a member' using errcode = '42501';
    end if;

    if p_member_user_id = v_uid then
        raise exception 'Use leave_group_ride to remove yourself' using errcode = 'PGRST';
    end if;

    update public.group_ride_members
    set status = 'removed', left_at = now()
    where ride_id = p_ride_id and user_id = p_member_user_id and status = 'joined';

    return jsonb_build_object('removed', found);
end;
$$;

revoke all on function public.remove_group_ride_member(uuid, uuid) from public;
grant execute on function public.remove_group_ride_member(uuid, uuid) to authenticated;

-- Lightweight, high-frequency-safe touch for the "slow-changing last_seen_at" field mentioned in
-- the membership model. Intentionally separate from the RLS "mark as left" policy so a stray
-- partial update can't accidentally change membership status.
create or replace function public.touch_group_ride_presence(p_ride_id uuid)
returns void
language sql
security definer
set search_path = pg_catalog, public
as $$
    update public.group_ride_members
    set last_seen_at = now()
    where ride_id = p_ride_id and user_id = auth.uid() and status = 'joined';
$$;

revoke all on function public.touch_group_ride_presence(uuid) from public;
grant execute on function public.touch_group_ride_presence(uuid) to authenticated;

-- =============================================================================================
-- Realtime authorization for the private `group-ride:<id>` channel
-- =============================================================================================
-- Requires the project's Realtime Authorization (private channels) feature. The Swift client
-- must create the channel with its private-channel option set (see
-- GroupRideRealtimeClient/SupabaseGroupRideRealtimeClient) for these policies to be consulted at
-- all — a channel opened without that option is treated as public and bypasses this table.

-- No `alter table realtime.messages enable row level security` here: Supabase owns that table
-- (via its own system role) and already has RLS enabled on it. The project's SQL-editor role has
-- just enough delegated privilege to add policies, not to run ALTER TABLE against it — attempting
-- the ALTER fails with "must be owner of table messages" (42501).

create policy group_ride_channel_receive on realtime.messages
    for select
    to authenticated
    using (
        realtime.topic() like 'group-ride:%'
        and app_private.is_active_group_ride_member(
            nullif(split_part(realtime.topic(), ':', 2), '')::uuid
        )
    );

create policy group_ride_channel_send on realtime.messages
    for insert
    to authenticated
    with check (
        realtime.topic() like 'group-ride:%'
        and app_private.is_active_group_ride_member(
            nullif(split_part(realtime.topic(), ':', 2), '')::uuid
        )
    );
