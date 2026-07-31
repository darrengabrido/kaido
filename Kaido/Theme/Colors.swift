import SwiftUI

// "Instrument" — a near-monochrome palette in the spirit of a high-end bike computer.
//
// The thesis: neutrals carry the screen, and colour is spent sparingly enough that it means
// something when it appears. Data is rendered in warm off-white and separated by size and weight
// rather than hue; violet survives in exactly one job — your route and the controls you touch.
//
// Three layers, and they don't borrow from each other:
//
//   Neutrals — the ground and nearly all data. Warm off-white and warm near-black, never pure
//              #FFF/#000, which is most of what separates "premium" from "default".
//   Accent   — one. Violet means "this is your route, or this is yours to touch."
//   Status   — muted sage / brass / clay. Serious rather than alarming, and never used to label a
//              quantity.
//
// The app is pinned to `.preferredColorScheme(.dark)`, so these are tuned for dark only.
extension Color {
    // MARK: Neutrals

    /// The ground — a warm-tinted near-black. Pure black reads flat and cheap under glass, and
    /// gives the material nothing to refract.
    static let kaidoMidnight = Color(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0C / 255)

    /// Primary data and text — a warm off-white. This is the hero: speed, time, street names.
    static let kaidoInk = Color(red: 0xF2 / 255, green: 0xF0 / 255, blue: 0xEC / 255)

    /// Secondary data, labels, and units. Carries everything that supports the hero number.
    static let kaidoDim = Color(red: 0x8B / 255, green: 0x8A / 255, blue: 0x93 / 255)

    /// Deep indigo behind brand gradients (the landing screen's aurora).
    static let kaidoIndigo = Color(red: 0x2A / 255, green: 0x22 / 255, blue: 0x66 / 255)

    // MARK: Accent

    /// The single accent — the route line, the maneuver arrow, interactive controls, global tint.
    /// Softened from the old violet so it reads as pigment rather than plastic.
    static let kaidoViolet = Color(red: 0x9B / 255, green: 0x8C / 255, blue: 0xFF / 255)

    /// Brighter accent for the route drawn on the map — Mapbox's night preset dims custom layers,
    /// and translucent glass lightens what sits on it. Use this variant on *any* non-solid surface,
    /// not just the map: the base violet only clears ~3.4:1 over glass, this clears ~7.7:1.
    static let kaidoVioletOnMap = Color(red: 0xB9 / 255, green: 0xAE / 255, blue: 0xFF / 255)

    /// Distinct alternate-route colours. They are intentionally separate from the mint used for
    /// bike infrastructure, so a rider can compare route choices without mistaking an alternate
    /// for a bike lane.
    static let routeBlueOnMap = Color(red: 0x70 / 255, green: 0xC6 / 255, blue: 0xFF / 255)
    static let routeCoralOnMap = Color(red: 0xFF / 255, green: 0xAF / 255, blue: 0x82 / 255)

    // MARK: Status
    //
    // State, not category — battery level, hardware connection, warnings. Muted on purpose: an
    // alert should read as serious, not as a toy. The only greens/yellows/reds in the system.

    /// Healthy — connected hardware, a live feed, comfortable battery.
    static let statusGood = Color(red: 0x7F / 255, green: 0xB8 / 255, blue: 0x8A / 255)

    /// Needs attention soon — battery getting low.
    static let statusCaution = Color(red: 0xD9 / 255, green: 0xA4 / 255, blue: 0x41 / 255)

    /// Critical — nearly flat, dropped connection, the End action.
    static let statusCritical = Color(red: 0xC9 / 255, green: 0x64 / 255, blue: 0x5E / 255)

    // MARK: Map canvas
    //
    // The map is the one place restraint has to yield: a line drawn over cartography needs enough
    // chroma to be read as infrastructure rather than as another road.

    /// Bike lanes and dedicated cycle paths on the night map. A luminous mint that sits
    /// beside the violet route without competing — bright enough to read over asphalt and
    /// the route glow, cool enough to feel like infrastructure rather than another accent.
    static let routeTealOnMap = Color(red: 0x6E / 255, green: 0xE0 / 255, blue: 0xC4 / 255)

    /// Off-map mint for bike-lane chrome (toggles, discover chips) that should match infrastructure.
    static let routeTeal = Color(red: 0x1F / 255, green: 0xB8 / 255, blue: 0x8A / 255)
}
