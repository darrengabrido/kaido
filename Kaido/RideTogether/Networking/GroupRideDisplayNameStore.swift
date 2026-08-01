import Foundation

/// Locally-remembered Ride Together display name, independent of any permanent account name —
/// Kaido doesn't collect one at sign-up today, and a guest shouldn't be asked twice. Mirrors the
/// `UserDefaults`-backed convention already used by `RoutingPreferenceStore`.
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
