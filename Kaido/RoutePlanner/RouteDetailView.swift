import SwiftUI
import SwiftData
import MapboxMaps
import CoreLocation

/// Same draggable bottom-drawer language as the Map tab's place card
/// (`MapboxMapView.placeDetailsContent`) — a full-bleed sheet over the map instead of a floating
/// card, with a matching icon+name header and the same two-stage "duration chevron → alternates +
/// Route details" disclosure. Kept as its own view rather than sharing code with `MapboxMapView`
/// because the two screens' state (a fixed saved route vs. a live search destination) differs
/// enough that a shared abstraction would just be indirection — see how `preferenceAndPaceRow`,
/// `hillsDetailRow`, etc. are already duplicated between the two files.
struct RouteDetailView: View {
    let route: Route

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(BikeBLEManager.self) private var bleManager
    @Environment(GroupRideSessionStore.self) private var rideTogetherSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \BikeProfile.lastConnectedAt, order: .reverse) private var bikeProfiles: [BikeProfile]

    @State private var viewport: Viewport
    @State private var navigationViewModel = NavigationViewModel()
    @State private var isPresentingNavigation = false
    @State private var showBikeLanes = true
    @State private var isPresentingRideTogetherLobby = false
    @State private var isPresentingRideTogetherNamePrompt = false
    @State private var pendingRawInviteToken: String?
    @State private var isCreatingRideTogether = false
    @State private var rideTogetherErrorMessage: String?
    @State private var isPresentingShareToCommunitySheet = false
    @State private var isPresentingCommunityNamePrompt = false
    @State private var isUpdatingCommunityShare = false
    @State private var communityErrorMessage: String?
    private let communityRouteService: CommunityRouteService = CompositeCommunityRouteService()
    /// Outer disclosure — chevron next to the duration reveals alternates + Route details.
    @State private var isRouteDetailsExpanded = false
    /// Nested under the expanded card — Steps + Hills live here so they aren't one long dump.
    @State private var isTurnDetailsExpanded = false
    @State private var isPresentingBikeEditor = false
    @State private var didPersistElevation = false
    @State private var drawerModel = MapDrawerModel()

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

    private var previewPolyline: [CLLocationCoordinate2D] {
        if let main = navigationViewModel.routeOptions.first(where: \.isMain),
           main.coordinates.count > 1 {
            return main.coordinates
        }
        return coordinates
    }

    private var mainOption: RouteOption? {
        navigationViewModel.routeOptions.first(where: \.isMain)
    }

    private var isRouteUnavailable: Bool {
        navigationViewModel.isRequestingRoute || navigationViewModel.navigationRoutes == nil
    }

    /// Highly damped so the drawer settles without visible bounce; Reduce Motion swaps it for a
    /// short transition with no overshoot at all. Mirrors `MapboxMapView`'s drawer.
    private var settleAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.22) : .spring(response: 0.38, dampingFraction: 0.92)
    }

    private func settleDrawer(to detent: MapDrawerModel.Detent) {
        withAnimation(settleAnimation) { drawerModel.settle(to: detent) }
    }

    /// Keeps the route line above the drawer's resting edge, the same way the Map tab's
    /// `followBottomPadding` keeps the puck above its drawer.
    private var drawerBottomPadding: CGFloat {
        drawerModel.height(for: drawerModel.detent) + 16
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(viewport: $viewport) {
                if showBikeLanes {
                    BikeLaneMapLayers()
                }

                if previewPolyline.count > 1 {
                    RouteGlowPolyline(coordinates: previewPolyline)
                }

                RouteEndpointAnnotations(coordinates: coordinates)
            }
            .mapStyle(.kaidoNight)
            .ignoresSafeArea()

            // Bike-lane toggle + legend ride above the drawer, same as the Map tab's map controls.
            VStack(spacing: 10) {
                Button {
                    showBikeLanes.toggle()
                } label: {
                    Image(systemName: "bicycle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(showBikeLanes ? Color.kaidoDim : Color.secondary)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular, in: Circle())

                if showBikeLanes {
                    BikeLaneLegend()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 16)
            .padding(.bottom, 16)
            .modifier(DrawerCoupledControls(model: drawerModel))

            routeDrawer
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .zIndex(2)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: route.persistentModelID) {
            // Shorter medium detent while the route card is up, so the map stays the hero —
            // same treatment the Map tab gives its place card.
            drawerModel.mediumTopFractionOverride = 0.55
            await prefetchPreview()
        }
        .onChange(of: activeRideTimeProfile) { _, profile in
            navigationViewModel.updateRideTimeProfile(profile)
        }
        .onChange(of: navigationViewModel.preference) { _, _ in
            overviewPreviewRoute()
        }
        .onChange(of: navigationViewModel.elevationByRouteId) { _, elevations in
            persistElevationIfNeeded(elevations)
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
                onCancel: { isPresentingRideTogetherNamePrompt = false }
            )
        }
        .sheet(isPresented: $isPresentingCommunityNamePrompt) {
            GroupRideDisplayNamePromptView(
                title: String(localized: "What should other riders see?"),
                message: String(localized: "Shown as the author on any route you share to the community."),
                onSubmit: { name in
                    isPresentingCommunityNamePrompt = false
                    GroupRideDisplayNameStore.current = name
                    isPresentingShareToCommunitySheet = true
                },
                onCancel: { isPresentingCommunityNamePrompt = false }
            )
        }
        .sheet(isPresented: $isPresentingShareToCommunitySheet) {
            ShareRouteToCommunitySheet(route: route) { name, description in
                try await publishToCommunity(name: name, description: description)
            }
        }
        .fullScreenCover(isPresented: $isPresentingNavigation) {
            if let navigationRoutes = navigationViewModel.navigationRoutes {
                ZStack(alignment: .bottomTrailing) {
                    NavigationSessionView(
                        navigationRoutes: navigationRoutes,
                        telemetry: bleManager.telemetry,
                        rideTimeProfile: navigationViewModel.rideTimeProfile,
                        groupRideSessionStore: rideTogetherSession.hasActiveRide ? rideTogetherSession : nil
                    ) { _ in
                        logRide()
                        isPresentingNavigation = false
                    }
                    .ignoresSafeArea()

                    RideHUDView(telemetry: bleManager.telemetry)
                        .padding(.trailing, 12)
                        .padding(.bottom, 100)
                }
            }
        }
    }

    // MARK: - Drawer

    private var routeDrawer: some View {
        DrawerPanHost(model: drawerModel, reduceMotion: reduceMotion) {
            routeDetailsSheetHeader
        } content: {
            routeDetailsContent
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 14)
        }
        .sheet(isPresented: $isPresentingBikeEditor) {
            if let bike = BikeProfileStore.activeProfile(in: bikeProfiles) {
                BikeProfileEditorView(
                    profile: bike,
                    onSave: {
                        BikeProfileStore.activate(bike, among: bikeProfiles)
                        bleManager.apply(profile: bike)
                        try? modelContext.save()
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

    private var drawerGrabber: some View {
        Capsule()
            .fill(Color.kaidoDim.opacity(0.72))
            .frame(width: 42, height: 5)
            .padding(.top, 9)
            .padding(.bottom, 10)
            .accessibilityElement()
            .accessibilityLabel("Resize route card")
            .accessibilityValue(drawerModel.detent.accessibilityName)
            .accessibilityAdjustableAction { direction in
                if let next = drawerModel.step(direction) {
                    settleDrawer(to: next)
                }
            }
    }

    // MARK: - Header

    private var routeDetailsSheetHeader: some View {
        VStack(spacing: 0) {
            drawerGrabber

            routeHeader
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
    }

    /// Mirrors `MapboxMapView.destinationHeader`'s shape — icon circle, name, and a trailing
    /// action cluster — but with a route's saved distance in place of a place's category/address.
    private var routeHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.kaidoVioletOnMap)
                .frame(width: 40, height: 40)
                .background(Color.kaidoViolet.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(route.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(formattedSavedDistance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            HStack(spacing: 6) {
                routeHeaderButton(
                    systemImage: route.isFavorite ? "star.fill" : "star",
                    isSelected: route.isFavorite,
                    accessibilityLabel: route.isFavorite ? "Remove from favorites" : "Add to favorites"
                ) {
                    route.isFavorite.toggle()
                }

                communityHeaderButton

                routeHeaderButton(
                    systemImage: "xmark",
                    isSelected: false,
                    accessibilityLabel: "Close route details"
                ) {
                    dismiss()
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// Same visual language as `routeHeaderButton`, but swaps in a spinner while a publish/remove
    /// request is in flight and toggles between the two community actions based on share state.
    private var communityHeaderButton: some View {
        Button {
            if route.sharedCommunityRouteId != nil {
                Task { await removeFromCommunity() }
            } else {
                startShareToCommunityFlow()
            }
        } label: {
            Group {
                if isUpdatingCommunityShare {
                    ProgressView()
                } else {
                    Image(systemName: route.sharedCommunityRouteId != nil ? "person.2.slash" : "globe")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .foregroundStyle(route.sharedCommunityRouteId != nil ? Color.kaidoVioletOnMap : Color.kaidoDim)
            .frame(width: 34, height: 34)
            .background(
                route.sharedCommunityRouteId != nil ? Color.kaidoViolet.opacity(0.18) : Color.kaidoInk.opacity(0.07),
                in: Circle()
            )
        }
        .buttonStyle(.plain)
        .disabled(isUpdatingCommunityShare || (route.sharedCommunityRouteId == nil && coordinates.count < 2))
        .accessibilityLabel(route.sharedCommunityRouteId != nil ? "Remove from Community" : "Share to Community")
    }

    private func routeHeaderButton(
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

    // MARK: - Drawer content

    /// Mirrors `MapboxMapView.placeDetailsContent`: loading/error states, then (once routes
    /// resolve) the preference row, summary strip, and the expanded disclosure (which now also
    /// holds Ride Together, alongside hills and steps).
    private var routeDetailsContent: some View {
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
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Preference + pace

    private var preferenceAndPaceRow: some View {
        HStack(spacing: 8) {
            routingPreferencePill
            pacePill
            Spacer(minLength: 0)
        }
    }

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
    }

    @ViewBuilder
    private var pacePill: some View {
        let profile = navigationViewModel.rideTimeProfile
        if let activeBike = BikeProfileStore.activeProfile(in: bikeProfiles) {
            Button {
                isPresentingBikeEditor = true
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

    // MARK: - Summary + GO

    /// Resting summary: large duration, arrival/distance/stress/hill meta, stress bar, and GO.
    /// The chevron next to the duration is the outer disclosure — same two-stage interaction as
    /// the Map tab's place card.
    @ViewBuilder
    private var routeSummaryStrip: some View {
        if let option = mainOption {
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
                .accessibilityLabel("Route details")
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

    /// Compact Apple Maps–style GO — primary CTA for the summary strip.
    private var goButton: some View {
        Button {
            Task { await startNavigation() }
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
        .accessibilityHint("Invite other riders to navigate this route together")
    }

    // MARK: - Route details disclosure

    /// Nested disclosure — hills + turn list stay out of the primary expand until asked for. No
    /// longer needs its own scroll-height cap: the drawer's own body already scrolls (see
    /// `DrawerSurface`), so a long step list just grows the drawer instead of the screen.
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
        if let communityErrorMessage {
            Text(communityErrorMessage)
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
        if let option = mainOption,
           let elevation = navigationViewModel.elevationByRouteId[option.id] {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "mountain.2.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.kaidoDim)
                        .frame(width: 22, alignment: .center)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(elevation.hillLabel)
                            .font(.subheadline.weight(.medium))
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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Hills")
            .accessibilityValue("\(elevation.hillLabel), \(hillsDetailSubtitle(elevation))")
        }
    }

    /// Google Maps–style turn list for the selected route.
    @ViewBuilder
    private var routeStepsSection: some View {
        let steps = navigationViewModel.mainRoutePreviewSteps
        if !steps.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Steps")
                    .font(.subheadline.weight(.semibold))
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

    // MARK: - Light alternates

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
                        overviewPreviewRoute()
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
                .fill(MapboxMapView.routeColor(for: option, in: navigationViewModel.routeOptions))
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

    /// Quiet routes read sage, mixed brass, busy clay — the status colours, used here for a
    /// qualitative state rather than to label a quantity.
    private func quietColor(for stress: Double) -> Color {
        switch stress {
        case ..<0.35: .statusGood
        case ..<0.55: .statusCaution
        default: .statusCritical
        }
    }

    private func routeAccessibilityLabel(for option: RouteOption) -> String {
        let duration = Self.formattedDuration(option.personalizedTravelTime)
        let distance = formattedDistance(option.distanceMeters)
        let selected = option.isMain ? ", selected" : ""
        return "Ride time \(duration) with \(navigationViewModel.rideTimeProfile.paceDescription), \(distance), \(option.stressProfile.headline), \(option.stressProfile.summary)\(selected)"
    }

    // MARK: - Formatting

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

    private var formattedSavedDistance: String {
        Measurement(value: route.distanceMeters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    private func formattedDistance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    private func formattedElevationClimb(_ meters: Double) -> String {
        let feet = Measurement(value: meters, unit: UnitLength.meters).converted(to: .feet).value
        let rounded = feet.formatted(.number.precision(.fractionLength(0)))
        return "\(rounded) ft"
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

    private func formattedArrival(after seconds: TimeInterval) -> String {
        Date().addingTimeInterval(seconds).formatted(date: .omitted, time: .shortened)
    }

    private func stressShortLabel(for score: Double) -> String {
        switch score {
        case ..<0.35: "Mostly quiet"
        case ..<0.55: "Mixed roads"
        default: "Busier roads"
        }
    }

    static func formattedDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? ""
    }

    // MARK: - Disclosure toggles

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

    // MARK: - Actions

    private func prefetchPreview() async {
        guard coordinates.count >= 2 else { return }
        navigationViewModel.updateRideTimeProfile(activeRideTimeProfile)
        await navigationViewModel.requestRoutes(waypointCoordinates: coordinates)
        overviewPreviewRoute()
    }

    private func startNavigation() async {
        if navigationViewModel.navigationRoutes == nil {
            navigationViewModel.updateRideTimeProfile(activeRideTimeProfile)
            await navigationViewModel.requestRoutes(waypointCoordinates: coordinates)
        }
        guard navigationViewModel.navigationRoutes != nil else { return }
        isPresentingNavigation = true
    }

    private func overviewPreviewRoute() {
        guard let main = mainOption, main.coordinates.count > 1 else { return }
        withViewportAnimation(.default(maxDuration: 1.0)) {
            viewport = .overview(
                geometry: LineString(main.coordinates),
                geometryPadding: EdgeInsets(
                    top: 72,
                    leading: 48,
                    bottom: drawerBottomPadding,
                    trailing: 48
                )
            )
        }
    }

    private func persistElevationIfNeeded(_ elevations: [String: ElevationProfile]) {
        guard !didPersistElevation,
              let option = mainOption,
              let profile = elevations[option.id],
              profile.gainMeters > 0
        else { return }

        // Keep the saved route's climb in sync for list/offline display.
        if abs(route.elevationGainMeters - profile.gainMeters) > 0.5 {
            route.elevationGainMeters = profile.gainMeters
            try? modelContext.save()
        }
        didPersistElevation = true
    }

    private func logRide() {
        let ride = Ride(route: route)
        ride.endedAt = Date()
        ride.distanceMeters = route.distanceMeters
        if let groupRide = rideTogetherSession.ride, rideTogetherSession.hasActiveRide {
            ride.groupRideId = groupRide.id
            ride.groupRideParticipantCount = rideTogetherSession.members.filter(\.isActive).count
            ride.wasGroupRideHost = rideTogetherSession.isHost
        }
        modelContext.insert(ride)
    }

    private func startRideTogetherFlow() async {
        if navigationViewModel.navigationRoutes == nil {
            navigationViewModel.updateRideTimeProfile(activeRideTimeProfile)
            await navigationViewModel.requestRoutes(waypointCoordinates: coordinates)
        }
        guard navigationViewModel.routeOptions.first(where: \.isMain) != nil else {
            rideTogetherErrorMessage = navigationViewModel.requestError
                ?? String(localized: "Couldn't prepare a route for this ride.")
            return
        }
        if GroupRideDisplayNameStore.current != nil {
            await createRideTogether(displayName: GroupRideDisplayNameStore.current ?? "Host")
        } else {
            isPresentingRideTogetherNamePrompt = true
        }
    }

    private func createRideTogether(displayName: String) async {
        guard let mainOption = navigationViewModel.routeOptions.first(where: \.isMain) else { return }
        isCreatingRideTogether = true
        rideTogetherErrorMessage = nil
        defer { isCreatingRideTogether = false }

        let snapshot = GroupRideRouteSnapshot(
            destinationName: route.name,
            waypointCoordinates: coordinates,
            selecting: mainOption,
            among: navigationViewModel.routeOptions
        )
        let destinationCoordinate = coordinates.last ?? mainOption.coordinates.last
            ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)

        do {
            let result = try await rideTogetherSession.createRide(
                destinationName: route.name,
                destination: destinationCoordinate,
                routeSnapshot: snapshot,
                title: route.name,
                displayName: displayName
            )
            pendingRawInviteToken = result.rawInviteToken
            isPresentingRideTogetherLobby = true
        } catch {
            rideTogetherErrorMessage = error.localizedDescription
        }
    }

    private var activeRideTimeProfile: RideTimeProfile {
        BikeProfileStore.activeProfile(in: bikeProfiles)?.rideTimeProfile ?? .defaultProfile
    }

    private func startShareToCommunityFlow() {
        if GroupRideDisplayNameStore.current != nil {
            isPresentingShareToCommunitySheet = true
        } else {
            isPresentingCommunityNamePrompt = true
        }
    }

    private func publishToCommunity(name: String, description: String?) async throws {
        let waypoints = route.orderedWaypoints.map {
            CommunityRoute.Waypoint(latitude: $0.latitude, longitude: $0.longitude, order: $0.order)
        }
        let displayName = GroupRideDisplayNameStore.current ?? "Rider"
        let published = try await communityRouteService.publish(
            name: name,
            description: description,
            distanceMeters: route.distanceMeters,
            elevationGainMeters: route.elevationGainMeters,
            waypoints: waypoints,
            displayName: displayName
        )
        GroupRideDisplayNameStore.current = displayName
        route.sharedCommunityRouteId = published.id
    }

    private func removeFromCommunity() async {
        guard let sharedCommunityRouteId = route.sharedCommunityRouteId else { return }
        isUpdatingCommunityShare = true
        communityErrorMessage = nil
        do {
            try await communityRouteService.remove(routeId: sharedCommunityRouteId)
            route.sharedCommunityRouteId = nil
        } catch {
            communityErrorMessage = error.localizedDescription
        }
        isUpdatingCommunityShare = false
    }
}
