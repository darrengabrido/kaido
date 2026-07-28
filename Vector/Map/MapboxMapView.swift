import SwiftUI
import MapboxMaps
import CoreLocation

extension MapStyle {
    static let vectorNight = MapStyle.standard(lightPreset: .night)
}

struct MapboxMapView: View {
    let locationManager: LocationManager

    @Environment(BikeBLEManager.self) private var bleManager

    @State private var viewport: Viewport = .followPuck(zoom: 15, bearing: .heading, pitch: 0)
    @State private var showBikeLanes = true
    @State private var searchViewModel = MapSearchViewModel()
    @State private var navigationViewModel = NavigationViewModel()
    @State private var isPresentingNavigation = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Map(viewport: $viewport) {
                Puck2D(bearing: .heading)

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

                if let destination = searchViewModel.selectedDestination {
                    CircleAnnotationGroup([destination]) { result in
                        CircleAnnotation(centerCoordinate: result.coordinate)
                            // The destination pin is the one marker that must not recede into the
                            // neutrals — clay reads warm against the violet route and sage lanes.
                            .circleColor(UIColor(Color.statusCritical))
                            .circleRadius(8)
                            .circleStrokeColor(.white)
                            .circleStrokeWidth(2)
                    }
                    .circleEmissiveStrength(1)
                }

                // Draw alternates first (dim, thin) so the main/selected route always paints on top.
                PolylineAnnotationGroup(
                    navigationViewModel.routeOptions.filter { !$0.isMain && $0.coordinates.count > 1 }
                ) { option in
                    PolylineAnnotation(lineCoordinates: option.coordinates)
                        .lineColor(UIColor(Color.vectorDim))
                        .lineWidth(3)
                }
                .lineOpacity(0.55)

                if let mainRoute = navigationViewModel.routeOptions.first(where: { $0.isMain && $0.coordinates.count > 1 }) {
                    RouteGlowPolyline(coordinates: mainRoute.coordinates)
                }
            }
            .mapStyle(.vectorNight)
            .ornamentOptions(OrnamentOptions(
                scaleBar: ScaleBarViewOptions(visibility: .hidden),
                // The compass defaults to .topTrailing with an 8pt margin, which puts it
                // underneath the search bar. Ornament margins are measured from the safe-area
                // top (~59pt), so y: 60 drops it clear of the search bar; .topLeading keeps it
                // off the right edge where the legend and bike-lane toggle live.
                compass: CompassViewOptions(
                    position: .topLeading,
                    margins: CGPoint(x: 16, y: 60)
                )
            ))
            .ignoresSafeArea()

