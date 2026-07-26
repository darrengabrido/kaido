# Vector

An iOS navigation app for ebike riders — turn-by-turn routing, bike lane visualization, custom route planning, and live BLE telemetry from your bike, all in one place.

## Features

- **Turn-by-turn navigation** with recommended route alternatives shown before you commit, powered by the Mapbox Navigation SDK.
- **Bike lane visualization** on the map — dedicated cycle paths and on-street painted lanes are rendered with distinct styles and a legend, toggleable on both the main map and the route planner.
- **Destination search** with rich business/POI results (category, address, icon) via the Mapbox Search Box API.
- **Custom route planning** — draw a route by tapping waypoints on the map, save it, and revisit it later.
- **Ride history** — routes and past rides persist locally and sync across devices via CloudKit.
- **Live bike telemetry** over Bluetooth LE — speed, cadence, and battery, read from standard Cycling Speed & Cadence and Battery GATT profiles and shown in a heads-up display during navigation.

## Tech stack

- SwiftUI, targeting iOS 26+
- [Mapbox Maps SDK](https://github.com/mapbox/mapbox-maps-ios) (v11) and [Mapbox Navigation SDK](https://github.com/mapbox/mapbox-navigation-ios) (v3)
- SwiftData with CloudKit sync
- Core Bluetooth (CBCentralManager/CBPeripheral)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — the `.xcodeproj` is generated from `project.yml` and is not checked into git

## Project structure

```
Vector/
├── Bluetooth/       BLE manager, telemetry model, bike-connection UI
├── HUD/             In-navigation heads-up display
├── Map/             Main map view, search, bike lane layers/legend
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

### Setup

1. Clone the repo.
2. Copy the secrets template and add your Mapbox token:
   ```
   cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
   ```
   then edit `Config/Secrets.xcconfig` and paste in your token.
3. Generate the Xcode project:
   ```
   xcodegen generate
   ```
4. Open `Vector.xcodeproj` and run.

To regenerate the project after changing `project.yml` (targets, permissions, entitlements, etc.), just re-run `xcodegen generate`.

## Status

Actively in development. Turn-by-turn navigation, bike lane visualization, destination search, route planning, and the BLE scaffold are all working. Live BLE telemetry has not yet been verified against real bike hardware.
