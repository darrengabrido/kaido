import SwiftUI

extension Color {
    // MARK: Brand

    /// The primary brand accent — interactive controls, primary CTAs, and the global tint.
    static let kaidoViolet = Color(red: 0x7B / 255, green: 0x4D / 255, blue: 0xE0 / 255)

    /// Brighter variant of `kaidoViolet` for the route line drawn on the map — Mapbox's night light
    /// preset dims custom layer colors, so the route needs extra brightness to stay visible against it.
    static let kaidoVioletOnMap = Color(red: 0xA4 / 255, green: 0x7D / 255, blue: 0xFF / 255)

    /// Deep indigo used in brand backdrops (e.g. the landing screen's aurora gradient).
    static let kaidoIndigo = Color(red: 0x2A / 255, green: 0x1E / 255, blue: 0x66 / 255)

    /// Violet-tinted near-black base behind brand gradients.
    static let kaidoMidnight = Color(red: 0x08 / 255, green: 0x07 / 255, blue: 0x12 / 255)

    // MARK: Data & status

    /// Distance — used consistently for distance stats and the Routes tab.
    static let routeTeal = Color(red: 0x1F / 255, green: 0xB8 / 255, blue: 0x8A / 255)

    /// Bike lane / dedicated cycle path infrastructure drawn on the map — brighter than `routeTeal`
    /// since Mapbox's night light preset dims custom layer colors along with everything else on the
    /// canvas. Deliberately distinct from `kaidoViolet` (the drawn/ridden route line itself), so a
    /// route stays legible against the bike lanes it runs along instead of blending into them.
    static let routeTealOnMap = Color(red: 0x3C / 255, green: 0xE6 / 255, blue: 0xB4 / 255)

    /// Physical effort — elevation climb, cadence, power.
    static let effortCoral = Color(red: 0xF0 / 255, green: 0x66 / 255, blue: 0x3A / 255)

    /// Time and speed.
    static let paceBlue = Color(red: 0x4A / 255, green: 0x9E / 255, blue: 0xF0 / 255)

    /// An active/live state — connected hardware, a live telemetry feed. (Primary CTAs use `kaidoViolet`.)
    static let goGreen = Color(red: 0x5E / 255, green: 0xB8 / 255, blue: 0x2E / 255)

    /// Favorited routes.
    static let favoriteAmber = Color(red: 0xF0 / 255, green: 0xA8 / 255, blue: 0x2E / 255)
}
