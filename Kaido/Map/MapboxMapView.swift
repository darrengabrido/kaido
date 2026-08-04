import SwiftUI
import SwiftData
import MapboxMaps
import CoreLocation

extension MapStyle {
    static let kaidoNight = MapStyle.standard(lightPreset: .night)
}

struct MapboxMapView: View {
    let locationManager: LocationManager

    @Environment(BikeBLEManager.self) private var bleManager
    @Environment(GroupRideSessionStore.self) private var rideTogetherSession
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BikeProfile.lastConnectedAt, order: .reverse) private var bikeProfiles: [BikeProfile]
    @Query(sort: \SavedPlace.createdAt) private var savedPlaces: [SavedPlace]

    @State private var viewport: Viewport = MapViewportFollow.live(bottomPadding: 420)
    @State private var showBikeLanes = true
    @State private var isFreeRideEnabled = false
    @State private var searchViewModel = MapSearchViewModel()
    @State private var discoverViewModel = DiscoverViewModel()
    @State private var navigationViewModel = NavigationViewModel()
    @State private var isPresentingNavigation = false
    @State private var placeDetailsCardHeight: CGFloat = 420
    @GestureState private var placeDetailsDragTranslation: CGFloat = 0
    @FocusState private var isSearchFocused: Bool

    // Ride Together
    @State private var isPresentingRideTogetherLobby = false
    @State private var isPresentingRideTogetherNamePrompt = false
    @State private var pendingRideTogetherCreation: PendingRideTogetherCreation?
    @State private var pendingRawInviteToken: String?
    @State private var rideTogetherErrorMessage: String?
    @State private var isCreatingRideTogether = false

    private static let placeDetailsCardDetents: [CGFloat] = [190, 420, 560]

    private var isFollowingUser: Bool {
        viewport.followPuck != nil
    }

    private var followBottomPadding: CGFloat {
        // Keep the puck above the drawer chrome with a little breathing room.
        resolvedPlaceDetailsCardHeight + 16
    }

    /// Free Ride is explicitly enabled and the map is available for discovery.
    private var shouldShowDiscover: Bool {
        isFreeRideEnabled
            && searchViewModel.selectedDestination == nil
            && navigationViewModel.navigationRoutes == nil
            && !isPresentingNavigation
            && searchViewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(viewport: $viewport) {
                // Course matches travel direction used by follow-puck; heading made the
                // puck spin when the phone was still or magnetically noisy on a mount.
                Puck2D(bearing: .course)
                    .bearingImage(BikePuckImage.bearing)
                    .pulsing(BikePuckImage.pulsing)

                if showBikeLanes {
                    BikeLaneMapLayers()
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

                // Draw alternates first. Their distinct colours keep choices legible, while a
                // narrow, translucent stroke makes the selected violet route the visual focus.
                PolylineAnnotationGroup(
                    navigationViewModel.routeOptions.filter { !$0.isMain && $0.coordinates.count > 1 }
                ) { option in
                    PolylineAnnotation(lineCoordinates: option.coordinates)
                        .lineColor(UIColor(routeColor(for: option)))
                        .lineWidth(2.5)
                }
                .lineOpacity(0.38)
                .lineEmissiveStrength(0.6)

                if let mainRoute = navigationViewModel.routeOptions.first(where: { $0.isMain && $0.coordinates.count > 1 }) {
                    RouteGlowPolyline(coordinates: mainRoute.coordinates)
                }
            }
            .mapStyle(.kaidoNight)
            .ornamentOptions(OrnamentOptions(
                scaleBar: ScaleBarViewOptions(visibility: .hidden),
                // Search and saved places live in the bottom drawer, leaving the map's top edge
                // available for ornaments.
                compass: CompassViewOptions(
                    position: .topLeading,
                    margins: CGPoint(x: 16, y: 16)
                )
            ))
            .ignoresSafeArea()

            // Recenter sits above the cycling menu so riders can recover follow after a pan.
            VStack(spacing: 10) {
                RecenterMapButton(isFollowing: isFollowingUser) {
                    MapViewportFollow.recenter($viewport, bottomPadding: followBottomPadding)
                }

                Menu {
                    Button {
                        showBikeLanes.toggle()
                    } label: {
                        Label(
                            "Bike Lanes & Paths",
                            systemImage: showBikeLanes ? "checkmark.circle.fill" : "circle"
                        )
                    }

                    Button {
                        setFreeRideEnabled(!isFreeRideEnabled)
                    } label: {
                        Label(
                            "Free Ride",
                            systemImage: isFreeRideEnabled ? "checkmark.circle.fill" : "circle"
                        )
                    }
                } label: {
                    Image(systemName: "bicycle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(
                            isFreeRideEnabled
                                ? Color.kaidoViolet
                                : (showBikeLanes ? Color.kaidoDim : Color.secondary)
                        )
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular, in: Circle())
                .accessibilityLabel("Cycling map options")
                .accessibilityHint("Choose bike lanes and paths or Free Ride")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 16)
            .padding(.bottom, 16)
            .offset(y: -(resolvedPlaceDetailsCardHeight + 8))

            // With search moved into the drawer, the legend can occupy the top-right corner.
            if showBikeLanes && searchViewModel.results.isEmpty {
                BikeLaneLegend()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 16)
                    .padding(.trailing, 16)
            }

            mapDrawer
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .zIndex(2)

        }
        .onAppear {
            navigationViewModel.updateRideTimeProfile(activeRideTimeProfile)
        }
        .onChange(of: activeRideTimeProfile) { _, profile in
            navigationViewModel.updateRideTimeProfile(profile)
        }
        .task {
            discoverViewModel.refreshIfNeeded(
                location: locationManager.currentLocation,
                isFreeRideMode: shouldShowDiscover
            )
        }
        .onChange(of: locationManager.currentLocation?.coordinate.latitude) { _, _ in
            searchViewModel.proximity = locationManager.currentLocation?.coordinate
            discoverViewModel.refreshIfNeeded(
                location: locationManager.currentLocation,
                isFreeRideMode: shouldShowDiscover
            )
            // Destination may have been picked before the first fix arrived — preview now.
            if let destination = searchViewModel.selectedDestination,
               navigationViewModel.navigationRoutes == nil,
               !navigationViewModel.isRequestingRoute,
               navigationViewModel.requestError == "Waiting for your location…" {
                fetchRoutes(to: destination)
            }
        }
        .onChange(of: rideTogetherSession.ride?.id) { _, newRideId in
            // Covers joining via a deep link handled elsewhere (ContentView) as well as this
            // view's own `createRideTogether` — either way, a freshly (re)joined ride should
            // land in the lobby unless we're already showing it or already navigating.
            guard newRideId != nil, rideTogetherSession.hasActiveRide,
                  !isPresentingRideTogetherLobby, !isPresentingNavigation
            else { return }
            isPresentingRideTogetherLobby = true
        }
        .onChange(of: shouldShowDiscover) { _, inFreeRide in
            if inFreeRide {
                discoverViewModel.refreshIfNeeded(
                    location: locationManager.currentLocation,
                    isFreeRideMode: true
                )
            } else {
                discoverViewModel.clear()
            }
        }
        .onChange(of: searchViewModel.query) { _, _ in
            searchViewModel.queryDidChange()
        }
        .onChange(of: isSearchFocused) { _, focused in
            if focused {
                snapPlaceDetailsCard(to: Self.placeDetailsCardDetents.last ?? 560)
            }
        }
        .fullScreenCover(isPresented: $isPresentingRideTogetherLobby) {
            GroupRideLobbyView(
                initialRawInviteToken: pendingRawInviteToken,
                onStartNavigating: {
                    isPresentingRideTogetherLobby = false
                    isPresentingNavigation = true
                },
                onDismiss: { isPresentingRideTogetherLobby = false }
            )
        }
        .sheet(isPresented: $isPresentingRideTogetherNamePrompt) {
            GroupRideDisplayNamePromptView(
                title: String(localized: "What should riders call you?"),
                message: String(localized: "This name is only shown to riders in this group, for this ride."),
                onSubmit: { name in
                    isPresentingRideTogetherNamePrompt = false
                    Task { await createRideTogether(displayName: name) }
                },
                onCancel: {
                    isPresentingRideTogetherNamePrompt = false
                    pendingRideTogetherCreation = nil
                }
            )
        }
        .fullScreenCover(isPresented: $isPresentingNavigation) {
            // Capture routes up front so a preference re-rank can't blank the cover mid-present.
            if let navigationRoutes = navigationViewModel.navigationRoutes {
                NavigationSessionView(
                    navigationRoutes: navigationRoutes,
                    telemetry: bleManager.telemetry,
                    rideTimeProfile: navigationViewModel.rideTimeProfile,
                    groupRideSessionStore: rideTogetherSession.hasActiveRide ? rideTogetherSession : nil
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
        .background(Color.kaidoInk.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.kaidoInk.opacity(0.08), lineWidth: 1)
        }
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
                            .foregroundStyle(result.isPOI ? Color.kaidoDim : Color.secondary)
                            .frame(width: 24, height: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            HStack(spacing: 4) {
                                if let category = result.category {
                                    Text(category)
                                        .foregroundStyle(Color.kaidoDim)
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
        .background(Color.kaidoInk.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
    }

    private var quickPlaces: [SavedPlace] {
        var places: [SavedPlace] = []
        if let homePlace {
            places.append(homePlace)
        }
        places.append(contentsOf: savedPlaces.filter { place in
            place.isFavorite && !place.isHome
        })
        return places
    }

    private var homePlace: SavedPlace? {
        savedPlaces.first(where: \.isHome)
    }

    private var recentPlaces: [SavedPlace] {
        savedPlaces
            .filter { $0.lastUsedAt != nil }
            .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
    }

    private var mapDrawer: some View {
        VStack(spacing: 0) {
            if let destination = searchViewModel.selectedDestination {
                placeDetailsSheetHeader(destination)
            } else {
                mapSearchSheetHeader
            }

            ScrollView {
                if let destination = searchViewModel.selectedDestination {
                    placeDetailsContent(destination)
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                        .padding(.bottom, 18)
                } else {
                    mapSearchContent
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                        .padding(.bottom, 24)
                }
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.placeDetailsCardDetents.last ?? 560)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        // The drawer's layout never changes during a drag. Only this transform updates, which
        // keeps Mapbox and the Liquid Glass material out of the per-frame layout path.
        .offset(y: (Self.placeDetailsCardDetents.last ?? 560) - resolvedPlaceDetailsCardHeight)
    }

    private var mapSearchSheetHeader: some View {
        VStack(spacing: 0) {
            drawerGrabber

            searchBar
                .padding(.horizontal, 18)
                .padding(.bottom, 14)

            Divider()
                .overlay(Color.kaidoInk.opacity(0.12))
                .padding(.horizontal, 18)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .simultaneousGesture(placeDetailsDragGesture)
    }

    private var mapSearchContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if searchViewModel.isSearching {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Searching…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if !searchViewModel.results.isEmpty {
                resultsList
            } else if let searchError = searchViewModel.searchError {
                Text(searchError)
                    .font(.caption)
                    .foregroundStyle(Color.statusCritical)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.statusCritical.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            } else {
                if shouldShowDiscover {
                    DiscoverPanelView(viewModel: discoverViewModel) { recommendation in
                        selectDestination(recommendation.searchResult)
                    } onRefresh: {
                        if let location = locationManager.currentLocation {
                            discoverViewModel.refresh(location: location)
                        }
                    }
                }

                savedPlacesSection

                if !recentPlaces.isEmpty {
                    recentsSection
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var savedPlacesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Places")
                .font(.title3.weight(.semibold))

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    if homePlace == nil {
                        savedPlaceCircleButton(
                            title: "Home",
                            subtitle: "Add",
                            systemImage: "house.fill",
                            colors: [Color.routeTealOnMap, Color.routeBlueOnMap]
                        ) {
                            isSearchFocused = true
                        }
                    }

                    ForEach(quickPlaces) { place in
                        savedPlaceCircleButton(
                            title: place.isHome ? "Home" : place.name,
                            subtitle: place.isHome ? place.name : "Favorite",
                            systemImage: place.isHome ? "house.fill" : "star.fill",
                            colors: place.isHome
                                ? [Color.routeTealOnMap, Color.routeBlueOnMap]
                                : [Color.kaidoViolet, Color.routeCoralOnMap]
                        ) {
                            selectDestination(place.searchResult)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func savedPlaceCircleButton(
        title: String,
        subtitle: String,
        systemImage: String,
        colors: [Color],
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.kaidoInk)
                    .frame(width: 68, height: 68)
                    .background(
                        LinearGradient(
                            colors: colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Circle()
                    )

                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Color.kaidoDim)
                    .lineLimit(1)
            }
            .frame(width: 82)
        }
        .buttonStyle(.plain)
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recents")
                .font(.title3.weight(.semibold))

            ForEach(Array(recentPlaces.prefix(8))) { place in
                HStack(spacing: 8) {
                    Button {
                        selectDestination(place.searchResult)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: place.isHome ? "house.fill" : place.iconName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.kaidoInk)
                                .frame(width: 34, height: 34)
                                .background(Color.kaidoInk.opacity(0.08), in: Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(place.address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Menu {
                        if !place.isFavorite {
                            Button {
                                place.isFavorite = true
                                savePlaces()
                            } label: {
                                Label("Add to Favorites", systemImage: "star")
                            }
                        }

                        Button(role: .destructive) {
                            removeFromRecents(place)
                        } label: {
                            Label("Remove from Recents", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.kaidoDim)
                            .frame(width: 34, height: 34)
                            .contentShape(Circle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.kaidoInk.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func placeDetailsContent(_ destination: SearchResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let requestError = navigationViewModel.requestError {
                Text(requestError)
                    .font(.caption)
                    .foregroundStyle(Color.statusCritical)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.statusCritical.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
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

            if let rideTogetherErrorMessage {
                Text(rideTogetherErrorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.statusCritical)
            }

            startNavigationButton
            rideTogetherButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct PendingRideTogetherCreation {
        let destination: SearchResult
        let option: RouteOption
        let allOptions: [RouteOption]
    }

    private var rideTogetherButton: some View {
        Button {
            Task { await startRideTogetherFlow() }
        } label: {
            if isCreatingRideTogether {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Label("Ride Together", systemImage: "person.2.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
        }
        .buttonStyle(.bordered)
        .tint(.kaidoViolet)
        .disabled(isRouteUnavailable || isCreatingRideTogether)
        .accessibilityHint("Invite other riders to navigate to this destination together")
    }

    private func startRideTogetherFlow() async {
        guard let destination = searchViewModel.selectedDestination,
              let mainOption = navigationViewModel.routeOptions.first(where: \.isMain)
        else { return }

        let pending = PendingRideTogetherCreation(
            destination: destination,
            option: mainOption,
            allOptions: navigationViewModel.routeOptions
        )
        if GroupRideDisplayNameStore.current != nil {
            await createRideTogether(displayName: GroupRideDisplayNameStore.current ?? "Host", pending: pending)
        } else {
            pendingRideTogetherCreation = pending
            isPresentingRideTogetherNamePrompt = true
        }
    }

    private func createRideTogether(displayName: String) async {
        guard let pending = pendingRideTogetherCreation else { return }
        await createRideTogether(displayName: displayName, pending: pending)
    }

    private func createRideTogether(displayName: String, pending: PendingRideTogetherCreation) async {
        isCreatingRideTogether = true
        rideTogetherErrorMessage = nil
        defer { isCreatingRideTogether = false }

        let originCoordinate = locationManager.currentLocation?.coordinate ?? pending.destination.coordinate
        let snapshot = GroupRideRouteSnapshot(
            destinationName: pending.destination.name,
            waypointCoordinates: [originCoordinate, pending.destination.coordinate],
            selecting: pending.option,
            among: pending.allOptions
        )

        do {
            let result = try await rideTogetherSession.createRide(
                destinationName: pending.destination.name,
                destination: pending.destination.coordinate,
                routeSnapshot: snapshot,
                title: nil,
                displayName: displayName
            )
            pendingRawInviteToken = result.rawInviteToken
            pendingRideTogetherCreation = nil
            isPresentingRideTogetherLobby = true
        } catch {
            rideTogetherErrorMessage = error.localizedDescription
        }
    }

    private var startNavigationButton: some View {
        Button {
            isPresentingNavigation = true
        } label: {
            Label("Start Navigation", systemImage: "location.north.line.fill")
                .font(.headline)
                .foregroundStyle(Color.kaidoInk)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.kaidoMidnight)
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.kaidoViolet, Color.kaidoIndigo],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .opacity(0.9)
                        }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.kaidoVioletOnMap.opacity(0.42), lineWidth: 1)
                }
                .shadow(color: Color.kaidoViolet.opacity(0.28), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isRouteUnavailable)
        .opacity(isRouteUnavailable ? 0.48 : 1)
    }

    private var isRouteUnavailable: Bool {
        navigationViewModel.isRequestingRoute || navigationViewModel.navigationRoutes == nil
    }

    private func placeDetailsSheetHeader(_ destination: SearchResult) -> some View {
        VStack(spacing: 0) {
            drawerGrabber

            destinationHeader(destination)
                .padding(.horizontal, 18)
                .padding(.bottom, 14)

            Divider()
                .overlay(Color.kaidoInk.opacity(0.12))
                .padding(.horizontal, 18)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .simultaneousGesture(placeDetailsDragGesture)
    }

    private var drawerGrabber: some View {
        Capsule()
            .fill(Color.kaidoDim.opacity(0.72))
            .frame(width: 42, height: 5)
            .padding(.top, 9)
            .padding(.bottom, 10)
            .accessibilityElement()
            .accessibilityLabel("Resize map drawer")
            .accessibilityValue(placeDetailsSizeLabel)
            .accessibilityAdjustableAction { direction in
                adjustPlaceDetailsSize(direction)
            }
    }

    private var resolvedPlaceDetailsCardHeight: CGFloat {
        rubberBandedPlaceDetailsHeight(placeDetailsCardHeight - placeDetailsDragTranslation)
    }

    private var placeDetailsDragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($placeDetailsDragTranslation) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                let proposedHeight = placeDetailsCardHeight - value.predictedEndTranslation.height
                snapPlaceDetailsCard(to: proposedHeight)
            }
    }

    private func clampedPlaceDetailsHeight(_ height: CGFloat) -> CGFloat {
        let minimum = Self.placeDetailsCardDetents.first ?? 190
        let maximum = Self.placeDetailsCardDetents.last ?? 560
        return min(max(height, minimum), maximum)
    }

    private func rubberBandedPlaceDetailsHeight(_ height: CGFloat) -> CGFloat {
        let minimum = Self.placeDetailsCardDetents.first ?? 190
        let maximum = Self.placeDetailsCardDetents.last ?? 560

        if height < minimum {
            return minimum - (minimum - height) * 0.16
        }
        if height > maximum {
            return maximum + (height - maximum) * 0.16
        }
        return height
    }

    private func snapPlaceDetailsCard(to proposedHeight: CGFloat) {
        let clampedHeight = clampedPlaceDetailsHeight(proposedHeight)
        let nearest = Self.placeDetailsCardDetents.min {
            abs($0 - clampedHeight) < abs($1 - clampedHeight)
        } ?? placeDetailsCardHeight

        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.86, blendDuration: 0.18)) {
            placeDetailsCardHeight = nearest
        }
        // Follow framing depends on drawer height — keep the puck above chrome.
        // Set outside the spring so we don't animate followPuck with a non-viewport curve.
        if viewport.followPuck != nil {
            viewport = MapViewportFollow.live(bottomPadding: nearest + 16)
        }
    }

    private var placeDetailsSizeLabel: String {
        switch placeDetailsCardHeight {
        case ..<305: "Compact"
        case ..<490: "Medium"
        default: "Expanded"
        }
    }

    private func adjustPlaceDetailsSize(_ direction: AccessibilityAdjustmentDirection) {
        guard let currentIndex = Self.placeDetailsCardDetents.firstIndex(of: placeDetailsCardHeight) else {
            snapPlaceDetailsCard(to: placeDetailsCardHeight)
            return
        }

        let nextIndex: Int
        switch direction {
        case .increment:
            nextIndex = min(currentIndex + 1, Self.placeDetailsCardDetents.count - 1)
        case .decrement:
            nextIndex = max(currentIndex - 1, 0)
        @unknown default:
            return
        }

        let nextHeight = Self.placeDetailsCardDetents[nextIndex]
        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.86, blendDuration: 0.18)) {
            placeDetailsCardHeight = nextHeight
        }
        if viewport.followPuck != nil {
            viewport = MapViewportFollow.live(bottomPadding: nextHeight + 16)
        }
    }

    private func destinationHeader(_ destination: SearchResult) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: destination.iconName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.kaidoVioletOnMap)
                .frame(width: 40, height: 40)
                .background(Color.kaidoViolet.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(destination.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                if let category = destination.category {
                    Text(category.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.kaidoVioletOnMap)
                        .lineLimit(1)
                }

                if let placeFormatted = destination.placeFormatted {
                    Text(placeFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                destinationHeaderButton(
                    systemImage: isHome(destination) ? "house.fill" : "house",
                    isSelected: isHome(destination),
                    accessibilityLabel: isHome(destination) ? "Remove home address" : "Set home address"
                ) {
                    toggleHome(destination)
                }

                destinationHeaderButton(
                    systemImage: isFavorite(destination) ? "star.fill" : "star",
                    isSelected: isFavorite(destination),
                    accessibilityLabel: isFavorite(destination) ? "Remove from favorites" : "Add to favorites"
                ) {
                    toggleFavorite(destination)
                }

                destinationHeaderButton(
                    systemImage: "xmark",
                    isSelected: false,
                    accessibilityLabel: "Close place details"
                ) {
                    clearDestination()
                }
            }
        }
    }

    private func destinationHeaderButton(
        systemImage: String,
        isSelected: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? Color.kaidoVioletOnMap : Color.kaidoDim)
                .frame(width: 34, height: 34)
                .background(
                    isSelected ? Color.kaidoViolet.opacity(0.18) : Color.kaidoInk.opacity(0.07),
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Quiet leans on dedicated lanes and quieter streets; Fast picks the quickest alternative.
    /// Lives next to the alternatives list so the preference is visible while comparing routes.
    private var routingPreferenceToggle: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("ROUTE STYLE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.kaidoDim)

            Picker("Routing style", selection: $navigationViewModel.preference) {
                ForEach(RoutingPreference.allCases) { preference in
                    Label(preference.title, systemImage: preference.systemImage)
                        .tag(preference)
                        .accessibilityLabel(preference.accessibilityLabel)
                }
            }
            .pickerStyle(.segmented)
        }
        .disabled(navigationViewModel.isRequestingRoute)
        .accessibilityHint("Changes which route Kaido recommends among alternatives")
    }

    /// Recommended routes for the currently selected destination — tap one to make it the
    /// route "Start Navigation" will launch. Mirrors what's drawn on the map: the picked
    /// route is violet and full-strength, the rest are dim.
    private var routeOptionsList: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ROUTE OPTIONS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.kaidoDim)
                Text("Your ride time · \(navigationViewModel.rideTimeProfile.paceDescription)")
                    .font(.caption)
                    .foregroundStyle(Color.kaidoVioletOnMap)
                    .lineLimit(1)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 9) {
                    ForEach(navigationViewModel.routeOptions) { option in
                        Button {
                            Task {
                                await navigationViewModel.selectRoute(option)
                                overviewSelectedRoute()
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(routeColor(for: option))
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 7)

                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                                        Text(formattedDuration(option.personalizedTravelTime))
                                            .font(.title3.weight(option.isMain ? .semibold : .medium))
                                            .foregroundStyle(option.isMain ? Color.primary : Color.secondary)

                                        Text(formattedDistance(option.distanceMeters))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        Spacer(minLength: 0)

                                        if option.isMain {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(Color.kaidoViolet)
                                        }
                                    }

                                    Text(option.stressProfile.headline)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(quietColor(for: option.stressProfile.score))
                                        .lineLimit(1)

                                    Text(option.stressProfile.summary)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(11)
                            .frame(width: 270, alignment: .leading)
                            .background(
                                option.isMain
                                    ? Color.kaidoViolet.opacity(0.14)
                                    : Color.kaidoInk.opacity(0.045),
                                in: RoundedRectangle(cornerRadius: 13)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 13)
                                    .stroke(
                                        option.isMain
                                            ? Color.kaidoViolet.opacity(0.34)
                                            : Color.kaidoInk.opacity(0.08),
                                        lineWidth: 1
                                    )
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(routeAccessibilityLabel(for: option))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func quietColor(for stress: Double) -> Color {
        switch stress {
        case ..<0.35: .statusGood
        case ..<0.55: .statusCaution
        default: .statusCritical
        }
    }

    /// Violet remains the active route. Mapbox returns up to two cycling alternatives, which
    /// receive blue and coral respectively — deliberately distinct from mint bike lanes.
    private func routeColor(for option: RouteOption) -> Color {
        guard !option.isMain else { return .kaidoViolet }
        let alternateIndex = navigationViewModel.routeOptions
            .filter { !$0.isMain }
            .firstIndex { $0.id == option.id } ?? 0

        switch alternateIndex % 2 {
        case 0: return .routeBlueOnMap
        default: return .routeCoralOnMap
        }
    }

    private func routeAccessibilityLabel(for option: RouteOption) -> String {
        let duration = formattedDuration(option.personalizedTravelTime)
        let distance = formattedDistance(option.distanceMeters)
        let selected = option.isMain ? ", selected" : ""
        return "Your ride time \(duration) with \(navigationViewModel.rideTimeProfile.paceDescription), \(distance), \(option.stressProfile.headline), \(option.stressProfile.summary)\(selected)"
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
        isFreeRideEnabled = false
        discoverViewModel.clear()
        recordRecent(result)
        searchViewModel.selectResult(result)
        navigationViewModel.clear()
        isSearchFocused = false
        snapPlaceDetailsCard(to: 420)
        withViewportAnimation(.default(maxDuration: 1)) {
            viewport = .camera(center: result.coordinate, zoom: 15)
                .padding(.bottom, followBottomPadding)
        }
        fetchRoutes(to: result)
    }

    private func isHome(_ result: SearchResult) -> Bool {
        savedPlaces.contains { $0.isHome && $0.matches(result) }
    }

    private func isFavorite(_ result: SearchResult) -> Bool {
        savedPlaces.contains { $0.isFavorite && $0.matches(result) }
    }

    private func toggleHome(_ result: SearchResult) {
        if let current = savedPlaces.first(where: { $0.isHome && $0.matches(result) }) {
            current.isHome = false
            removeIfUnused(current)
            savePlaces()
            return
        }

        for currentHome in savedPlaces where currentHome.isHome {
            currentHome.isHome = false
            removeIfUnused(currentHome)
        }

        let place = savedPlace(matching: result) ?? createSavedPlace(from: result)
        place.update(from: result)
        place.isHome = true
        savePlaces()
    }

    private func toggleFavorite(_ result: SearchResult) {
        let place = savedPlace(matching: result) ?? createSavedPlace(from: result)
        place.update(from: result)
        place.isFavorite.toggle()
        removeIfUnused(place)
        savePlaces()
    }

    private func savedPlace(matching result: SearchResult) -> SavedPlace? {
        savedPlaces.first { $0.matches(result) }
    }

    private func createSavedPlace(from result: SearchResult) -> SavedPlace {
        let place = SavedPlace(result: result)
        modelContext.insert(place)
        return place
    }

    private func removeIfUnused(_ place: SavedPlace) {
        if !place.isHome && !place.isFavorite && place.lastUsedAt == nil {
            modelContext.delete(place)
        }
    }

    private func recordRecent(_ result: SearchResult) {
        let place = savedPlace(matching: result) ?? createSavedPlace(from: result)
        place.update(from: result)
        place.lastUsedAt = Date()
        savePlaces()
    }

    private func removeFromRecents(_ place: SavedPlace) {
        place.lastUsedAt = nil
        removeIfUnused(place)
        savePlaces()
    }

    private func savePlaces() {
        try? modelContext.save()
    }

    private func clearDestination() {
        searchViewModel.clearSelection()
        navigationViewModel.clear()
        snapPlaceDetailsCard(to: 420)
        MapViewportFollow.recenter($viewport, bottomPadding: followBottomPadding)
    }

    private func setFreeRideEnabled(_ enabled: Bool) {
        isFreeRideEnabled = enabled
        if enabled {
            clearDestination()
            discoverViewModel.refreshIfNeeded(
                location: locationManager.currentLocation,
                isFreeRideMode: true
            )
        } else {
            discoverViewModel.clear()
        }
    }

    private func fetchRoutes(to destination: SearchResult) {
        guard let currentCoordinate = locationManager.currentLocation?.coordinate else {
            navigationViewModel.requestError = "Waiting for your location…"
            return
        }
        Task {
            navigationViewModel.updateRideTimeProfile(activeRideTimeProfile)
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
        withViewportAnimation(.default(maxDuration: 1.2)) {
            viewport = .overview(
                geometry: LineString(main.coordinates),
                geometryPadding: EdgeInsets(
                    top: 72,
                    leading: 48,
                    bottom: followBottomPadding,
                    trailing: 48
                )
            )
        }
    }

    private var activeRideTimeProfile: RideTimeProfile {
        BikeProfileStore.activeProfile(in: bikeProfiles)?.rideTimeProfile ?? .defaultProfile
    }
}

#Preview {
    MapboxMapView(locationManager: LocationManager())
}
