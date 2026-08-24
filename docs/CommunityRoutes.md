# Community Routes

The Routes tab's "Community" section: a browsable feed of bike routes shared by other riders,
plus a small hand-curated seed catalog bundled with the app. Tapping a route opens a read-only
preview; "Add to My Routes" copies it into the rider's own local, SwiftData-backed routes, after
which it behaves exactly like any other saved route (navigate, Ride Together, favorite, delete).
See the code comments in `Kaido/RoutePlanner/Community/` for the detailed rationale behind
individual decisions; this document covers setup, architecture, and what to verify manually.

## Architecture

- **Domain** (`Kaido/RoutePlanner/Community/CommunityRoute.swift`) — `CommunityRoute`, a plain
  `Codable` value type mirroring the `community_routes` table columns exactly (see the migration
  below), plus `CommunityRouteStatus`.
- **Seed content** (`Kaido/RoutePlanner/Community/CuratedCommunityRoutes.swift`) — a dozen
  well-known, real routes (heavily weighted toward California) bundled directly into the app, each
  with distance/elevation from a single cited official or GPS-tracked source and waypoints at real,
  verified landmark coordinates. Shaped as ordinary `CommunityRoute` values with a fixed, never-real
  `authorUserId` sentinel so they're always shown but never editable/removable by anyone.
- **Networking** (`Kaido/RoutePlanner/Community/CommunityRouteService.swift`,
  `SupabaseCommunityRouteService.swift`) — `CommunityRouteService` is a protocol
  (`fetchPublished`/`publish`/`remove`) with three conformers:
  - `CuratedCommunityRouteService` — read-only wrapper around the bundled catalog.
  - `SupabaseCommunityRouteService` — talks to the `community_routes` table, following the same
    conventions as `SupabaseGroupRideService` (explicit `CodingKeys`, an explicit `wireDecoder`,
    reusing `PostgresDate.parse`). Resolves an identity via
    `SupabaseGroupRideIdentityProvider().ensureIdentity()` before publishing — deliberately reusing
    Ride Together's guest-anonymous-session flow rather than duplicating it, since both features
    need exactly the same thing: a stable `auth.uid()` for RLS that a guest never has to notice as
    "creating an account".
  - `CompositeCommunityRouteService` — what the app actually injects by default. Browsing merges
    the curated catalog (always available, even offline) with whatever's been published to
    Supabase; publishing/removing always go straight to the backend.
- **View model** (`CommunityRoutesViewModel.swift`) — `@Observable @MainActor`; `load()`/
  `refresh()`, `isMine(_:)` (compares against a `currentUserId` resolved once via the identity
  provider, never forcing a sign-in just to browse), `publish(from:description:displayName:)`,
  `remove(_:)`.
- **UI** (`CommunityRoutesListView.swift`, `CommunityRouteDetailView.swift`,
  `ShareRouteToCommunitySheet.swift`) — list with a swipe-to-remove action shown only on the
  current rider's own published routes, a read-only detail/preview screen, and the publish sheet
  presented from `RouteDetailView`'s toolbar.

SwiftData (`Route`) is untouched except one new optional field, `sharedCommunityRouteId: UUID?` —
additive, default-backed `nil`, the same pattern already used for `Ride.groupRideId`, so existing
routes saved before this feature existed are unaffected.

## Required Supabase setup (one-time, external)

Community routes reuse the same Supabase project as sign-in and Ride Together — no separate
project needed.

1. Run `supabase/migrations/0002_community_routes.sql` against the project (via the Supabase
   CLI/`db push`, or paste into the SQL editor). It assumes `pgcrypto` is installed in the
   `extensions` schema, which is the Supabase default.
2. **Enable anonymous sign-ins**: Dashboard → Authentication → Providers → enable "Allow anonymous
   sign-ins", if not already enabled for Ride Together. Without this, a guest tapping "Share to
   Community" gets a "you need to be signed in" error instead of a transparent session. This
   cannot be enabled from the repository.
