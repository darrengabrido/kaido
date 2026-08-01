-- Ride Together — manual RLS / RPC verification script.
--
-- No Supabase CLI or local Postgres was available in the environment this migration was
-- authored in, so this could not be executed against a live project as part of this change.
-- Run it in the Supabase SQL editor (or `psql` against the project) after applying
-- `supabase/migrations/0001_group_rides.sql`, replacing the placeholder UUIDs with real
-- `auth.users.id` values (e.g. from three test accounts, at least one created via
-- `auth.sign_in_anonymously()` from a client to exercise the guest path).
--
-- The `set local role authenticated; set local request.jwt.claims = ...` pattern below is the
-- standard way to impersonate a given user's RLS context from the SQL editor/psql without a
-- real client JWT. Run each numbered block as its own transaction (`begin; ... ; rollback;`) so
-- nothing here leaves permanent state behind.

-- Fixture setup (run once as postgres / service role) -----------------------------------------
-- begin;
--   insert into auth.users (id, email) values
--     ('11111111-1111-1111-1111-111111111111', 'host@example.com'),
--     ('22222222-2222-2222-2222-222222222222', 'member@example.com'),
--     ('33333333-3333-3333-3333-333333333333', 'nonmember@example.com'),
--     ('44444444-4444-4444-4444-444444444444', 'anon-guest@example.com')
--   on conflict do nothing;
-- commit;

-- 1. Host creates a ride -----------------------------------------------------------------------
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select public.create_group_ride(
    'Golden Gate Park',
    37.7694, -122.4862,
    '{"schemaVersion":1,"destinationName":"Golden Gate Park","destinationLatitude":37.7694,"destinationLongitude":-122.4862,"waypoints":[],"routingProfile":"cycling","distanceMeters":5000,"expectedDurationSeconds":1200,"capturedAt":"2026-01-01T00:00:00Z"}'::jsonb,
    8, 'Sunday Ride', 'Host Rider', 'seed-host'
);
-- Expect: succeeds, returns {ride: {...}, raw_invite_token: "..."}. Copy both the ride id and
-- the raw token for the steps below.
rollback; -- rollback only if you don't want the fixture ride to persist between runs

-- 2. Nonmember cannot read the ride or its messages ---------------------------------------------
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';
select * from public.group_rides where id = '<RIDE_ID>';           -- Expect: 0 rows
select * from public.group_ride_members where ride_id = '<RIDE_ID>'; -- Expect: 0 rows
select * from public.group_ride_messages where ride_id = '<RIDE_ID>'; -- Expect: 0 rows
rollback;

-- 3. Nonmember cannot join with a wrong token, and the error doesn't reveal ride existence -------
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';
select public.join_group_ride('<RIDE_ID>', 'not-the-real-token', 'Nonmember', 'seed-x');
-- Expect: raises "This invite link is invalid or has expired" — identical message to an invite
-- for a ride ID that doesn't exist at all.
select public.preview_group_ride_invite('00000000-0000-0000-0000-000000000000', 'anything');
-- Expect: same generic error message as above.
rollback;

-- 4. A real member (including an anonymous-auth guest) can join, read, and send a message -------
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
select public.preview_group_ride_invite('<RIDE_ID>', '<RAW_TOKEN>');
-- Expect: destination/route/host/participant-count preview, no membership row created yet.
select public.join_group_ride('<RIDE_ID>', '<RAW_TOKEN>', 'Member Rider', 'seed-member');
-- Expect: succeeds; membership row created with status 'joined'.
select * from public.group_rides where id = '<RIDE_ID>';            -- Expect: 1 row now visible
select * from public.group_ride_members where ride_id = '<RIDE_ID>'; -- Expect: 2 rows (host + self)
insert into public.group_ride_messages (ride_id, sender_user_id, sender_display_name, kind, body, preset_key, client_message_id)
values ('<RIDE_ID>', '22222222-2222-2222-2222-222222222222', 'Member Rider', 'preset', 'All good', 'all_good', gen_random_uuid());
-- Expect: succeeds (active member, sending as self, within length/rate limits).
insert into public.group_ride_messages (ride_id, sender_user_id, sender_display_name, kind, body, preset_key, client_message_id)
values ('<RIDE_ID>', '11111111-1111-1111-1111-111111111111', 'Host Rider', 'preset', 'All good', 'all_good', gen_random_uuid());
-- Expect: DENIED — sender_user_id must equal auth.uid(); a member cannot send as another user.
rollback;

-- 5. A normal member cannot perform host-only mutations ------------------------------------------
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
select public.start_group_ride('<RIDE_ID>');            -- Expect: raises "Only the host can start this ride"
select public.rotate_group_ride_invite('<RIDE_ID>');     -- Expect: raises "Only the host can rotate this invite"
select public.remove_group_ride_member('<RIDE_ID>', '11111111-1111-1111-1111-111111111111');
-- Expect: raises "Only the host can remove a member"
rollback;

-- 6. Member read permissions vs. host-only mutation, positive case for the host ------------------
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select public.start_group_ride('<RIDE_ID>');   -- Expect: succeeds, status -> 'active'
rollback;

-- 7. A member can mark their own membership as left (direct RLS path, defense-in-depth) ----------
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
update public.group_ride_members set status = 'left' where ride_id = '<RIDE_ID>' and user_id = auth.uid();
-- Expect: succeeds (updates exactly one row: the caller's own).
update public.group_ride_members set status = 'left' where ride_id = '<RIDE_ID>' and user_id = '11111111-1111-1111-1111-111111111111';
-- Expect: 0 rows affected — the USING clause excludes rows that aren't the caller's own.
rollback;

-- 8. Expired invite is rejected -------------------------------------------------------------------
-- As postgres/service role, backdate an invite, then attempt to join as an uninvolved user:
-- update public.group_rides set invite_expires_at = now() - interval '1 minute' where id = '<RIDE_ID>';
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';
select public.join_group_ride('<RIDE_ID>', '<RAW_TOKEN>', 'Late Rider', 'seed-late');
-- Expect: raises "This invite link is invalid or has expired".
rollback;

-- 9. Full ride is rejected ------------------------------------------------------------------------
-- As postgres/service role, set max_members to 1 on a ride that already has its host joined,
-- then attempt to join as a different user with a valid token — expect "This group ride is full".

-- 10. Ended ride is rejected ------------------------------------------------------------------------
-- As the host, call end_group_ride, then attempt join_group_ride as a new user with a valid
-- (unexpired) token — expect "This group ride has ended".

-- 11. Realtime channel authorization (requires the project's Realtime Authorization feature) -----
-- From the Supabase dashboard's Realtime inspector, or via two authenticated Swift clients:
--   * A joined member subscribing to `group-ride:<ride-id>` with `isPrivate = true` should
--     receive broadcast/presence events.
--   * An authenticated user who is NOT a member of that ride should have the subscription
--     rejected (or silently receive nothing) when attempting the same topic.
-- This is the one policy in this migration that could not be exercised without a live project;
-- confirm it manually once Realtime Authorization is enabled (see docs/RideTogether.md).
