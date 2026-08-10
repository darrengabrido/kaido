import SwiftUI
import SwiftData
import MapboxMaps

/// Read-only preview of a curated community route. The only action here is "Add to My Routes" —
/// once copied into a local `Route`, it's a normal saved route and picks up navigation, Ride
/// Together, favoriting, etc. from `RouteDetailView` for free, so none of that logic is duplicated
/// here.
struct CommunityRouteDetailView: View {
    let route: CommunityRoute

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewport: Viewport
    @State private var showBikeLanes = true

    init(route: CommunityRoute) {
        self.route = route
        let coordinates = route.coordinates
        if coordinates.count > 1 {
            _viewport = State(initialValue: .overview(geometry: LineString(coordinates)))
        } else if let first = coordinates.first {
            _viewport = State(initialValue: .camera(center: first, zoom: 13))
        } else {
            _viewport = State(initialValue: .styleDefault)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(viewport: $viewport) {
                if showBikeLanes {
                    BikeLaneMapLayers()
                }
                if route.coordinates.count > 1 {
                    RouteGlowPolyline(coordinates: route.coordinates)
                }
            }
            .mapStyle(.kaidoNight)
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    showBikeLanes.toggle()
                } label: {
                    Image(systemName: "bicycle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(showBikeLanes ? Color.kaidoDim : Color.secondary)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular, in: Circle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, 12)
            .padding(.trailing, 16)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(route.name)
                        .font(.title2.bold())
                    if let areaName = route.areaName {
                        Text(areaName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    StatTile(value: formattedDistance, label: "distance", tint: .routeTeal)
                    StatTile(value: formattedElevation, label: "ft climb", tint: .routeTeal)
                }

                if let description = route.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Label("Curated by \(route.curatorName)", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.routeTeal)

                Button {
                    addToMyRoutes()
                } label: {
                    Label("Add to My Routes", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.kaidoViolet)
                .disabled(route.coordinates.count < 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
            .padding()
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
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

    private func addToMyRoutes() {
        let localRoute = Route(
            name: route.name,
            distanceMeters: route.distanceMeters,
            elevationGainMeters: route.elevationGainMeters
        )

        var waypointModels: [Waypoint] = []
        for waypoint in route.orderedWaypoints {
            let model = Waypoint(
                latitude: waypoint.latitude,
                longitude: waypoint.longitude,
                order: waypoint.order,
                isSnappedToRoad: true
            )
            model.route = localRoute
            waypointModels.append(model)
        }
        localRoute.waypoints = waypointModels

        modelContext.insert(localRoute)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        CommunityRouteDetailView(route: CuratedCommunityRoutes.all[0])
    }
    .modelContainer(KaidoModelContainer.shared)
}
