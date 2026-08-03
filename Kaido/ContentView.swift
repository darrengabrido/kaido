import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RideTogetherDeepLinkRouter.self) private var rideTogetherDeepLinkRouter
    @State private var locationManager = LocationManager()

    var body: some View {
        TabView {
            // No .ignoresSafeArea() here — MapboxMapView applies it to the map itself so the
            // tiles run full-bleed, while its overlay controls stay inside the safe area.
            MapboxMapView(locationManager: locationManager)
                .tabItem {
                    Label("Map", systemImage: "map")
                }

            RoutesListView()
                .tabItem {
                    Label("Routes", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                }

            BikeConnectionView()
                .tabItem {
                    Label("Bike", systemImage: "bicycle")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
        }
        .task {
            locationManager.requestWhenInUseAuthorization()
            BikeProfileStore.ensureActiveProfile(in: modelContext)
            RiderProfileStore.ensureProfile(in: modelContext)
        }
        .fullScreenCover(isPresented: pendingInviteBinding) {
            if let link = rideTogetherDeepLinkRouter.pendingInvite {
                GroupRideJoinPreviewView(
                    link: link,
                    onJoined: { rideTogetherDeepLinkRouter.clearPendingInvite() },
                    onDismiss: { rideTogetherDeepLinkRouter.clearPendingInvite() }
                )
            }
        }
    }

    private var pendingInviteBinding: Binding<Bool> {
        Binding(
            get: { rideTogetherDeepLinkRouter.pendingInvite != nil },
            set: { isPresented in
                if !isPresented { rideTogetherDeepLinkRouter.clearPendingInvite() }
            }
        )
    }
}

#Preview {
    ContentView()
        .modelContainer(KaidoModelContainer.shared)
}