3. No new environment variables — this reuses `SUPABASE_HOST`/`SUPABASE_ANON_KEY`, already wired
   into `Config/Secrets.xcconfig` and the TestFlight workflow.

Without a configured Supabase project, the Community section still works — it shows only the
bundled curated catalog, and "Share to Community" fails with a clear "not configured" message
rather than a confusing network error.

## Design decisions worth calling out

- **Curated seed content and user-published routes share one model and one feed.** Rather than
  bolt user-publishing onto a purely curated catalog (or vice versa), `CompositeCommunityRouteService`
  merges both: the feed is never empty (even offline, or before any rider has published a route),
  and every published route behaves identically to a curated one from the UI's perspective — same
  row, same detail screen, same "Add to My Routes" action. The only functional difference is that
  `isMine`/"Remove from Community" can never apply to a curated route, since its `authorUserId` is
  a fixed sentinel that will never equal a real `auth.uid()`.
- **Removing a published route is a hard delete**, not a `status = 'removed'` soft-delete. The
  `status` column and its RLS-select carve-out (`... or author_user_id = auth.uid()`) exist so a
  future moderation pass has somewhere to land a "removed" state without a schema change, but
  nothing sets it today — republish-by-removing-and-resharing is the escape hatch for editing a
  published route's content.
- **Browsing is public** (no sign-in/guest session required) — the community feed is a discovery
  surface, so its `select` RLS policy grants `anon` as well as `authenticated`. Publishing still
  requires an identity, and reuses Ride Together's `GroupRideIdentityProvider`/
  `GroupRideDisplayNameStore` — worth calling out given the `GroupRide*` naming, since neither is
  Ride-Together-specific in practice.
- **No likes/saves counters, no comments, no moderation/reporting, no "nearby" geo search** in this
  pass — see Known limitations below. `start_latitude`/`start_longitude` columns are stored so
  "nearby" sorting can be added later without a migration.

## Manual testing checklist

Requires a Supabase project with `0002_community_routes.sql` applied and anonymous sign-ins
enabled.

1. With no Supabase project configured at all, open the Routes tab → Community section → confirm
   the bundled curated routes still show up, previews still render, and "Add to My Routes" still
   works.
2. As a guest (no prior sign-in), save a custom route, open it, tap **Share to Community** →
   confirm the display-name prompt appears once, then the publish sheet → publish → confirm the
   toolbar action switches to "Remove from Community" on that route.
3. Switch to the Community section → confirm the just-published route appears after the curated
   ones, with the right name/distance/author/relative time, and swipe-to-remove is available on it.
4. On a second account (or after signing out and back in as someone else), confirm the same
   published route shows up in the Community feed but has **no** swipe-to-remove action.
5. Back on the original account/device, swipe-to-remove the published route from the list (or tap
   "Remove from Community" from the route's detail view's toolbar) → confirm it disappears from
   the feed and the local route's toolbar action switches back to "Share to Community".
6. Confirm the second account's attempt to remove or edit the first account's route is rejected
   (RLS `update`/`delete` policies) if exercised directly (e.g. via the SQL editor with that user's
   JWT), to sanity-check the ownership policies independent of what the UI currently exposes.
7. Turn off networking (Airplane Mode) mid-publish → confirm the sheet surfaces a readable error
   and the local route is left unmodified (`sharedCommunityRouteId` stays `nil`).

## Known limitations / deferred

- Save/like counts, comments, reporting/moderation.
- "Nearby" geo-filtered browsing (columns are in place, query isn't).
- Editing a published route's route geometry after publish (only name/description are editable
  via this flow at all, and only indirectly by removing and resharing).
- The RLS policies in `supabase/migrations/0002_community_routes.sql` and
  `SupabaseCommunityRouteService`'s exact `supabase-swift` query-builder surface are the parts most
  likely to need a small adjustment on first real build/run against a live project — both are
  isolated to a single migration file and a single service file, respectively.
