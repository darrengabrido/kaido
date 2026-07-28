import Foundation

/// How Vector should choose among cycling route alternatives.
///
/// Mapbox's `cycling` profile already leans toward bike infrastructure. Calm vs Fast
/// sharpens that: Calm avoids ferries and promotes the lowest-stress alternative;
/// Fast keeps the request unconstrained and promotes the quickest alternative.
enum RoutingPreference: String, CaseIterable, Identifiable, Sendable {
    case calm
    case fast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calm: "Calm"
        case .fast: "Fast"
        }
    }

    var systemImage: String {
        switch self {
        case .calm: "leaf.fill"
        case .fast: "bolt.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .calm: "Prefer calm routes on dedicated lanes and quieter streets"
        case .fast: "Prefer the fastest route"
        }
    }
}

enum RoutingPreferenceStore {
    private static let key = "vector.routingPreference"

    static var current: RoutingPreference {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let preference = RoutingPreference(rawValue: raw)
            else { return .calm }
            return preference
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}
