import SwiftUI

@main
struct KaidoApp: App {
    @State private var bleManager = BikeBLEManager()
    @State private var authState = AuthState()
    @State private var rideTogetherSession = GroupRideSessionStore()
    @State private var rideTogetherDeepLinkRouter = RideTogetherDeepLinkRouter()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(.kaidoViolet)
                .environment(bleManager)
                .environment(authState)
                .environment(rideTogetherSession)
                .environment(rideTogetherDeepLinkRouter)
                .onOpenURL { url in
                    MediaPlayerManager.shared.handleAuthCallback(url)
                    rideTogetherDeepLinkRouter.handle(url)
                }
                .task {
                    // Populates the hidden MPVolumeView slider ahead of time so the first tap
                    // of the Now Playing sheet's volume nudge isn't a no-op.
                    SystemVolumeControl.warmUp()
                }
        }
        .modelContainer(KaidoModelContainer.shared)
        .onChange(of: scenePhase) { _, phase in
            // App Remote drops in the background; keep the token and re-establish on return.
            switch phase {
            case .active:
                MediaPlayerManager.shared.reconnectIfPossible()
                AppleMusicManager.shared.refreshAuthorizationStatus()
                Task { await rideTogetherSession.handleAppForeground() }
            case .background:
                MediaPlayerManager.shared.suspendConnection()
            default:
                break
            }
        }
    }
}
