import SwiftUI

@main
struct EbikeApp: App {
    @State private var bleManager = BikeBLEManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .tint(.routeTeal)
                .environment(bleManager)
        }
        .modelContainer(EbikeModelContainer.shared)
    }
}
