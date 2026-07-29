import SwiftUI

@main
struct KaidoApp: App {
    @State private var bleManager = BikeBLEManager()
    @State private var authState = AuthState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(.kaidoViolet)
                .environment(bleManager)
                .environment(authState)
        }
        .modelContainer(KaidoModelContainer.shared)
    }
}
