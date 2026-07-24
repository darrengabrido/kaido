import SwiftUI
import SwiftData

struct ContentView: View {
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
        }
        .task {
            locationManager.requestWhenInUseAuthorization()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(EbikeModelContainer.shared)
}
