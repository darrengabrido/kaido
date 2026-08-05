import SwiftUI
import SwiftData
import MapboxMaps

struct RoutePlannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel = RoutePlannerViewModel()
    @State private var viewport: Viewport = MapViewportFollow.live(bottomPadding: 220)
    @State private var isShowingNameAlert = false
    @State private var routeName = ""
    @State private var showBikeLanes = true

    private var isFollowingUser: Bool {
        viewport.followPuck != nil
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(viewport: $viewport) {
                    Puck2D(bearing: .course)

                    if showBikeLanes {
                        BikeLaneMapLayers()
                    }

                    if viewModel.lineCoordinates.count > 1 {
                        RouteGlowPolyline(coordinates: viewModel.lineCoordinates)
                    }

                    CircleAnnotationGroup(viewModel.waypoints) { waypoint in
                        CircleAnnotation(centerCoordinate: waypoint.coordinate)
                            .circleColor(UIColor(Color.kaidoVioletOnMap))
                            .circleRadius(6)
                            .circleStrokeColor(.white)
                            .circleStrokeWidth(2)
                    }
                    .circleEmissiveStrength(1)
                }
                .mapStyle(.kaidoNight)
                .onMapTapGesture { context in
                    viewModel.addWaypoint(at: context.coordinate)
                }
                .ignoresSafeArea()

                RecenterMapButton(isFollowing: isFollowingUser) {
                    MapViewportFollow.recenter($viewport, bottomPadding: 220)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 16)
                .padding(.bottom, 220)

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
                    .tint(.kaidoViolet)
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
                    .foregroundStyle(viewModel.waypoints.count > 1 ? Color.kaidoDim : .secondary)
                Spacer()
                if viewModel.isMatching {
                    ProgressView()
                }
            }

            Toggle("Bike Lanes", isOn: $showBikeLanes)
                .tint(.kaidoDim)

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
            .tint(.kaidoViolet)

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
        .modelContainer(KaidoModelContainer.shared)
}
