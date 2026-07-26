import SwiftUI

extension Color {
    // MARK: Brand

    /// The primary brand accent — interactive controls, primary CTAs, and the global tint.
    static let vectorViolet = Color(red: 0x7B / 255, green: 0x4D / 255, blue: 0xE0 / 255)

    /// Deep indigo used in brand backdrops (e.g. the landing screen's aurora gradient).
    static let vectorIndigo = Color(red: 0x2A / 255, green: 0x1E / 255, blue: 0x66 / 255)

    /// Violet-tinted near-black base behind brand gradients.
    static let vectorMidnight = Color(red: 0x08 / 255, green: 0x07 / 255, blue: 0x12 / 255)

    // MARK: Data & status

    /// Distance and the route path itself — used consistently for distance stats and the Routes tab.
    static let routeTeal = Color(red: 0x1F / 255, green: 0xB8 / 255, blue: 0x8A / 255)

    /// Brighter variant of `routeTeal` for lines/markers drawn directly on the map — Mapbox's night light
    /// preset dims custom layer colors along with everything else on the canvas, so annotations need extra
    /// brightness to still read clearly against it.
    static let routeTealOnMap = Color(red: 0x3C / 255, green: 0xE6 / 255, blue: 0xB4 / 255)

    /// Physical effort — elevation climb, cadence, power.
    static let effortCoral = Color(red: 0xF0 / 255, green: 0x66 / 255, blue: 0x3A / 255)

    /// Time and speed.
    static let paceBlue = Color(red: 0x4A / 255, green: 0x9E / 255, blue: 0xF0 / 255)

    /// An active/live state — connected hardware, a live telemetry feed. (Primary CTAs use `vectorViolet`.)
    static let goGreen = Color(red: 0x5E / 255, green: 0xB8 / 255, blue: 0x2E / 255)

    /// Favorited routes.
    static let favoriteAmber = Color(red: 0xF0 / 255, green: 0xA8 / 255, blue: 0x2E / 255)
}
