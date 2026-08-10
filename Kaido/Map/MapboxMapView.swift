import SwiftUI
import SwiftData
import MapboxMaps
import CoreLocation
import UIKit

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
    @Query private var riderProfiles: [RiderProfile]

    @State private var viewport: Viewport = MapViewportFollow.live(bottomPadding: 420)
    @State private var showBikeLanes = true
    @State private var isFreeRideEnabled = false
    @State private var searchViewModel = MapSearchViewModel()
    @State private var discoverViewModel = DiscoverViewModel()
    @State private var navigationViewModel = NavigationViewModel()
    @State private var isPresentingNavigation = false
    /// Canonical drawer state. Held here so it survives content changes, but this view's body
    /// never reads `height` or `progress` — only the drawer and the map-control stack do, which
    /// is what keeps a drag off this view's frame budget.
    @State private var drawerModel = MapDrawerModel()
    @FocusState private var isSearchFocused: Bool
    /// Same recogniser Ride Together dictation uses — the mic only appears when it can actually
    /// record, so the control is never decorative.
    @State private var speechService = SpeechQuickMessageService()
    @State private var speechErrorMessage: String?
    /// A view honours only one `.sheet`, so the drawer's two destinations share one, keyed by
    /// this rather than by a pair of booleans that would silently fight each other.
    @State private var presentedSheet: DrawerSheet?
    /// Collapsed by default so the resting card is Apple Maps–compact (summary + GO). Expands
    /// in place for light alternates and a nested Route details disclosure. Reset on every new
    /// destination.
    @State private var isRouteDetailsExpanded = false
    /// Nested under the expanded card — Steps + Hills live here so they aren't one long dump.
    @State private var isTurnDetailsExpanded = false
    /// True while the origin field owns the drawer's search UI. `selectedDestination` stays set
    /// throughout — this is a transient overlay on the destination-picked state, not a return to
    /// the no-destination search screen.
    @State private var isEditingOrigin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Ride Together
    @State private var isPresentingRideTogetherLobby = false
    @State private var isPresentingRideTogetherNamePrompt = false
    @State private var pendingRideTogetherCreation: PendingRideTogetherCreation?
    @State private var pendingRawInviteToken: String?
    @State private var rideTogetherErrorMessage: String?
    @State private var isCreatingRideTogether = false

    /// What the drawer can present. The Ride Together display-name prompt is a separate sheet on
    /// the screen's ZStack, which is a different view and so doesn't contend with these.
    private enum DrawerSheet: Identifiable {
        case profile
        case bike(BikeProfile)

        var id: String {
            switch self {
            case .profile: "profile"
            case .bike(let profile): "bike-\(profile.persistentModelID.hashValue)"
            }
        }
    }

    private var isFollowingUser: Bool {
        viewport.followPuck != nil
    }

    private var followBottomPadding: CGFloat {
        // Keep the puck above the drawer chrome with a little breathing room. Read from the
        // resting detent, not the live height, so recentring never fights an in-flight drag.
        drawerModel.height(for: drawerModel.detent) + 16
    }

    /// Highly damped so the drawer settles without visible bounce; Reduce Motion swaps it for a
    /// short transition with no overshoot at all.
    private var settleAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.22) : .spring(response: 0.38, dampingFraction: 0.92)
    }

    private func settleDrawer(to detent: MapDrawerModel.Detent) {
        withAnimation(settleAnimation) { drawerModel.settle(to: detent) }
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
            KaidoMapCanvas(
                viewport: $viewport,
                showBikeLanes: showBikeLanes,
                selectedDestination: searchViewModel.selectedDestination,
                searchResults: searchViewModel.selectedDestination == nil ? searchViewModel.filteredResults : [],
                onSelectResult: { result in selectDestination(result) },
                routeOptions: navigationViewModel.routeOptions,
                onSelectRoute: { option in
                    Task {
                        await navigationViewModel.selectRoute(option)
                        overviewSelectedRoute()
                        expandRouteDetails()
                    }
                },
                onTapBasemapPOI: selectBasemapPOI
            )

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
            // Wrapped so only this reads the live drawer position — it rides the drawer
            // continuously, while this view's body stays out of the per-frame path.
            .modifier(DrawerCoupledControls(model: drawerModel))

            // With search moved into the drawer, the legend can occupy the top-right corner.
            if showBikeLanes && searchViewModel.results.isEmpty {
                BikeLaneLegend()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 16)
                    .padding(.trailing, 16)
            }

            // Full-bleed: flush to the left, right, and bottom edges in every state, with no
            // external margins. Rounded corners live on the drawer's own surface.
            mapDrawer
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .zIndex(2)
        }
        // Geometry now comes from the drawer's own view controller, in viewDidLayoutSubviews,
        // so there's a single source for it rather than two that can disagree.
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
        .onChange(of: searchViewModel.selectedDestination?.id) { _, destinationID in
            isRouteDetailsExpanded = false
            isTurnDetailsExpanded = false
            // Shorter medium detent while a place card is up so the map stays the hero.
            drawerModel.mediumTopFractionOverride = destinationID == nil ? nil : 0.55
        }
        // Frame every candidate pin as results come in (or a category pill narrows them),
        // so the rider can see what's nearby without manually panning to find it.
        .onChange(of: searchViewModel.filteredResults) { _, newResults in
            guard searchViewModel.selectedDestination == nil, !newResults.isEmpty else { return }
            guard let fitted = MapViewportFollow.fit(newResults.map(\.coordinate), bottomPadding: followBottomPadding) else {
                return
            }
            withViewportAnimation(.default(maxDuration: 1)) {
                viewport = fitted
            }
        }
        // Live dictation streams straight into the query, so debounce, suggestions, and results
        // behave exactly as they do for typing.
        .onChange(of: speechService.liveTranscript) { _, transcript in
            guard speechService.isRecording else { return }
            searchViewModel.query = transcript
        }
        // Follow framing depends on drawer height — keep the puck above the chrome. Keyed off
        // the settled detent, so it fires once per resize rather than once per frame.
        .onChange(of: drawerModel.detent) { _, _ in
            if viewport.followPuck != nil {
                viewport = MapViewportFollow.live(bottomPadding: followBottomPadding)
            }
        }
        // Tapping the field expands and opens the keyboard. Dragging to full deliberately does
        // not focus — expansion and focus are separate intents.
        .onChange(of: isSearchFocused) { _, focused in
            drawerModel.isSearchFocused = focused
            // Focus is the only thing that raises the keyboard here, so it tracks focus.
            drawerModel.isKeyboardVisible = focused
            if focused { settleDrawer(to: .full) }
        }
        .onChange(of: drawerModel.isSearchFocused) { _, focused in
            // The drawer asks for dismissal on a downward drag; mirror it back to the field.
            if !focused, isSearchFocused { isSearchFocused = false }
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

    /// Shared chrome for both the destination field and the origin field — same pill, same
    /// trailing controls, only the placeholder and what "clear" means differ per call site.
    private func searchBar(placeholder: String, onClear: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $searchViewModel.query)
                .focused($isSearchFocused)
                .submitLabel(.search)
            if !searchViewModel.query.isEmpty {
                Button {
                    onClear()
                    isSearchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }

            if isDictationAvailable {
                Button(action: toggleDictation) {
                    Image(systemName: speechService.isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(speechService.isRecording ? Color.statusCritical : Color.kaidoDim)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(speechService.isRecording ? "Stop dictation" : "Dictate a destination")
            }
        }
        .padding(.leading, 14)
        // Trailing inset shrinks when a trailing control is present, since those carry their
        // own 44pt targets and would otherwise sit too far inboard.
        .padding(.trailing, (isDictationAvailable || !searchViewModel.query.isEmpty) ? 2 : 14)
        .frame(minHeight: 48)
        .background(Color.kaidoInk.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.kaidoInk.opacity(0.08), lineWidth: 1)
        }
    }

    /// Reused for both destination results and origin results — `onSelect` is the only thing
    /// that differs between the two contexts.
    private func resultsList(onSelect: @escaping (SearchResult) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(searchViewModel.filteredResults) { result in
                Button {
                    onSelect(result)
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

                if result.id != searchViewModel.filteredResults.last?.id {
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
        DrawerPanHost(
            model: drawerModel,
            reduceMotion: reduceMotion
        ) {
            if isEditingOrigin {
                originSearchHeader
            } else if let destination = searchViewModel.selectedDestination {
                placeDetailsSheetHeader(destination)
            } else {
                mapSearchSheetHeader
            }
        } content: {
            if isEditingOrigin {
                originSearchContent
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
            } else if let destination = searchViewModel.selectedDestination {
                placeDetailsContent(destination)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
            } else {
                mapSearchContent
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
            }
        }
        // The keyboard must not resize the drawer's container. If it does, every detent is
        // recomputed against a shorter viewport and the drawer re-animates underneath whatever
        // is being typed. Presenting the keyboard should only reduce the body's scroll height.
        .ignoresSafeArea(.keyboard)
        // Attached to the drawer rather than to the screen's ZStack, whose one sheet slot
        // already belongs to the Ride Together display-name prompt.
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .profile:
                NavigationStack { ProfileView() }
            case .bike(let bike):
                BikeProfileEditorView(
                    profile: bike,
                    onSave: {
                        BikeProfileStore.activate(bike, among: bikeProfiles)
                        bleManager.apply(profile: bike)
                        try? modelContext.save()
                        // Route times are derived from this, so re-price them immediately.
                        navigationViewModel.updateRideTimeProfile(activeRideTimeProfile)
                    },
                    onDelete: {
                        modelContext.delete(bike)
                        try? modelContext.save()
                        navigationViewModel.updateRideTimeProfile(activeRideTimeProfile)
                    }
                )
            }
        }
    }

    /// Identical geometry in every state — it translates with the drawer rather than becoming a
    /// different component. No divider beneath it: the glass edge already separates it.
    private var mapSearchSheetHeader: some View {
        VStack(spacing: 0) {
            drawerGrabber

            HStack(spacing: 10) {
                searchBar(placeholder: "Search for a destination") { clearDestination() }
                profileButton
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
    }

    /// The origin field's own header, layered over the destination-picked state rather than
    /// replacing it — `selectedDestination` stays set the whole time.
    private var originSearchHeader: some View {
        VStack(spacing: 0) {
            drawerGrabber

            HStack(spacing: 10) {
                searchBar(placeholder: "Search for a starting point") { searchViewModel.resetQuery() }

                Button {
                    endEditingOrigin()
                } label: {
                    Text("Cancel")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.kaidoVioletOnMap)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
    }

    /// Opens the existing account screen. Presented from the drawer rather than this view
    /// because the ZStack's one sheet slot is taken by the display-name prompt.
    ///
    /// Reuses `RiderAvatarView` rather than a generic glyph so this button shows the rider's own
    /// photo once they've set one — same avatar, same initials-fallback, as the Profile tab itself.
    private var profileButton: some View {
        Button {
            presentedSheet = .profile
        } label: {
            RiderAvatarView(
                displayName: riderProfiles.first?.displayName ?? "",
                photoImage: riderProfiles.first?.photoData.flatMap(UIImage.init(data:)),
                size: 48
            )
            .overlay {
                Circle().stroke(Color.kaidoInk.opacity(0.08), lineWidth: 1)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile")
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
                if searchViewModel.categoryTallies.count > 1 {
                    CategoryPillsView(
                        categories: searchViewModel.categoryTallies,
                        selected: $searchViewModel.selectedCategory
                    )
                }
                resultsList(onSelect: { result in selectDestination(result) })
            } else if let message = speechErrorMessage ?? searchViewModel.searchError {
                Text(message)
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

    /// Origin search's own content — no recents/discover/saved places, since those exist to
    /// help pick a destination. "Current Location" pinned above the results is what reverting
    /// to the implicit default looks like.
    private var originSearchContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            currentLocationRow

            if searchViewModel.isSearching {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Searching…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if !searchViewModel.results.isEmpty {
                resultsList(onSelect: { selectOrigin($0) })
            } else if let searchError = searchViewModel.searchError {
                Text(searchError)
                    .font(.caption)
                    .foregroundStyle(Color.statusCritical)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.statusCritical.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var currentLocationRow: some View {
        Button {
            selectOrigin(nil)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "location.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.kaidoVioletOnMap)
                    .frame(width: 24, height: 24)
                Text("Current Location")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.kaidoInk.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
    }

    private var savedPlacesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Places")

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

    /// Shown only when the recogniser could actually run. A permanently dead mic would be
    /// exactly the decorative control the brief ruled out.
    private var isDictationAvailable: Bool {
        switch speechService.availability {
        case .available, .permissionNotDetermined: true
        case .permissionDenied, .restricted, .recognizerUnavailable: false
        }
    }

    /// Dictates into the existing search field — the transcript is just text, so debouncing,
    /// suggestions, and results all keep working unchanged.
    private func toggleDictation() {
        speechErrorMessage = nil

        if speechService.isRecording {
            let transcript = speechService.stopRecording()
            RideAudioCoordinator.shared.endSpeechCapture()
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                speechErrorMessage = SpeechQuickMessageError.emptyTranscript.localizedDescription
            } else {
                searchViewModel.query = trimmed
            }
            return
        }

        Task {
            if speechService.availability == .permissionNotDetermined {
                guard await speechService.requestPermission() else { return }
            }
            guard speechService.availability == .available else {
                speechErrorMessage = SpeechQuickMessageError.recognizerUnavailable.localizedDescription
                return
            }
            do {
                try RideAudioCoordinator.shared.beginSpeechCapture()
                try speechService.startRecording()
                // Dictating implies searching — bring the drawer up so results have room.
                settleDrawer(to: .full)
            } catch {
                RideAudioCoordinator.shared.endSpeechCapture()
                speechErrorMessage = SpeechQuickMessageError.recognizerUnavailable.localizedDescription
            }
        }
    }

    /// Section headings carry a disclosure chevron so they read as openable groups.
    private func sectionHeading(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.kaidoDim)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// One rounded glass group holding every recent, rather than a stack of separate cards, with
    /// inset dividers between rows.
    private var recentsSection: some View {
        let places = Array(recentPlaces.prefix(8))
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeading("Recents")

            VStack(spacing: 0) {
                ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                    recentRow(place)

                    if index < places.count - 1 {
                        Divider()
                            .overlay(Color.kaidoInk.opacity(0.10))
                            // Inset so the rule starts past the leading icon.
                            .padding(.leading, 58)
                    }
                }
            }
            // A lighter nested treatment rather than a second glass surface. Real glass here
            // would mean blurring on top of the drawer's own blur, and this group translates
            // with every frame of a drag — blur-on-blur under motion is the single most
            // expensive thing on this screen.
            .background(Color.kaidoInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.kaidoInk.opacity(0.08), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func recentRow(_ place: SavedPlace) -> some View {
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
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .accessibilityLabel("More options for \(place.name)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 9)
    }

    private func placeDetailsContent(_ destination: SearchResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let requestError = navigationViewModel.requestError {
                Text(requestError)
                    .font(.caption)
                    .foregroundStyle(Color.statusCritical)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.statusCritical.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }

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
                preferenceAndPaceRow
                routeSummaryStrip

                if isRouteDetailsExpanded {
                    if navigationViewModel.routeOptions.count > 1 {
                        // Multiple options: pick one, then dig into hills/steps for it.
                        lightAlternatesList
                        routeDetailsDisclosure
                    } else {
                        // Only one route — the nested "Route details" toggle would just be a
                        // second tap to see the same thing the outer expand already promised.
                        routeDetailsBody
                    }
                }
            } else if !navigationViewModel.isRequestingRoute && navigationViewModel.requestError == nil {
                // A tapped basemap POI lands here — selectBasemapPOI deliberately skips the
                // auto route-preview every other selection path takes, so routing is this
                // explicit opt-in instead of something that happens the moment you tap a pin.
                Button {
                    fetchRoutes(to: destination)
                } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.kaidoVioletOnMap)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.kaidoViolet.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct PendingRideTogetherCreation {
        let destination: SearchResult
        let option: RouteOption
        let allOptions: [RouteOption]
    }

    /// Quiet/Fast preference and bike pace share one row — both shape the times above, so they
    /// sit together instead of burying pace under the turn list.
    private var preferenceAndPaceRow: some View {
        HStack(spacing: 8) {
            routingPreferencePill
            pacePill
            Spacer(minLength: 0)
        }
    }

    /// Secondary to GO, and tucked inside Route details rather than pinned under the summary —
    /// riding solo is the common case, so this only costs a tap for riders who actually want it.
    private var rideTogetherButton: some View {
        Button {
            Task { await startRideTogetherFlow() }
        } label: {
            if isCreatingRideTogether {
                ProgressView().frame(maxWidth: .infinity).frame(height: 22)
            } else {
                Label("Ride Together", systemImage: "person.2.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.kaidoVioletOnMap)
                    .frame(maxWidth: .infinity)
                    .frame(height: 22)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .disabled(isRouteUnavailable || isCreatingRideTogether)
        .opacity(isRouteUnavailable ? 0.48 : 1)
        .accessibilityHint("Invite other riders to navigate to this destination together")
    }

    /// Compact pace control beside Quiet roads — opens the active bike editor when one exists.
    @ViewBuilder
    private var pacePill: some View {
        let profile = navigationViewModel.rideTimeProfile

        if let activeBike = BikeProfileStore.activeProfile(in: bikeProfiles) {
            Button {
                presentedSheet = .bike(activeBike)
            } label: {
                pacePillLabel(profile.paceDescription, showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit this bike's pace settings")
        } else {
            pacePillLabel(profile.paceDescription, showsChevron: false)
        }
    }

    private func pacePillLabel(_ pace: String, showsChevron: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "bicycle")
                .font(.system(size: 12, weight: .semibold))
            Text(pace)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .foregroundStyle(showsChevron ? Color.kaidoVioletOnMap : Color.kaidoDim)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.kaidoInk.opacity(0.07), in: Capsule())
        .accessibilityLabel("Times for \(pace)")
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

        let originCoordinate = searchViewModel.selectedOrigin?.coordinate
            ?? locationManager.currentLocation?.coordinate
            ?? pending.destination.coordinate
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

    /// Compact Apple Maps–style GO — primary CTA for the summary strip.
    private var goButton: some View {
        Button {
            isPresentingNavigation = true
        } label: {
            Text("GO")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.kaidoInk)
                .frame(width: 72, height: 72)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.kaidoMidnight)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.kaidoViolet, Color.kaidoIndigo],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .opacity(0.92)
                        }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.kaidoVioletOnMap.opacity(0.42), lineWidth: 1)
                }
                .shadow(color: Color.kaidoViolet.opacity(0.28), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(isRouteUnavailable)
        .opacity(isRouteUnavailable ? 0.48 : 1)
        .accessibilityLabel("Start Navigation")
    }

    private var isRouteUnavailable: Bool {
        navigationViewModel.isRequestingRoute || navigationViewModel.navigationRoutes == nil
    }

    private func placeDetailsSheetHeader(_ destination: SearchResult) -> some View {
        VStack(spacing: 0) {
            drawerGrabber

            VStack(spacing: 6) {
                originRow
                destinationHeader(destination)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
    }

    /// Mirrors `destinationHeader`'s row shape so origin and destination read as one route, not
    /// two different components. The swap button stays disabled while origin is still "Current
    /// Location" — there's no coordinate to hand the destination slot until it's a real place.
    private var originRow: some View {
        HStack(spacing: 8) {
            Button {
                beginEditingOrigin()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: searchViewModel.selectedOrigin?.iconName ?? "location.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.kaidoDim)
                        .frame(width: 28, height: 28)
                        .background(Color.kaidoInk.opacity(0.07), in: Circle())

                    Text(searchViewModel.selectedOrigin?.name ?? "Current Location")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Starting point")
            .accessibilityValue(searchViewModel.selectedOrigin?.name ?? "Current Location")
            .accessibilityHint("Double tap to search for a different starting point")

            destinationHeaderButton(
                systemImage: "arrow.up.arrow.down",
                isSelected: false,
                accessibilityLabel: "Swap starting point and destination"
            ) {
                swapOriginAndDestination()
            }
            .disabled(searchViewModel.selectedOrigin == nil)
            .opacity(searchViewModel.selectedOrigin == nil ? 0.35 : 1)
        }
    }

    private var drawerGrabber: some View {
        Capsule()
            .fill(Color.kaidoDim.opacity(0.72))
            .frame(width: 42, height: 5)
            .padding(.top, 9)
            .padding(.bottom, 10)
            .accessibilityElement()
            .accessibilityLabel("Resize map drawer")
            .accessibilityValue(drawerModel.detent.accessibilityName)
            .accessibilityAdjustableAction { direction in
                if let next = drawerModel.step(direction) {
                    settleDrawer(to: next)
                }
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
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // Category and address on separate lines so the street doesn't get clipped by
                // the trailing action cluster.
                if let category = destination.category, !category.isEmpty {
                    Text(category.capitalized)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let address = destinationAddress(destination) {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

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
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// Street-level address with country stripped — local riders don't need "United States" eating
    /// the line. State is kept when it fits; wrapping handles longer boulevard names.
    private func destinationAddress(_ destination: SearchResult) -> String? {
        guard let address = destination.placeFormatted, !address.isEmpty else { return nil }
        let trimmed = address
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.localizedCaseInsensitiveContains("United States") }
            .joined(separator: ", ")
        return trimmed.isEmpty ? address : trimmed
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

    /// Apple Maps–style preference control: one pill that opens Quiet roads / Fastest.
    private var routingPreferencePill: some View {
        Menu {
            ForEach(RoutingPreference.allCases) { preference in
                Button {
                    navigationViewModel.preference = preference
                } label: {
                    Label(preference.menuTitle, systemImage: preference.systemImage)
                }
                .accessibilityLabel(preference.accessibilityLabel)
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: navigationViewModel.preference.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(navigationViewModel.preference.menuTitle)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(Color.kaidoVioletOnMap)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.kaidoViolet.opacity(0.16), in: Capsule())
        }
        .disabled(navigationViewModel.isRequestingRoute)
        .accessibilityLabel("Routing style")
        .accessibilityValue(navigationViewModel.preference.menuTitle)
        .accessibilityHint("Changes which route Kaido recommends among alternatives")
    }

    /// Resting summary: large duration, arrival/distance/stress meta, stress bar, and GO.
    @ViewBuilder
    private var routeSummaryStrip: some View {
        if let option = navigationViewModel.routeOptions.first(where: \.isMain) {
            HStack(alignment: .center, spacing: 14) {
                // The whole summary — not a separate icon — is the expand/collapse target, so
                // there's no dedicated affordance competing with GO for attention.
                Button {
                    toggleRouteDetailsExpanded()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Self.formattedDuration(option.personalizedTravelTime))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.primary)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)

                        Text(routeSummaryMeta(for: option))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        RouteStressBar(
                            quiet: option.stressProfile.quietFraction,
                            mixed: option.stressProfile.mixedFraction,
                            busy: option.stressProfile.busyFraction
                        )
                        .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Other routes")
                .accessibilityValue(isRouteDetailsExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint("Double tap to show or hide alternate routes and route details")

                goButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.kaidoInk.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func routeSummaryMeta(for option: RouteOption) -> String {
        var parts = [
            "Arrive \(formattedArrival(after: option.personalizedTravelTime))",
            formattedDistance(option.distanceMeters),
            stressShortLabel(for: option.stressProfile.score),
        ]
        if let elevation = navigationViewModel.elevationByRouteId[option.id] {
            parts.append(elevation.hillLabel)
            if elevation.gainMeters >= 1 {
                parts.append("+\(formattedElevationClimb(elevation.gainMeters))")
            }
        }
        return parts.joined(separator: " · ")
    }

    private func formattedElevationClimb(_ meters: Double) -> String {
        let feet = Measurement(value: meters, unit: UnitLength.meters).converted(to: .feet).value
        let rounded = feet.formatted(.number.precision(.fractionLength(0)))
        return "\(rounded) ft"
    }

    /// Nested disclosure — hills + turn list stay out of the primary expand until asked for.
    private var routeDetailsDisclosure: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(
                    reduceMotion
                        ? .easeOut(duration: 0.2)
                        : .spring(response: 0.35, dampingFraction: 0.86)
                ) {
                    isTurnDetailsExpanded.toggle()
                }
                if isTurnDetailsExpanded {
                    settleDrawer(to: .full)
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Route details")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.kaidoDim)
                        .rotationEffect(.degrees(isTurnDetailsExpanded ? 0 : -90))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Color.kaidoInk.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Route details")
            .accessibilityValue(isTurnDetailsExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Double tap to show or hide hills and turn-by-turn steps")

            if isTurnDetailsExpanded {
                routeDetailsBody
            }
        }
    }

    /// Ride Together, hills, and steps — shown either under the nested "Route details" toggle
    /// (when there are alternates to pick between first) or directly under the outer expand
    /// (when there's only one route, so that extra toggle would be redundant).
    @ViewBuilder
    private var routeDetailsBody: some View {
        if let rideTogetherErrorMessage {
            Text(rideTogetherErrorMessage)
                .font(.caption)
                .foregroundStyle(Color.statusCritical)
        }
        rideTogetherButton
        Divider().opacity(0.35)
        hillsDetailRow
        routeStepsSection
    }

    /// Expanded hills block — label, gain/loss, and Terrain sparkline when samples exist.
    @ViewBuilder
    private var hillsDetailRow: some View {
        if let main = navigationViewModel.routeOptions.first(where: \.isMain),
           let elevation = navigationViewModel.elevationByRouteId[main.id] {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "mountain.2.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.kaidoDim)
                        .frame(width: 22, alignment: .center)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(elevation.hillLabel)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.primary)

                        Text(hillsDetailSubtitle(elevation))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                if elevation.elevationsMeters.count >= 3 {
                    ElevationSparkline(elevationsMeters: elevation.elevationsMeters)
                        .padding(.leading, 34)
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Hills")
            .accessibilityValue("\(elevation.hillLabel), \(hillsDetailSubtitle(elevation))")
        }
    }

    private func hillsDetailSubtitle(_ elevation: ElevationProfile) -> String {
        var parts: [String] = []
        if elevation.gainMeters >= 1 {
            parts.append("+\(formattedElevationClimb(elevation.gainMeters))")
        }
        if elevation.lossMeters >= 1 {
            parts.append("−\(formattedElevationClimb(elevation.lossMeters))")
        }
        return parts.isEmpty ? "No significant climb" : parts.joined(separator: " · ")
    }

    /// Light alternate rows — only shown when there is more than one option. Selecting one
    /// promotes it for GO. Stress text is omitted when it matches the selected route so the
    /// summary strip isn't restated on every row.
    private var lightAlternatesList: some View {
        let options = navigationViewModel.routeOptions
        let main = options.first(where: \.isMain)
        let mainStress = main.map { stressShortLabel(for: $0.stressProfile.score) }
        let mainElevation = main.flatMap { navigationViewModel.elevationByRouteId[$0.id] }

        return VStack(alignment: .leading, spacing: 0) {
            Text("Other routes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            ForEach(options) { option in
                Button {
                    Task {
                        await navigationViewModel.selectRoute(option)
                        overviewSelectedRoute()
                    }
                } label: {
                    lightAlternateRow(
                        option,
                        mainStressLabel: mainStress,
                        mainElevation: mainElevation
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(routeAccessibilityLabel(for: option))
                .accessibilityAddTraits(option.isMain ? [.isSelected] : [])

                if option.id != options.last?.id {
                    Divider().opacity(0.35)
                }
            }
        }
    }

    private func lightAlternateRow(
        _ option: RouteOption,
        mainStressLabel: String?,
        mainElevation: ElevationProfile?
    ) -> some View {
        let stressLabel = stressShortLabel(for: option.stressProfile.score)
        let showStress = mainStressLabel == nil || stressLabel != mainStressLabel
        let elevation = navigationViewModel.elevationByRouteId[option.id]
        let showElevation: Bool = {
            guard let elevation else { return false }
            guard let mainElevation else { return true }
            return elevation.hillLabel != mainElevation.hillLabel
                || abs(elevation.gainMeters - mainElevation.gainMeters) >= 10
        }()

        return HStack(spacing: 10) {
            Circle()
                .fill(Self.routeColor(for: option, in: navigationViewModel.routeOptions))
                .frame(width: 8, height: 8)

            Text(Self.formattedDuration(option.personalizedTravelTime))
                .font(.subheadline.weight(option.isMain ? .semibold : .medium))
                .foregroundStyle(option.isMain ? Color.primary : Color.secondary)

            Text(formattedDistance(option.distanceMeters))
                .font(.caption)
                .foregroundStyle(.secondary)

            if showStress {
                Text(stressLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(quietColor(for: option.stressProfile.score))
                    .lineLimit(1)
            }

            if showElevation, let elevation {
                Text(elevation.hillLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if option.isMain {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.kaidoVioletOnMap)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func formattedArrival(after seconds: TimeInterval) -> String {
        Date().addingTimeInterval(seconds).formatted(date: .omitted, time: .shortened)
    }

    /// Google Maps–style turn list for the selected route. Lives in the expanded drawer body so
    /// riders can scan the ride before tapping GO.
    @ViewBuilder
    private var routeStepsSection: some View {
        let steps = navigationViewModel.mainRoutePreviewSteps
        if !steps.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Steps")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .padding(.top, 4)

                VStack(spacing: 0) {
                    ForEach(steps) { step in
                        routeStepRow(step)
                        if step.id != steps.last?.id {
                            Divider().opacity(0.35).padding(.leading, 34)
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Turn-by-turn steps")
        }
    }

    private func routeStepRow(_ step: PreviewRouteStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: step.maneuverSymbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.kaidoVioletOnMap)
                .frame(width: 22, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.instructions)
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if step.distanceMeters > 0 {
                    Text(NavigationBannerModel.distanceText(step.distanceMeters))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func toggleRouteDetailsExpanded() {
        if isRouteDetailsExpanded {
            withAnimation(
                reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.86)
            ) {
                isRouteDetailsExpanded = false
                isTurnDetailsExpanded = false
            }
            settleDrawer(to: .medium)
        } else {
            expandRouteDetails()
        }
    }

    private func expandRouteDetails() {
        withAnimation(
            reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.86)
        ) {
            isRouteDetailsExpanded = true
        }
        // Alternates and the Route details disclosure need room above the tab bar.
        settleDrawer(to: .full)
    }

    /// Quiet routes read sage, mixed brass, busy clay — the status colours, used here for a
    /// qualitative state rather than to label a quantity.
    private func quietColor(for stress: Double) -> Color {
        switch stress {
        case ..<0.35: .statusGood
        case ..<0.55: .statusCaution
        default: .statusCritical
        }
    }

    /// Short form of `RouteStressScorer.Profile.headline` for the one-line summary row — same
    /// score bands, a phrase instead of a sentence.
    private func stressShortLabel(for score: Double) -> String {
        switch score {
        case ..<0.35: "Mostly quiet"
        case ..<0.55: "Mixed"
        default: "Busier roads"
        }
    }

    /// Violet remains the active route. Mapbox returns up to two cycling alternatives, which
    /// receive blue and coral respectively — deliberately separate from the mint used for bike
    /// lanes, so a rider can compare route choices without mistaking one for infrastructure.
    ///
    /// Static so `KaidoMapCanvas` can share it without a reference back to this view.
    static func routeColor(for option: RouteOption, in routeOptions: [RouteOption]) -> Color {
        guard !option.isMain else { return .kaidoViolet }
        let alternateIndex = routeOptions
            .filter { !$0.isMain }
            .firstIndex { $0.id == option.id } ?? 0

        switch alternateIndex % 2 {
        case 0: return .routeBlueOnMap
        default: return .routeCoralOnMap
        }
    }

    private func routeAccessibilityLabel(for option: RouteOption) -> String {
        let duration = Self.formattedDuration(option.personalizedTravelTime)
        let distance = formattedDistance(option.distanceMeters)
        let selected = option.isMain ? ", selected" : ""
        return "Your ride time \(duration) with \(navigationViewModel.rideTimeProfile.paceDescription), \(distance), \(option.stressProfile.headline), \(option.stressProfile.summary)\(selected)"
    }

    /// Static so `KaidoMapCanvas`'s on-map ETA badges can share it, same treatment as `routeColor`.
    static func formattedDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? ""
    }

    private func formattedDistance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    private func selectDestination(_ result: SearchResult, previewRoute: Bool = true) {
        isFreeRideEnabled = false
        isEditingOrigin = false
        discoverViewModel.clear()
        recordRecent(result)
        searchViewModel.selectResult(result)
        navigationViewModel.clear()
        isSearchFocused = false
        drawerModel.mediumTopFractionOverride = 0.55
        settleDrawer(to: .medium)
        withViewportAnimation(.default(maxDuration: 1)) {
            viewport = .camera(center: result.coordinate, zoom: 15)
                .padding(.bottom, followBottomPadding)
        }
        if previewRoute {
            fetchRoutes(to: result)
        }
    }

    /// A rider tapped one of the Standard style's own POI icons on the base map (not a search
    /// result) — build a lightweight `SearchResult` locally, no network round trip, and show the
    /// same place card everything else uses, but without auto-starting a route preview.
    private func selectBasemapPOI(name: String, coordinate: CLLocationCoordinate2D, maki: String?) {
        guard !isPresentingNavigation else { return }
        let (iconName, placeCategory) = PlaceCategory.categorize(maki: maki, isPOI: true)
        let result = SearchResult(
            id: "basemap:\(coordinate.latitude),\(coordinate.longitude)",
            name: name,
            placeFormatted: nil,
            coordinate: coordinate,
            category: placeCategory.label,
            iconName: iconName,
            isPOI: true,
            placeCategory: placeCategory
        )
        selectDestination(result, previewRoute: false)
    }

    private func beginEditingOrigin() {
        searchViewModel.beginEditingOrigin()
        isEditingOrigin = true
        isSearchFocused = true
    }

    private func endEditingOrigin() {
        isEditingOrigin = false
        searchViewModel.activeTarget = .destination
        isSearchFocused = false
    }

    /// `result == nil` means "Current Location" was tapped — reverts to the implicit default
    /// rather than picking a place.
    private func selectOrigin(_ result: SearchResult?) {
        if let result {
            recordRecent(result)
            searchViewModel.selectResult(result)
        } else {
            searchViewModel.selectedOrigin = nil
            searchViewModel.resetQuery()
        }
        endEditingOrigin()
        if let destination = searchViewModel.selectedDestination {
            navigationViewModel.clear()
            fetchRoutes(to: destination)
        }
    }

    /// Only reachable once origin is explicit — the button is disabled until then, since
    /// "Current Location" has no coordinate to hand the destination slot.
    private func swapOriginAndDestination() {
        guard let newDestination = searchViewModel.selectedOrigin,
              searchViewModel.selectedDestination != nil
        else { return }
        searchViewModel.swapOriginAndDestination()
        recordRecent(newDestination)
        navigationViewModel.clear()
        fetchRoutes(to: newDestination)
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
        isEditingOrigin = false
        searchViewModel.clearSelection()
        navigationViewModel.clear()
        drawerModel.mediumTopFractionOverride = nil
        settleDrawer(to: .medium)
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
        guard let originCoordinate = searchViewModel.selectedOrigin?.coordinate
            ?? locationManager.currentLocation?.coordinate
        else {
            navigationViewModel.requestError = "Waiting for your location…"
            return
        }
        Task {
            navigationViewModel.updateRideTimeProfile(activeRideTimeProfile)
            await navigationViewModel.requestRoutes(
                waypointCoordinates: [originCoordinate, destination.coordinate]
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
