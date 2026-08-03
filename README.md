# Kaido

An intelligent ride companion for iOS — turn-by-turn routing, bike lane visualization, custom route planning, and live BLE telemetry from your bike, all in one place.

App Store listing name: **Kaido Ride**. Home-screen / brand name: **Kaido**.

Bundle ID: `com.oaktreehouse.kaido`

## Features

- **Turn-by-turn navigation** with recommended route alternatives shown before you commit, powered by the Mapbox Navigation SDK.
- **Cycling map options** — tap the bicycle control to independently show bike lanes and paths or opt into Free Ride mode.
- **Destination search** with rich business/POI results (category, address, icon) via the Mapbox Search Box API.
- **AI discover (free ride mode)** — after the rider explicitly enables Free Ride from the bicycle menu, Kaido surfaces nearby parks, cafes, and attractions based on their location. With an OpenAI API key configured, suggestions include short AI-written blurbs explaining why each stop is worth a visit.
- **Custom route planning** — draw a route by tapping waypoints on the map, save it, and revisit it later.
- **Ride history** — routes and past rides persist locally and sync across devices via CloudKit.
- **Live bike telemetry** over Bluetooth LE — speed, cadence, and battery, read from standard Cycling Speed & Cadence and Battery GATT profiles and shown in a heads-up display during navigation.
- **Optional sign-in** — Sign in with Apple or email/password via Supabase Auth, or skip it entirely and ride as a guest. Guest mode is remembered across launches, and you can sign in later from the Bike tab.
- **Ride Together** — invite-only group navigation: create a group from a route or destination, share a secure invite link, see other riders as live markers during turn-by-turn navigation, and send safety-oriented quick messages (preset, custom, or dictated). Guests get a transparent, feature-scoped anonymous session rather than being asked to create an account. See [`docs/RideTogether.md`](docs/RideTogether.md) for architecture, required Supabase setup, and a manual testing checklist.

## Tech stack

