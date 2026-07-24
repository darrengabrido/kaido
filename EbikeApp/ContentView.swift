import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var locationManager = LocationManager()

    var body: some View {
        TabView {
            MapboxMapView(locationManager: locationManager)
                .ignoresSafeArea()
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
