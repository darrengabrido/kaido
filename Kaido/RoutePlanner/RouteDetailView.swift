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
    @State private var showBikeLanes = true

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
                if showBikeLanes {
                    VectorSource(id: "streets-v8")
                        .url("mapbox://mapbox.mapbox-streets-v8")
                    // On-street painted bike lane — drawn on the road's own centerline (bike_lane field),
                    // dashed so it reads as "lane within the road" rather than a separate path.
                    LineLayer(id: "bike-onstreet-lane", source: "streets-v8")
                        .sourceLayer("road")
                        .filter(Exp(.any) {
                            Exp(.eq) { Exp(.get) { "bike_lane" }; "yes" }
                            Exp(.eq) { Exp(.get) { "bike_lane" }; "left" }
                            Exp(.eq) { Exp(.get) { "bike_lane" }; "right" }
                            Exp(.eq) { Exp(.get) { "bike_lane" }; "both" }
                        })
                        .lineColor(StyleColor(UIColor(Color.routeTealOnMap)))
                        .lineWidth(3.0)
                        .lineOpacity(0.95)
                        .lineEmissiveStrength(1)
                        .lineCap(.butt)
                        .lineJoin(.round)
                        .lineDashArray([2, 2])
                        .slot(.top)
                    // Dedicated, physically-separated cycle path — solid and thicker
                    LineLayer(id: "bike-dedicated-path", source: "streets-v8")
                        .sourceLayer("road")
                        .filter(Exp(.eq) { Exp(.get) { "type" }; "cycleway" })
                        .lineColor(StyleColor(UIColor(Color.routeTealOnMap)))
                        .lineWidth(4.5)
                        .lineOpacity(1.0)
                        .lineEmissiveStrength(1)
                        .lineCap(.round)
                        .lineJoin(.round)
                        .slot(.top)
                }

                if coordinates.count > 1 {
                    RouteGlowPolyline(coordinates: coordinates)
                }
            }
            .mapStyle(.kaidoNight)
            .ignoresSafeArea()

            VStack(alignment: .trailing, spacing: 8) {
                Button {
                    showBikeLanes.toggle()
                } label: {
                    Image(systemName: "bicycle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(showBikeLanes ? Color.routeTeal : Color.secondary)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular, in: Circle())

                if showBikeLanes {
                    BikeLaneLegend()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, 12)
            .padding(.trailing, 16)

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
                        await navigationViewModel.requestRoutes(waypointCoordinates: coordinates)
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
                .tint(.kaidoViolet)
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
