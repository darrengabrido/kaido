import SwiftUI

struct RootView: View {
    @Environment(AuthState.self) private var authState

    var body: some View {
        Group {
            if authState.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if authState.shouldShowGate {
                AuthGateView()
            } else {
                ContentView()
            }
        }
        .task { await authState.start() }
    }
}
