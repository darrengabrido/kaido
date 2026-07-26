import SwiftUI

@main
struct VectorApp: App {
    @State private var bleManager = BikeBLEManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .tint(.routeTeal)
                .environment(bleManager)
        }
        .modelContainer(VectorModelContainer.shared)
    }
}
