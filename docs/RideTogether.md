# Ride Together

Private group-ride navigation: create a group from a route/destination, invite riders through a
secure link, see each other as live markers during navigation, and exchange safety-oriented quick
messages (preset, custom, or dictated). See the code comments in `Kaido/RideTogether/` for the
detailed rationale behind individual decisions; this document covers setup, architecture, and
what to verify manually.

## Architecture

- **Domain** (`Kaido/RideTogether/Domain`) — plain value types and the explicit state machine
  (`GroupRideStateMachine`). No Mapbox/Supabase imports here except one bridge file
  (`GroupRideRouteSnapshot+RouteOption.swift`) that reads plain properties off `RouteOption`.
- **Networking** (`Kaido/RideTogether/Networking`) — `GroupRideService` (lifecycle RPCs +
  durable message CRUD) and `GroupRideRealtimeClient` (private-channel broadcast/presence) are
  protocols with a `Supabase*` concrete adapter each, plus `GroupRideIdentityProvider` for the
  guest anonymous-session flow. Every concrete adapter is isolated to its own file specifically
  so a Supabase SDK version mismatch is a one-file fix.
- **Session** (`Kaido/RideTogether/Session`) — `GroupRideSessionStore` is the single
  `@MainActor @Observable` coordinator: ride/membership state, the Realtime connection lifecycle,
  and every teardown path. Injected once at the app root (`KaidoApp`) via `.environment(...)`,
  exactly like `AuthState`/`BikeBLEManager`.
- **Location** (`Kaido/RideTogether/Location`) — `GroupRideLocationPublisher` (throttle +
  publish), `GroupRideParticipantLocationStore` (in-memory-only per-rider last-known state +
  staleness), and `NavigationMapViewLocationSource` (reuses the location feed already driving
  Mapbox's puck during active guidance instead of a second `CLLocationManager`).
- **Map** (`Kaido/RideTogether/Map`) — `GroupRideMapOverlayController` renders rider markers on
  the *same* `MapView` Mapbox's `NavigationViewController` already owns (circle + initials label,
  diffed by member ID on a 2s refresh tick), never a second map.
- **Messaging** (`Kaido/RideTogether/Messaging`) — quick-reply/dictation/audio-session
  coordination, entirely local except the durable send/fetch calls in `GroupRideService`.
- **UI** (`Kaido/RideTogether/UI`) — lobby, join preview, participant sheet, quick-message sheet,
  dictation review, incoming banner.
- **Invite** (`Kaido/RideTogether/Invite`) — link building/parsing/redaction.

CloudKit/SwiftData (`Route`, `Ride`, etc.) is untouched except three new optional fields on `Ride`
(`groupRideId`, `groupRideParticipantCount`, `wasGroupRideHost`) — additive, default-backed,
exactly the pattern `BikeProfile` already uses for schema evolution, so existing solo-ride
records are unaffected.

## Required Supabase setup (one-time, external)

Apply in order:

1. Run `supabase/migrations/0001_group_rides.sql` against the project (via the Supabase CLI/`db
   push`, or paste into the SQL editor). It assumes `pgcrypto` is installed in the `extensions`
   schema, which is the Supabase default.
2. **Enable anonymous sign-ins**: Dashboard → Authentication → Providers → enable "Allow anonymous
   sign-ins". Without this, a guest tapping "Ride Together" gets
   `GroupRideIdentityError.signInFailed` instead of a transparent session. This cannot be enabled
   from the repository.
3. **Enable Realtime Authorization (private channels)** for the project, if it isn't already the
   default for the installed Supabase Realtime version. The two policies at the bottom of the
   migration (`group_ride_channel_receive` / `group_ride_channel_send` on `realtime.messages`)
   are the piece of this change that could not be exercised against a live project from this
   environment — verify them once against a real project using the steps in
   `supabase/verification/ride_together_rls_check.sql` (§11).
4. No new environment variables — this reuses `SUPABASE_HOST`/`SUPABASE_ANON_KEY`, already wired
   into `Config/Secrets.xcconfig` and the TestFlight workflow.

## Deep links

No associated domain is configured for this project yet. Invites use the app's existing `kaido://`
custom scheme as a development fallback:

```
kaido://ride-together/join?ride=<ride-id>&token=<invite-token>
```

**For production**, add:
1. An associated domain entitlement (`com.apple.developer.associated-domains`) with
   `applinks:<your-domain>`.
