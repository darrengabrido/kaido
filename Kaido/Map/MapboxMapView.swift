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
    /// Canonical drawer state. Held here so it survives content changes, but this view's body
    /// never reads `height` or `progress` — only the drawer and the map-control stack do, which
    /// is what keeps a drag off this view's frame budget.
    @State private var drawerModel = MapDrawerModel()
    @FocusState private var isSearchFocused: Bool
    /// Same recogniser Ride Together dictation uses — the mic only appears when it can actually
    /// record, so the control is never decorative.
    @State private var speechService = SpeechQuickMessageService()
    @State private var speechErrorMessage: String?
    @State private var isPresentingProfile = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Ride Together
    @State private var isPresentingRideTogetherLobby = false
    @State private var isPresentingRideTogetherNamePrompt = false
    @State private var pendingRideTogetherCreation: PendingRideTogetherCreation?
    @State private var pendingRawInviteToken: String?
    @State private var rideTogetherErrorMessage: String?
    @State private var isCreatingRideTogether = false

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
                onSelectResult: selectDestination,
                routeOptions: navigationViewModel.routeOptions
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

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(searchViewModel.filteredResults) { result in
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
            if let destination = searchViewModel.selectedDestination {
                placeDetailsSheetHeader(destination)
            } else {
                mapSearchSheetHeader
            }
        } content: {
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
        // The keyboard must not resize the drawer's container. If it does, every detent is
        // recomputed against a shorter viewport and the drawer re-animates underneath whatever
        // is being typed. Presenting the keyboard should only reduce the body's scroll height.
        .ignoresSafeArea(.keyboard)
        // Attached to the drawer rather than to the screen's ZStack, whose one sheet slot
        // already belongs to the Ride Together display-name prompt.
        .sheet(isPresented: $isPresentingProfile) {
            NavigationStack { ProfileView() }
        }
    }

    /// Identical geometry in every state — it translates with the drawer rather than becoming a
    /// different component. No divider beneath it: the glass edge already separates it.
    private var mapSearchSheetHeader: some View {
        VStack(spacing: 0) {
            drawerGrabber

            HStack(spacing: 10) {
                searchBar
                profileButton
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
    }

    /// Opens the existing account screen. Presented from the drawer rather than this view
    /// because the ZStack's one sheet slot is taken by the display-name prompt.
    private var profileButton: some View {
        Button {
            isPresentingProfile = true
        } label: {
            Image(systemName: "person.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.kaidoInk)
                .frame(width: 48, height: 48)
                .background(Color.kaidoInk.opacity(0.08), in: Circle())
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
                resultsList
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
        }
        .frame(maxWidth: .infinity)
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
                                    .fill(Self.routeColor(for: option, in: navigationViewModel.routeOptions))
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
    ///
    /// Static so `KaidoMapCanvas` (a separate view, so the map isn't rebuilt on every search
    /// drawer drag frame) can share this without needing a reference back to this view.
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
        settleDrawer(to: .medium)
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
