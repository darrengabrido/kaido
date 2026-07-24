import SwiftUI
import MapboxMaps
import CoreLocation

extension MapStyle {
    static let ebikeNight = MapStyle.standard(lightPreset: .night)
}

struct MapboxMapView: View {
    let locationManager: LocationManager

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
                    VectorSource(id: "ebike-streets-v8")
                        .url("mapbox://mapbox.mapbox-streets-v8")
                    // On-street painted bike lane — drawn on the road's own centerline (bike_lane field),
                    // dashed so it reads as "lane within the road" rather than a separate path.
                    LineLayer(id: "bike-onstreet-lane", source: "ebike-streets-v8")
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
                    LineLayer(id: "bike-dedicated-path", source: "ebike-streets-v8")
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
                            .circleColor(UIColor(Color.effortCoral))
                            .circleRadius(8)
                            .circleStrokeColor(.white)
                            .circleStrokeWidth(2)
                    }
                    .circleEmissiveStrength(1)
                }
            }
            .mapStyle(.ebikeNight)
            .ornamentOptions(OrnamentOptions(scaleBar: ScaleBarViewOptions(visibility: .hidden)))
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

                if let destination = searchViewModel.selectedDestination {
                    destinationCard(destination)
                }
            }
            .padding(.top, 60)
            .padding(.horizontal, 16)
            .padding(.bottom, 90)

            // Bike lanes legend — top-right, tucked under the search bar.
            // Hidden while search results are showing so it doesn't collide with the dropdown.
            if showBikeLanes && searchViewModel.results.isEmpty {
                BikeLaneLegend()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 118)
                    .padding(.trailing, 16)
            }

            // Bike lanes toggle — bottom-right
            Button {
                showBikeLanes.toggle()
            } label: {
                Image(systemName: "bicycle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(showBikeLanes ? Color.routeTeal : Color.secondary)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular, in: Circle())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 16)
            .padding(.bottom, 100)
        }
        .onChange(of: locationManager.currentLocation?.coordinate.latitude) { _, _ in
            searchViewModel.proximity = locationManager.currentLocation?.coordinate
        }
        .onChange(of: searchViewModel.query) { _, _ in
            searchViewModel.queryDidChange()
        }
        .fullScreenCover(isPresented: $isPresentingNavigation) {
            if let navigationRoutes = navigationViewModel.navigationRoutes {
                NavigationSessionView(navigationRoutes: navigationRoutes) { _ in
                    isPresentingNavigation = false
                    navigationViewModel.clear()
                    clearDestination()
                }
                .ignoresSafeArea()
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
                            .foregroundStyle(result.isPOI ? Color.routeTeal : Color.secondary)
                            .frame(width: 24, height: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            HStack(spacing: 4) {
                                if let category = result.category {
                                    Text(category)
                                        .foregroundStyle(Color.routeTeal)
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
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    private func destinationCard(_ destination: SearchResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: destination.iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(destination.isPOI ? Color.routeTeal : Color.secondary)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.name)
                        .font(.headline)
                    if let category = destination.category {
                        Text(category)
                            .font(.caption)
                            .foregroundStyle(Color.routeTeal)
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
                }
                .buttonStyle(.plain)
            }

            if let requestError = navigationViewModel.requestError {
                Text(requestError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                startNavigation(to: destination)
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
            .disabled(navigationViewModel.isRequestingRoute)
        }
        .padding()
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
    }

    private func selectDestination(_ result: SearchResult) {
        searchViewModel.selectResult(result)
        isSearchFocused = false
        withAnimation {
            viewport = .camera(center: result.coordinate, zoom: 15)
        }
    }

    private func clearDestination() {
        searchViewModel.clearSelection()
        withAnimation {
            viewport = .followPuck(zoom: 15, bearing: .heading, pitch: 0)
        }
    }

    private func startNavigation(to destination: SearchResult) {
        guard let currentCoordinate = locationManager.currentLocation?.coordinate else {
            navigationViewModel.requestError = "Waiting for your location…"
            return
        }
        Task {
            await navigationViewModel.startNavigation(
                waypointCoordinates: [currentCoordinate, destination.coordinate]
            )
            if navigationViewModel.navigationRoutes != nil {
                isPresentingNavigation = true
            }
        }
    }
}

#Preview {
    MapboxMapView(locationManager: LocationManager())
}
