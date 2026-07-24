import SwiftUI
import SwiftData
import MapboxMaps

struct RouteDetailView: View {
    let route: Route

    @Environment(\.modelContext) private var modelContext
    @Environment(BikeBLEManager.self) private var bleManager
    @State private var viewport: Viewport
    @State private var navigationViewModel = NavigationViewModel()
    @State private var isPresentingNavigation = false

    init(route: Route) {
        self.route = route
        let coordinates = route.orderedWaypoints.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        if coordinates.count > 1 {
            _viewport = State(initialValue: .overview(geometry: LineString(coordinates)))
        } else if let first = coordinates.first {
            _viewport = State(initialValue: .camera(center: first, zoom: 14))
        } else {
            _viewport = State(initialValue: .styleDefault)
        }
    }

    private var coordinates: [CLLocationCoordinate2D] {
        route.orderedWaypoints.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(viewport: $viewport) {
                if coordinates.count > 1 {
                    PolylineAnnotationGroup {
                        PolylineAnnotation(lineCoordinates: coordinates)
                            .lineColor(UIColor(Color.routeTealOnMap))
                            .lineWidth(4)
                    }
                    .lineEmissiveStrength(1)
                }
            }
            .mapStyle(.ebikeNight)
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                Text(route.name)
                    .font(.title2.bold())

                HStack(spacing: 8) {
                    StatTile(value: formattedDistance, label: "distance", tint: .routeTeal)
                    StatTile(value: formattedElevation, label: "ft climb", tint: .effortCoral)
                }

                if let requestError = navigationViewModel.requestError {
                    Text(requestError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    Task {
                        await navigationViewModel.startNavigation(waypointCoordinates: coordinates)
                        if navigationViewModel.navigationRoutes != nil {
                            isPresentingNavigation = true
                        }
                    }
                } label: {
                    if navigationViewModel.isRequestingRoute {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Start Navigation", systemImage: "location.north.line.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(.goGreen)
                .disabled(navigationViewModel.isRequestingRoute || coordinates.count < 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
            .padding()
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    route.isFavorite.toggle()
                } label: {
                    Image(systemName: route.isFavorite ? "star.fill" : "star")
                }
                .tint(.favoriteAmber)
            }
        }
        .fullScreenCover(isPresented: $isPresentingNavigation) {
            if let navigationRoutes = navigationViewModel.navigationRoutes {
                ZStack(alignment: .bottomTrailing) {
                    NavigationSessionView(navigationRoutes: navigationRoutes) { _ in
                        logRide()
                        isPresentingNavigation = false
                        navigationViewModel.clear()
                    }
                    .ignoresSafeArea()

                    RideHUDView(telemetry: bleManager.telemetry)
                        .padding(.trailing, 12)
                        .padding(.bottom, 100)
                }
            }
        }
    }

    private var formattedDistance: String {
        let measurement = Measurement(value: route.distanceMeters, unit: UnitLength.meters)
        return measurement.formatted(.measurement(width: .abbreviated, usage: .road))
    }

    private var formattedElevation: String {
        let measurement = Measurement(value: route.elevationGainMeters, unit: UnitLength.meters)
        let feet = measurement.converted(to: .feet).value
        return feet.formatted(.number.precision(.fractionLength(0)))
    }

    private func logRide() {
        let ride = Ride(route: route)
        ride.endedAt = Date()
        ride.distanceMeters = route.distanceMeters
        modelContext.insert(ride)
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(tint)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(tint.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
