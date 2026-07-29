# Vector

An intelligent ride companion for iOS — turn-by-turn routing, bike lane visualization, custom route planning, and live BLE telemetry from your bike, all in one place.

## Features

- **Turn-by-turn navigation** with recommended route alternatives shown before you commit, powered by the Mapbox Navigation SDK.
- **Cycling map options** — tap the bicycle control to independently show bike lanes and paths or opt into Free Ride mode.
- **Destination search** with rich business/POI results (category, address, icon) via the Mapbox Search Box API.
- **AI discover (free ride mode)** — after the rider explicitly enables Free Ride from the bicycle menu, Vector surfaces nearby parks, cafes, and attractions based on their location. With an OpenAI API key configured, suggestions include short AI-written blurbs explaining why each stop is worth a visit.
- **Custom route planning** — draw a route by tapping waypoints on the map, save it, and revisit it later.
- **Ride history** — routes and past rides persist locally and sync across devices via CloudKit.
- **Live bike telemetry** over Bluetooth LE — speed, cadence, and battery, read from standard Cycling Speed & Cadence and Battery GATT profiles and shown in a heads-up display during navigation.
- **Optional sign-in** — Sign in with Apple or email/password via Supabase Auth, or skip it entirely and ride as a guest. Guest mode is remembered across launches, and you can sign in later from the Bike tab.

## Tech stack

- SwiftUI, targeting iOS 26+
- [Mapbox Maps SDK](https://github.com/mapbox/mapbox-maps-ios) (v11) and [Mapbox Navigation SDK](https://github.com/mapbox/mapbox-navigation-ios) (v3)
- SwiftData with CloudKit sync
- [Supabase Auth](https://github.com/supabase/supabase-swift) (v2) — Sign in with Apple + email/password
- Core Bluetooth (CBCentralManager/CBPeripheral)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — the `.xcodeproj` is generated from `project.yml` and is not checked into git

## Project structure

```
Vector/
├── Auth/            Sign-in screen, session state, Supabase client setup
├── Bluetooth/       BLE manager, telemetry model, bike-connection UI
├── HUD/             In-navigation heads-up display
├── Map/             Main map view, search, bike lane layers/legend, free-ride discover
├── Discover/        AI-curated nearby POI suggestions for free ride mode
├── Models/          SwiftData models (Route, Waypoint, Ride, BikeProfile)
├── Navigation/       Directions/routing and turn-by-turn session view
├── Persistence/      SwiftData model container
├── RoutePlanner/    Route drawing, saved routes list, route detail
└── Theme/           Shared colors and styling
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
   Add your Mapbox token. Supabase credentials are optional — leave them blank and the app still builds and runs, with sign-in disabled and guest mode always available. An OpenAI API key is also optional — without it, free-ride discover still works using nearby Mapbox POIs and built-in suggestion heuristics.
3. Generate the Xcode project:
   ```
   xcodegen generate
   ```
4. Open `Vector.xcodeproj` and run.

To regenerate the project after changing `project.yml` (targets, permissions, entitlements, etc.), just re-run `xcodegen generate`.

### Continuous integration

The `iOS Build` GitHub Actions workflow runs on pull requests, branch pushes, and manual dispatches. It uses a macOS 26 runner with Xcode 26.5, generates the project with XcodeGen, and performs an unsigned iOS Simulator build.

Mapbox's binary SDK dependencies require a private download token even for compilation. Create a secret token with the `DOWNLOADS:READ` scope in the Mapbox dashboard, then add it in GitHub under **Settings → Secrets and variables → Actions** as `MAPBOX_DOWNLOADS_TOKEN`. Do not use the public `pk.` token or place this private token in `Info.plist`.

Supabase and OpenAI credentials are not required for the build check.

### TestFlight deployment

The `Deploy to TestFlight` workflow is manual so a branch push cannot publish a build accidentally. It creates a signed Release archive, uses the workflow run number as the App Store build number, exports an IPA, and uploads it with an App Store Connect API key.

Before running it, create an App Store Connect app for bundle ID `com.darren.vector`, an Apple Distribution certificate, and an App Store provisioning profile that includes the app's CloudKit, push notification, and Sign in with Apple capabilities. Add these GitHub Actions secrets:

| Secret | Value |
| --- | --- |
| `MAPBOX_ACCESS_TOKEN` | Public `pk.` token used by the app at runtime |
| `MAPBOX_DOWNLOADS_TOKEN` | Private Mapbox token with `DOWNLOADS:READ` |
| `APPLE_DISTRIBUTION_CERTIFICATE_BASE64` | Base64-encoded `.p12` distribution certificate |
| `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `APP_STORE_PROVISIONING_PROFILE_BASE64` | Base64-encoded App Store `.mobileprovision` file |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect API key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect API issuer ID |
| `APP_STORE_CONNECT_API_KEY` | Full contents of the API key's `.p8` file |

`SUPABASE_HOST` and `SUPABASE_ANON_KEY` are optional GitHub secrets. The TestFlight workflow intentionally does not embed an OpenAI secret in the app binary; free-ride discovery uses its local fallback until AI requests are routed through a server-side endpoint.

After this workflow is on `master`, open **Actions → Deploy to TestFlight → Run workflow**. A successful upload appears in App Store Connect after Apple's processing finishes.

### Enabling sign-in

1. **Supabase project** — create one, then copy the project host (e.g. `abcdefgh.supabase.co`, without the `https://`) and the `anon`/`public` key from Project Settings → API into `Config/Secrets.xcconfig`. Enable the Email provider under Authentication → Providers.
2. **Apple Developer portal** — Identifiers → App ID `com.darren.vector` → enable the **Sign In with Apple** capability → Save.
3. **Supabase Apple provider** — Authentication → Providers → Apple → enable it and set **Client IDs** to `com.darren.vector`.

Because Vector uses Apple's *native* sign-in (an on-device ID token exchanged via `signInWithIdToken`), the Services ID, `.p8` secret key, and OAuth callback URL are **not** required — those are only for Sign in with Apple on the web.

Sign in with Apple only works end-to-end on a device or simulator signed into an Apple Account.

## Status

Actively in development. Turn-by-turn navigation, bike lane visualization, destination search, route planning, optional sign-in, and the BLE scaffold are all working. Live BLE telemetry has not yet been verified against real bike hardware, and Sign in with Apple has not yet been verified end-to-end against a configured Supabase project.