- SwiftUI, targeting iOS 26+
- [Mapbox Maps SDK](https://github.com/mapbox/mapbox-maps-ios) (v11) and [Mapbox Navigation SDK](https://github.com/mapbox/mapbox-navigation-ios) (v3)
- SwiftData with CloudKit sync
- [Supabase Auth](https://github.com/supabase/supabase-swift) (v2) — Sign in with Apple + email/password, plus anonymous sessions for Ride Together guests
- Supabase Database + Realtime (Broadcast/Presence) — Ride Together group state and live rider locations
- Core Bluetooth (CBCentralManager/CBPeripheral)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — the `.xcodeproj` is generated from `project.yml` and is not checked into git

## Project structure

```
Kaido/
├── Auth/            Sign-in screen, session state, Supabase client setup
├── Bluetooth/       BLE manager, telemetry model, bike-connection UI
├── HUD/             In-navigation heads-up display
├── Map/             Main map view, search, bike lane layers/legend, free-ride discover
├── Discover/        AI-curated nearby POI suggestions for free ride mode
├── Models/          SwiftData models (Route, Waypoint, Ride, BikeProfile)
├── Navigation/      Directions/routing and turn-by-turn session view
├── Persistence/     SwiftData model container
├── RideTogether/    Group-ride domain, Supabase networking, session/location/map/messaging
├── RoutePlanner/    Route drawing, saved routes list, route detail
└── Theme/           Shared colors and styling

KaidoTests/          Unit tests (state machine, throttling, staleness, dedup, deep links, ...)
supabase/            SQL migrations + a manual RLS/RPC verification script for Ride Together
docs/                Feature docs (Ride Together architecture, setup, testing checklist)
```

## Getting started

### Prerequisites

- Xcode 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- A [Mapbox](https://www.mapbox.com/) account and public access token
- Optional: a [Supabase](https://supabase.com/) project, if you want sign-in enabled

### Setup

1. Clone the repo.
2. Copy the secrets template and fill it in:
   ```
   cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
   ```
   Set `DEVELOPMENT_TEAM` to your 10-character Apple Team ID and add your Mapbox token. Supabase credentials are optional — leave them blank and the app still builds and runs, with sign-in disabled and guest mode always available. An OpenAI API key is also optional — without it, free-ride discover still works using nearby Mapbox POIs and built-in suggestion heuristics.
3. Generate the Xcode project:
   ```
   xcodegen generate
   ```
4. Open `Kaido.xcodeproj` and run.

To regenerate the project after changing `project.yml` (targets, permissions, entitlements, etc.), just re-run `xcodegen generate`.

### Continuous integration

The `iOS Build` GitHub Actions workflow runs on pull requests, branch pushes, and manual dispatches. It uses a macOS 26 runner with Xcode 26.5, generates the project with XcodeGen, and performs an unsigned iOS Simulator build.

Mapbox's binary SDK dependencies require a private download token even for compilation. Create a secret token with the `DOWNLOADS:READ` scope in the Mapbox dashboard, then add it in GitHub under **Settings → Secrets and variables → Actions** as `MAPBOX_DOWNLOADS_TOKEN`. Do not use the public `pk.` token or place this private token in `Info.plist`.

Supabase and OpenAI credentials are not required for the build check.

### TestFlight deployment

The `Deploy to TestFlight` workflow is manual so a branch push cannot publish a build accidentally. It creates a signed Release archive, uses the workflow run number as the App Store build number, exports an IPA, and uploads it with an App Store Connect API key.

Before running it, confirm App Store Connect has **Kaido Ride** for bundle ID `com.oaktreehouse.kaido`, then create an Apple Distribution certificate and an App Store provisioning profile that includes CloudKit, push notifications, and Sign in with Apple. Add these GitHub Actions secrets:

| Secret | Value |
| --- | --- |
| `APPLE_TEAM_ID` | 10-character Apple Team ID |
| `MAPBOX_ACCESS_TOKEN` | Public `pk.` token used by the app at runtime |
| `MAPBOX_DOWNLOADS_TOKEN` | Private Mapbox token with `DOWNLOADS:READ` |
| `APPLE_DISTRIBUTION_CERTIFICATE_BASE64` | Base64-encoded `.p12` distribution certificate |
| `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `APP_STORE_PROVISIONING_PROFILE_BASE64` | Base64-encoded App Store `.mobileprovision` for `com.oaktreehouse.kaido` |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect API **Team** key ID (not an Individual key) |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect API issuer ID |
| `APP_STORE_CONNECT_API_KEY` | Full contents of that Team key's `.p8` file (including `BEGIN`/`END` lines) |
| `SUPABASE_HOST` | Supabase host only (e.g. `abcdefgh.supabase.co`, no `https://`) |
| `SUPABASE_ANON_KEY` | Supabase `anon`/`public` API key |
| `SPOTIFY_CLIENT_ID` | Spotify app Client ID (Redirect URI must be `kaido://spotify-callback`) |

The App Store provisioning profile must include the **iCloud** container `iCloud.com.oaktreehouse.kaido` (CloudKit), **Push Notifications**, and **Sign in with Apple**. If archive fails with an iCloud container mismatch, edit the App ID in the Apple Developer portal, regenerate the App Store profile, and update `APP_STORE_PROVISIONING_PROFILE_BASE64`.

The TestFlight workflow intentionally does not embed an OpenAI secret in the app binary; free-ride discovery uses its local fallback until AI requests are routed through a server-side endpoint.

After the workflow is available on your branch, open **Actions → Deploy to TestFlight → Run workflow**. A successful upload appears in App Store Connect after Apple's processing finishes.

If the `Upload to TestFlight` step fails with `NOT_AUTHORIZED` / status 401, `altool` could not build a valid bearer token from the three `APP_STORE_CONNECT_*` secrets — this is a credential problem, not a workflow bug (`altool` only supports Team API keys; Individual API keys are not accepted for any authenticated call, so there is no alternate auth mode to fall back to). In App Store Connect → **Users and Access → Integrations → App Store Connect API**, confirm the key's status is **Active** and its role is **Admin** or **App Manager**, re-copy the Key ID and Issuer ID from that page, and regenerate the key if there's any doubt about the `.p8` (Apple only allows downloading it once). Update all three secrets together, and check **Settings → Environments → testflight** for a same-named secret shadowing the repo-level one — environment secrets take precedence.

### Enabling sign-in

1. **Supabase project** — create one, then copy the project host (e.g. `abcdefgh.supabase.co`, without the `https://`) and the `anon`/`public` key from Project Settings → API into `Config/Secrets.xcconfig`. Enable the Email provider under Authentication → Providers.
2. **Apple Developer portal** — Identifiers → App ID `com.oaktreehouse.kaido` → enable the **Sign In with Apple** capability → Save.
3. **Supabase Apple provider** — Authentication → Providers → Apple → enable it and set **Client IDs** to `com.oaktreehouse.kaido`.

Because Kaido uses Apple's *native* sign-in (an on-device ID token exchanged via `signInWithIdToken`), the Services ID, `.p8` secret key, and OAuth callback URL are **not** required — those are only for Sign in with Apple on the web.

Sign in with Apple only works end-to-end on a device or simulator signed into an Apple Account.

### Enabling Ride Together

Reuses the same Supabase project as sign-in — no separate project needed. See
[`docs/RideTogether.md`](docs/RideTogether.md) for the full setup (applying
`supabase/migrations/0001_group_rides.sql`, enabling anonymous sign-ins, and confirming Realtime
Authorization), plus a two-device manual testing checklist.

### Running tests

`KaidoTests` covers Ride Together's pure domain/state logic (state machine, route-snapshot
Codable round trip, location throttling/staleness, message dedup, deep-link parsing, invite-token
redaction) against fakes — no live Supabase project, network access, or GPS required:

```
xcodebuild -project Kaido.xcodeproj -scheme Kaido -destination "platform=iOS Simulator,name=iPhone 16" test
```

The `iOS Build` GitHub Actions workflow runs this on every push/PR alongside the existing build.

## Status

Actively in development. Turn-by-turn navigation, bike lane visualization, destination search, route planning, optional sign-in, the BLE scaffold, and an initial Ride Together group-navigation MVP are all working. Live BLE telemetry has not yet been verified against real bike hardware, Sign in with Apple has not yet been verified end-to-end against a configured Supabase project, and Ride Together's Supabase Realtime integration has not yet been exercised against a live project from this environment (see `docs/RideTogether.md`'s Known limitations).
