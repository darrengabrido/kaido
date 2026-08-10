-- Community Routes: a rider-published catalog of bike routes, browsable from the Routes tab's
-- "Community" section.
--
-- Design notes (see docs/CommunityRoutes.md for the full write-up):
--   * Unlike `0001_group_rides.sql`, this feature has no invite-token/state-machine invariants to
--     protect — publishing/removing a route is a single-row operation gated purely on ownership —
--     so this migration uses plain RLS-enforced CRUD instead of SECURITY DEFINER RPCs.
--   * The SELECT policy intentionally grants `anon` as well as `authenticated`: browsing the
--     community feed is a discovery surface and should work even for a rider who hasn't signed in
--     or started a guest session yet. Publishing still requires an identity (a real account or a
--     transparent anonymous session — see `GroupRideIdentityProvider`, reused here as-is).
--   * `start_latitude`/`start_longitude` are stored even though nothing queries by location yet —
--     forward-compatible groundwork for a future "nearby" sort/filter without another migration.
--   * "Removing" a route is a hard delete (see `remove` on `CommunityRouteService`), not a
--     soft-delete `status` flip — `status` exists so a future moderation pass has somewhere to
--     land a "removed" state without a schema change, but nothing sets it today besides the
--     'published' default.

create table if not exists public.community_routes (
    id                     uuid primary key default gen_random_uuid(),
    author_user_id         uuid not null references auth.users (id) on delete cascade,
    author_display_name    text not null,
    name                   text not null check (char_length(name) between 1 and 80),
    description            text check (description is null or char_length(description) <= 280),
    distance_meters        double precision not null check (distance_meters >= 0),
    elevation_gain_meters  double precision not null default 0,
    -- Ordered [{latitude, longitude, order}, ...] — mirrors `CommunityRoute.Waypoint` exactly.
    waypoints              jsonb not null,
    start_latitude         double precision not null,
    start_longitude        double precision not null,
    status                 text not null default 'published' check (status in ('published', 'removed')),
    created_at             timestamptz not null default now(),
    updated_at             timestamptz not null default now()
);

create index if not exists community_routes_status_created_at_idx
    on public.community_routes (status, created_at desc);
create index if not exists community_routes_author_user_id_idx
    on public.community_routes (author_user_id);

alter table public.community_routes enable row level security;

-- Readable by anyone — signed in, guest, or no session at all — as long as the route is
-- published. An author can additionally see their own non-published rows (relevant once a
-- moderation pass introduces a way to set `status = 'removed'` without deleting the row).
create policy community_routes_select on public.community_routes
    for select
    to anon, authenticated
    using (
        status = 'published'
        or author_user_id = auth.uid()
    );

create policy community_routes_insert_own on public.community_routes
    for insert
    to authenticated
    with check (author_user_id = auth.uid());

create policy community_routes_update_own on public.community_routes
    for update
    to authenticated
    using (author_user_id = auth.uid())
    with check (author_user_id = auth.uid());

create policy community_routes_delete_own on public.community_routes
    for delete
    to authenticated
    using (author_user_id = auth.uid());
