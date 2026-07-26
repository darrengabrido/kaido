import SwiftUI

@main
struct VectorApp: App {
    @State private var bleManager = BikeBLEManager()
    @State private var authState = AuthState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(.routeTeal)
                .environment(bleManager)
                .environment(authState)
        }
        .modelContainer(VectorModelContainer.shared)
    }
}