2. An `apple-app-site-association` file hosted at `https://<your-domain>/.well-known/`.
3. Flip `GroupRideInviteParser.isConfiguredAssociatedDomain` and
   `GroupRideInviteLinkBuilder.makeLink` to emit `https://<your-domain>/ride/<ride-id>?token=...`
   instead of the custom scheme. Both already accept either form — no other code changes needed.

## Design decisions worth calling out

- **Joining an active ride is supported**, not restricted to the lobby (per the MVP decision to
  prefer this when the architecture allows it) — `GroupRideStateMachine.joinDenialReason` only
  rejects `ended`/`cancelled`/`full`/`expired`, not "already active."
- **Ride-status changes fan out over the same private Realtime channel** used for locations
  (`ride_status` broadcast event), rather than adding Postgres Changes/CDC as a second Realtime
  primitive. The acting client (almost always the host) broadcasts immediately after a
  start/end/cancel RPC succeeds; a foreground/reconnect refetch is the fallback if that notice is
  ever missed.
- **Sharing an invite during active navigation always rotates it first** — the raw token is
  returned only once, by `create_group_ride`/`rotate_group_ride_invite`, and is deliberately never
  persisted client-side, so there's nothing to re-share without generating a fresh one.
- **Anonymous guest sessions reuse the one shared `KaidoSupabaseClient`** (see
  `GroupRideIdentityProvider`) — no second Supabase client or competing auth store. A permanent
  session, if one exists, is always reused as-is.
- **Bearing on the map**: rider markers show initials in a colored circle, not a rotating
  direction glyph — heading is still shown to the user, in the rider card that opens on tap
  (an SF Symbol rotated by `courseDegrees`), which avoided a second Mapbox imperative-layer
  dependency for comparatively low value in an MVP.

## Manual two-device testing checklist

Requires two simulators/devices, both signed into (or guesting on) the same Supabase project.

1. Device A: search a destination → preview a route → tap **Ride Together** → confirm the lobby
   shows the destination, distance/time, and Device A as host.
2. Device A: tap **Share Invite** → send the link to Device B (Messages/AirDrop/Notes — anything
   the share sheet offers).
3. Device B: open the link → confirm the join preview shows the same destination/route, host
   name, and the location-sharing disclosure → tap **Join Ride Together**.
   - If Device B has no remembered display name, confirm the name prompt appears first and it
     completes the join afterward.
4. Device A: confirm Device B's avatar appears in the lobby's rider list.
5. Device A: tap **Start Ride Together** → both devices should land in their own turn-by-turn
   navigation to the shared destination.
6. On each device, confirm the other rider's marker appears on the map with a stable identity
   (initials, consistent color) and updates smoothly without the map flickering/rebuilding.
7. Force Device B into airplane mode for ~40s, then restore connectivity — confirm Device A's
   view of Device B's marker dims (~8–20s), then disappears from the map (~30s+) while still
   showing "last seen" in the participant sheet, then reappears once B reconnects.
8. Device B: send a preset quick message ("All good") → confirm Device A sees a nonblocking
   banner that doesn't obscure the maneuver instruction, and that it appears in the participant
   sheet's message list.
9. Device A: press-and-hold the mic, say a short phrase, release → confirm the review screen
   shows the transcript and only sends on explicit **Send**; try **Cancel** once too.
10. Device B: tap **Leave Ride Together** → confirm Device B keeps navigating on its own, while
    Device A still shows the ride as active (now with one fewer rider).
11. Device A (host): tap **End Ride Together** → confirm both devices' group UI clears (no more
    remote markers, no group pill) while each device's own turn-by-turn session keeps running
    until separately ended.
12. Repeat step 2–3 with an expired/rotated invite link → confirm Device B sees a clear "invalid
    or expired" message rather than any hint about whether the ride ID exists.

## Known limitations / deferred

- Background delivery is not guaranteed — this reuses the app's existing foreground-oriented
  Realtime connection; a backgrounded device's marker will honestly go stale rather than pretend
  to stay live. No new APNs infrastructure was added (none existed before this feature).
- No leader transfer: the host leaving ends the ride outright, by design for this MVP.
- Rider markers show a static bearing indicator only in the tapped rider card, not a rotating
  glyph on the map itself (see above).
- The realtime channel authorization policies (`realtime.messages`) and the exact
  `supabase-swift` private-channel Broadcast/Presence API surface used in
  `SupabaseGroupRideRealtimeClient` are the two areas most likely to need a small adjustment on
  first real build/run against a live project — both are isolated to single files.
