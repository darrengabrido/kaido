import Foundation

/// Per-user Ride Together messaging preferences, stored locally like `RoutingPreferenceStore` —
/// never synced as part of any ride's shared state.
enum GroupRideMessagingPreferences {
    private static let readAloudKey = "kaido.rideTogether.readMessagesAloud"

    /// "Read group messages aloud during navigation." Off by default — existing product
    /// behavior has no precedent for speaking anything other than Mapbox's own turn guidance,
    /// so an unprompted new voice during navigation should be something a rider opts into.
    static var readMessagesAloud: Bool {
        get { UserDefaults.standard.bool(forKey: readAloudKey) }
        set { UserDefaults.standard.set(newValue, forKey: readAloudKey) }
    }
}
