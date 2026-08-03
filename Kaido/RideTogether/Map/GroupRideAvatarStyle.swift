import SwiftUI

/// Deterministic per-rider visual identity derived from `avatarSeed` (defaults to their user ID
/// server-side, see the `create_group_ride`/`join_group_ride` migrations). There's no photo
/// upload feature in this MVP, so a stable initials+color pairing is what keeps a rider
/// recognizable across marker updates and across app launches/devices.
enum GroupRideAvatarStyle {
    /// Deliberately reuses the app's existing route/status palette rather than introducing new
    /// hues, so rider markers read as part of the same visual system as the route line.
    private static let palette: [Color] = [
        .kaidoViolet, .routeBlueOnMap, .routeCoralOnMap, .routeTealOnMap, .statusCaution, .statusGood
    ]

    static func color(for seed: String) -> Color {
        palette[stableIndex(for: seed, count: palette.count)]
    }

    static func initials(for displayName: String) -> String {
        let letters = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let initials = String(letters)
        return initials.isEmpty ? "?" : initials.uppercased()
    }

    /// FNV-1a — deterministic across processes and devices, unlike Swift's `Hasher` (randomly
    /// seeded per launch for DoS resistance, so it can't be used for a *stable* visual identity).
    private static func stableIndex(for seed: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return Int(hash % UInt64(count))
    }
}
