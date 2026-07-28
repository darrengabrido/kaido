import SwiftUI
import SwiftData
import MapboxMaps

struct RoutePlannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel = RoutePlannerViewModel()
    @State private var viewport: Viewport = .followPuck(zoom: 15, bearing: .heading, pitch: 0)
    @State private var isShowingNameAlert = false
    @State private var routeName = ""
    @State private var showBikeLanes = true

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(viewport: $viewport) {
                    Puck2D(bearing: .heading)

                    if showBikeLanes {
                        VectorSource(id: "streets-v8")
                            .url("mapbox://mapbox.mapbox-streets-v8")
                        // On-street painted bike lane — drawn on the road's own centerline (bike_lane field)
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

                    if viewModel.lineCoordinates.count > 1 {
                        RouteGlowPolyline(coordinates: viewModel.lineCoordinates)
                    }

                    CircleAnnotationGroup(viewModel.waypoints) { waypoint in
                        CircleAnnotation(centerCoordinate: waypoint.coordinate)
                            .circleColor(UIColor(Color.vectorVioletOnMap))
                            .circleRadius(6)
                            .circleStrokeColor(.white)
                            .circleStrokeWidth(2)
                    }
                    .circleEmissiveStrength(1)
                }
                .mapStyle(.vectorNight)
                .onMapTapGesture { context in
                    viewModel.addWaypoint(at: context.coordinate)
                }
                .ignoresSafeArea()

                controlPanel
            }
            .navigationTitle("Plan Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        routeName = ""
                        isShowingNameAlert = true
                    }
                    .tint(.vectorViolet)
                    .disabled(viewModel.waypoints.count < 2)
                }
            }
            .alert("Name Your Route", isPresented: $isShowingNameAlert) {
                TextField("Route name", text: $routeName)
                Button("Save", action: saveRoute)
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(formattedDistance)
                    .font(.headline)
                    .foregroundStyle(viewModel.waypoints.count > 1 ? Color.vectorDim : .secondary)
                Spacer()
                if viewModel.isMatching {
                    ProgressView()
                }
            }

            Toggle("Bike Lanes", isOn: $showBikeLanes)
                .tint(.vectorDim)

            if showBikeLanes {
                BikeLaneLegend(showsBackground: false)
            }

            Toggle("Snap to Roads", isOn: Binding(
                get: { viewModel.isSnapEnabled },
                set: { newValue in
                    viewModel.isSnapEnabled = newValue
                    if newValue {
                        Task { await viewModel.snapToRoads() }
                    }
                }
            ))
            .tint(.vectorViolet)

            if let matchingError = viewModel.matchingError {
                Text(matchingError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button {
                    viewModel.removeLast()
                } label: {
                    Label("Undo Last", systemImage: "arrow.uturn.backward")
                }
                .disabled(viewModel.waypoints.isEmpty)

                Spacer()

                Button("Clear", role: .destructive) {
                    viewModel.clear()
                }
                .disabled(viewModel.waypoints.isEmpty)
            }
        }
        .padding()
        .contentShape(Rectangle())
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
        .padding()
    }

    private var formattedDistance: String {
        guard viewModel.waypoints.count > 1 else {
            return "Tap the map to add waypoints"
        }
        let measurement = Measurement(value: viewModel.displayDistanceMeters, unit: UnitLength.meters)
        return measurement.formatted(.measurement(width: .abbreviated, usage: .road))
    }

    private func saveRoute() {
        let trimmedName = routeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let route = Route(
            name: trimmedName.isEmpty ? "Untitled Route" : trimmedName,
            distanceMeters: viewModel.displayDistanceMeters
        )

        let isSnapped = viewModel.isSnapEnabled && viewModel.snappedCoordinates != nil
        var waypointModels: [Waypoint] = []
        for (index, plannerWaypoint) in viewModel.waypoints.enumerated() {
            let waypoint = Waypoint(
                latitude: plannerWaypoint.coordinate.latitude,
                longitude: plannerWaypoint.coordinate.longitude,
                order: index,
                isSnappedToRoad: isSnapped
            )
            waypoint.route = route
            waypointModels.append(waypoint)
        }
        route.waypoints = waypointModels

        modelContext.insert(route)
        dismiss()
    }
}

#Preview {
    RoutePlannerView()
        .modelContainer(VectorModelContainer.shared)
}
