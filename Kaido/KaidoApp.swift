import SwiftUI

@main
struct KaidoApp: App {
    @State private var bleManager = BikeBLEManager()
    @State private var authState = AuthState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(.kaidoViolet)
                .environment(bleManager)
                .environment(authState)
                .onOpenURL { url in
                    MediaPlayerManager.shared.handleAuthCallback(url)
                }
        }
        .modelContainer(KaidoModelContainer.shared)
        .onChange(of: scenePhase) { _, phase in
            // App Remote drops its connection in the background, so re-establish on return.
            switch phase {
            case .active: MediaPlayerManager.shared.reconnectIfPossible()
            case .background: MediaPlayerManager.shared.disconnect()
            default: break
            }
        }
    }
}
