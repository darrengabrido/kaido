import Foundation

/// How Kaido should choose among cycling route alternatives.
///
/// Mapbox's `cycling` profile already leans toward bike infrastructure. Quiet vs Fast
/// only re-ranks the returned alternatives: Quiet promotes the lowest-stress option;
/// Fast promotes the quickest.
enum RoutingPreference: String, CaseIterable, Identifiable, Sendable {
    case quiet
    case fast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quiet: "Quiet"
        case .fast: "Fast"
        }
    }

    var systemImage: String {
        switch self {
        case .quiet: "leaf.fill"
        case .fast: "bolt.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .quiet: "Prefer quiet routes on dedicated lanes and quieter streets"
        case .fast: "Prefer the fastest route"
        }
    }
}

enum RoutingPreferenceStore {
    private static let key = "kaido.routingPreference"
    private static let legacyKey = "vector.routingPreference"

    static var current: RoutingPreference {
        get {
            let raw = UserDefaults.standard.string(forKey: key)
                ?? UserDefaults.standard.string(forKey: legacyKey)
            guard let raw else { return .quiet }
            // Migrate the previous "calm" preference name.
            if raw == "calm" { return .quiet }
            return RoutingPreference(rawValue: raw) ?? .quiet
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}
