import Foundation

/// Locally-remembered display name, independent of any permanent account name — Kaido doesn't
/// collect one at sign-up today, and a guest shouldn't be asked twice. Mirrors the
/// `UserDefaults`-backed convention already used by `RoutingPreferenceStore`.
///
/// Originally built for Ride Together (hence the name), and reused as-is by "Share to Community"
/// (`RouteDetailView`/`ShareRouteToCommunitySheet`) — both features need exactly the same thing:
/// a name shown to other riders, remembered once so a guest is never asked twice.
enum GroupRideDisplayNameStore {
    private static let key = "kaido.rideTogether.displayName"

    static var current: String? {
        get {
            let value = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (value?.isEmpty ?? true) ? nil : value
        }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                UserDefaults.standard.set(trimmed, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}