            VStack(spacing: 8) {
                searchBar

                if searchViewModel.isSearching {
                    HStack {
                        ProgressView()
                        Spacer()
                    }
                    .padding(10)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
                }

                if !searchViewModel.results.isEmpty {
                    resultsList
                }

                if let searchError = searchViewModel.searchError {
                    Text(searchError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
                }

                Spacer()

                // Bike lanes toggle lives in the layout flow rather than as a free-floating
                // corner overlay, so it is pushed up by the destination card instead of
                // covering its "Start Navigation" button.
                Button {
                    showBikeLanes.toggle()
                } label: {
                    Image(systemName: "bicycle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(showBikeLanes ? Color.vectorDim : Color.secondary)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular, in: Circle())
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel(showBikeLanes ? "Hide bike lanes" : "Show bike lanes")

                if let destination = searchViewModel.selectedDestination {
                    destinationCard(destination)
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // Bike lanes legend — top-right, tucked under the search bar.
            // Hidden while search results are showing so it doesn't collide with the dropdown.
            // Top inset = search bar top padding (8) + its height (~44) + an 8pt gap; this
            // matches the compass's safe-area-relative margin on the opposite side.
            if showBikeLanes && searchViewModel.results.isEmpty {
                BikeLaneLegend()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 60)
                    .padding(.trailing, 16)
            }

        }
        .onChange(of: locationManager.currentLocation?.coordinate.latitude) { _, _ in
            searchViewModel.proximity = locationManager.currentLocation?.coordinate
            // Destination may have been picked before the first fix arrived — preview now.
            if let destination = searchViewModel.selectedDestination,
               navigationViewModel.navigationRoutes == nil,
               !navigationViewModel.isRequestingRoute,
               navigationViewModel.requestError == "Waiting for your location…" {
                fetchRoutes(to: destination)
            }
        }
        .onChange(of: searchViewModel.query) { _, _ in
            searchViewModel.queryDidChange()
        }
        .fullScreenCover(isPresented: $isPresentingNavigation) {
            // Capture routes up front so a preference re-rank can't blank the cover mid-present.
            if let navigationRoutes = navigationViewModel.navigationRoutes {
                NavigationSessionView(
                    navigationRoutes: navigationRoutes,
                    telemetry: bleManager.telemetry
                ) { _ in
                    isPresentingNavigation = false
                    navigationViewModel.clear()
                    clearDestination()
                }
                .ignoresSafeArea()
            } else {
                Color.clear
                    .onAppear { isPresentingNavigation = false }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search for a destination", text: $searchViewModel.query)
                .focused($isSearchFocused)
                .submitLabel(.search)
            if !searchViewModel.query.isEmpty {
                Button {
                    clearDestination()
                    isSearchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(searchViewModel.results) { result in
                Button {
                    selectDestination(result)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: result.iconName)
                            .font(.system(size: 15))
                            .foregroundStyle(result.isPOI ? Color.vectorDim : Color.secondary)
                            .frame(width: 24, height: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            HStack(spacing: 4) {
                                if let category = result.category {
                                    Text(category)
                                        .foregroundStyle(Color.vectorDim)
                                    if result.placeFormatted != nil {
                                        Text("·").foregroundStyle(.secondary)
                                    }
                                }
                                if let placeFormatted = result.placeFormatted {
                                    Text(placeFormatted)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption)
                            .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if result.id != searchViewModel.results.last?.id {
                    Divider()
                        .padding(.leading, 48)
                }
            }
        }
        // Without this, taps in the gaps between rows fall through to the Mapbox map
        // underneath instead of being absorbed by this panel — same bug as the route
        // planner's control panel (see its `.contentShape` note).
        .contentShape(Rectangle())
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    private func destinationCard(_ destination: SearchResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: destination.iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(destination.isPOI ? Color.vectorDim : Color.secondary)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.name)
                        .font(.headline)
                    if let category = destination.category {
                        Text(category)
                            .font(.caption)
                            .foregroundStyle(Color.vectorDim)
                    }
                    if let placeFormatted = destination.placeFormatted {
                        Text(placeFormatted)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    clearDestination()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if let requestError = navigationViewModel.requestError {
                Text(requestError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            routingPreferenceToggle

            if navigationViewModel.isRequestingRoute && navigationViewModel.navigationRoutes == nil {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Previewing route…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            if navigationViewModel.navigationRoutes != nil {
                routeOptionsList
            }

            Button {
                isPresentingNavigation = true
            } label: {
                Label("Start Navigation", systemImage: "location.north.line.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.vectorViolet)
            .disabled(
                navigationViewModel.isRequestingRoute
                    || navigationViewModel.navigationRoutes == nil
            )
        }
        .padding()
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
    }

    /// Quiet leans on dedicated lanes and quieter streets; Fast picks the quickest alternative.
    /// Lives next to the alternatives list so the preference is visible while comparing routes.
    private var routingPreferenceToggle: some View {
        Picker("Routing style", selection: $navigationViewModel.preference) {
            ForEach(RoutingPreference.allCases) { preference in
                Label(preference.title, systemImage: preference.systemImage)
                    .tag(preference)
                    .accessibilityLabel(preference.accessibilityLabel)
            }
        }
        .pickerStyle(.segmented)
        .disabled(navigationViewModel.isRequestingRoute)
        .accessibilityHint("Changes which route Vector recommends among alternatives")
    }

    /// Recommended routes for the currently selected destination — tap one to make it the
    /// route "Start Navigation" will launch. Mirrors what's drawn on the map: the picked
    /// route is violet and full-strength, the rest are dim.
    private var routeOptionsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(navigationViewModel.routeOptions) { option in
                Button {
                    Task {
                        await navigationViewModel.selectRoute(option)
                        overviewSelectedRoute()
                    }
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            // Alternates recede to the same dim used for their map polylines.
                            .fill(option.isMain ? Color.vectorViolet : Color.vectorDim)
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(formattedDuration(option.expectedTravelTime))
                                    .font(.subheadline.weight(option.isMain ? .semibold : .regular))
                                    .foregroundStyle(option.isMain ? Color.primary : Color.secondary)
                                Text("·")
                                    .foregroundStyle(.secondary)
                                Text(formattedDistance(option.distanceMeters))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                if option.isMain {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.vectorViolet)
                                }
                            }

                            Text(option.stressProfile.headline)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(quietColor(for: option.stressProfile.score))

                            Text(option.stressProfile.summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(option.isMain ? Color.vectorViolet.opacity(0.14) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(routeAccessibilityLabel(for: option))
            }
        }
    }

    private func quietColor(for stress: Double) -> Color {
        switch stress {
        case ..<0.35: .statusGood
        case ..<0.55: .statusCaution
        default: .statusCritical
        }
    }

    private func routeAccessibilityLabel(for option: RouteOption) -> String {
        let duration = formattedDuration(option.expectedTravelTime)
        let distance = formattedDistance(option.distanceMeters)
        let selected = option.isMain ? ", selected" : ""
        return "\(duration), \(distance), \(option.stressProfile.headline), \(option.stressProfile.summary)\(selected)"
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? ""
    }

    private func formattedDistance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    private func selectDestination(_ result: SearchResult) {
        searchViewModel.selectResult(result)
        navigationViewModel.clear()
        isSearchFocused = false
        withAnimation {
            viewport = .camera(center: result.coordinate, zoom: 15)
        }
        fetchRoutes(to: result)
    }

    private func clearDestination() {
        searchViewModel.clearSelection()
        navigationViewModel.clear()
        withAnimation {
            viewport = .followPuck(zoom: 15, bearing: .heading, pitch: 0)
        }
    }

    private func fetchRoutes(to destination: SearchResult) {
        guard let currentCoordinate = locationManager.currentLocation?.coordinate else {
            navigationViewModel.requestError = "Waiting for your location…"
            return
        }
        Task {
            await navigationViewModel.requestRoutes(
                waypointCoordinates: [currentCoordinate, destination.coordinate]
            )
            overviewSelectedRoute()
        }
    }

    private func overviewSelectedRoute() {
        guard let main = navigationViewModel.routeOptions.first(where: { $0.isMain }),
              main.coordinates.count > 1
        else { return }
        withAnimation {
            viewport = .overview(geometry: LineString(main.coordinates))
        }
    }
}

#Preview {
    MapboxMapView(locationManager: LocationManager())
}
