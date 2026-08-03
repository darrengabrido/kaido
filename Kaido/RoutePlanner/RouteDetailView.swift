import SwiftUI
import SwiftData
import MapboxMaps

struct RouteDetailView: View {
    let route: Route

    @Environment(\.modelContext) private var modelContext
    @Environment(BikeBLEManager.self) private var bleManager
    @Environment(GroupRideSessionStore.self) private var rideTogetherSession
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
                    BikeLaneMapLayers()
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
                        .foregroundStyle(showBikeLanes ? Color.kaidoDim : Color.secondary)
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
                    StatTile(value: formattedDistance, label: "distance", tint: .kaidoDim)
                    StatTile(value: formattedElevation, label: "ft climb", tint: .kaidoDim)
                }

                if let requestError = navigationViewModel.requestError {
                    Text(requestError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Picker("Routing style", selection: $navigationViewModel.preference) {
                    ForEach(RoutingPreference.allCases) { preference in
                        Label(preference.title, systemImage: preference.systemImage)
                            .tag(preference)
                            .accessibilityLabel(preference.accessibilityLabel)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(navigationViewModel.isRequestingRoute)

                Button {
                    Task {
                        navigationViewModel.updateRideTimeProfile(activeRideTimeProfile)
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

                if let rideTogetherErrorMessage {
                    Text(rideTogetherErrorMessage)
                        .font(.caption)
                        .foregroundStyle(Color.statusCritical)
                }

                Button {
                    Task { await startRideTogetherFlow() }
                } label: {
                    if isCreatingRideTogether {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label("Ride Together", systemImage: "person.2.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.kaidoViolet)
                .disabled(isCreatingRideTogether || navigationViewModel.isRequestingRoute || coordinates.count < 2)
                .accessibilityHint("Invite other riders to navigate this route together")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
            .padding()
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            navigationViewModel.updateRideTimeProfile(activeRideTimeProfile)
        }
        .onChange(of: activeRideTimeProfile) { _, profile in
            navigationViewModel.updateRideTimeProfile(profile)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    route.isFavorite.toggle()
                } label: {
                    Image(systemName: route.isFavorite ? "star.fill" : "star")
                }
                .tint(.kaidoViolet)
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
                onCancel: { isPresentingRideTogetherNamePrompt = false }
            )
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
        // Group metadata only — never other riders' locations or identities.
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
