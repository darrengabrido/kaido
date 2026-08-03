import Foundation
import CoreLocation
import MapboxDirections
import MapboxNavigationCore

struct RouteOption: Identifiable {
    let id: String
    let distanceMeters: Double
    /// Native Mapbox cycling duration retained for ranking and navigation internals.
    let expectedTravelTime: TimeInterval
    /// Rider-facing duration adjusted to the active bike's configured pace.
    let personalizedTravelTime: TimeInterval
    let stressProfile: RouteStressScorer.Profile
    let coordinates: [CLLocationCoordinate2D]
    let isMain: Bool
    fileprivate let alternativeRoute: AlternativeRoute?

    /// Explicit replacement for the compiler-synthesized memberwise initializer — adding the
    /// testable convenience initializer below would otherwise suppress it entirely, breaking
    /// every existing call site in `routeOptions`.
    fileprivate init(
        id: String,
        distanceMeters: Double,
        expectedTravelTime: TimeInterval,
        personalizedTravelTime: TimeInterval,
        stressProfile: RouteStressScorer.Profile,
        coordinates: [CLLocationCoordinate2D],
        isMain: Bool,
        alternativeRoute: AlternativeRoute?
    ) {
        self.id = id
        self.distanceMeters = distanceMeters
        self.expectedTravelTime = expectedTravelTime
        self.personalizedTravelTime = personalizedTravelTime
        self.stressProfile = stressProfile
        self.coordinates = coordinates
        self.isMain = isMain
        self.alternativeRoute = alternativeRoute
    }

    /// Testable/synthetic construction — `alternativeRoute` stays `nil`, so a `RouteOption` built
    /// this way behaves like `isMain` for `NavigationViewModel.selectRoute` purposes. Exists
    /// because the fileprivate initializer above would otherwise make `RouteOption` impossible to
    /// construct from outside this file — including from `GroupRideRouteSnapshot`'s tests.
    init(
        id: String,
        distanceMeters: Double,
        expectedTravelTime: TimeInterval,
        personalizedTravelTime: TimeInterval,
        stressProfile: RouteStressScorer.Profile,
        coordinates: [CLLocationCoordinate2D],
        isMain: Bool
    ) {
        self.init(
            id: id,
            distanceMeters: distanceMeters,
            expectedTravelTime: expectedTravelTime,
            personalizedTravelTime: personalizedTravelTime,
            stressProfile: stressProfile,
            coordinates: coordinates,
            isMain: isMain,
            alternativeRoute: nil
        )
    }
}

@Observable
@MainActor
final class NavigationViewModel {
    var isRequestingRoute = false
    var requestError: String?
    var navigationRoutes: NavigationRoutes?
    var rideTimeProfile: RideTimeProfile = .defaultProfile
    var preference: RoutingPreference = RoutingPreferenceStore.current {
        didSet {
            RoutingPreferenceStore.current = preference
            guard oldValue != preference else { return }
            // Re-rank in place — no network round-trip, so toggling never blanks routes.
            Task { await promotePreferredRoute() }
        }
    }

    private let directionsService = DirectionsService()

    var routeOptions: [RouteOption] {
        guard let navigationRoutes else { return [] }
        let main = navigationRoutes.mainRoute
        var options = [
            RouteOption(
                id: main.routeId.description,
                distanceMeters: main.route.distance,
                expectedTravelTime: main.route.expectedTravelTime,
                personalizedTravelTime: rideTimeProfile.personalizedDuration(
                    mapboxDuration: main.route.expectedTravelTime,
                    distanceMeters: main.route.distance
                ),
                stressProfile: RouteStressScorer.profile(for: main.route),
                coordinates: main.route.shape?.coordinates ?? [],
                isMain: true,
                alternativeRoute: nil
            )
        ]
        for alternative in navigationRoutes.alternativeRoutes {
            options.append(
                RouteOption(
                    id: alternative.routeId.description,
                    distanceMeters: alternative.route.distance,
                    expectedTravelTime: alternative.route.expectedTravelTime,
                    personalizedTravelTime: rideTimeProfile.personalizedDuration(
                        mapboxDuration: alternative.route.expectedTravelTime,
                        distanceMeters: alternative.route.distance
                    ),
                    stressProfile: RouteStressScorer.profile(for: alternative.route),
                    coordinates: alternative.route.shape?.coordinates ?? [],
                    isMain: false,
                    alternativeRoute: alternative
                )
            )
        }
        return options
    }

    func requestRoutes(waypointCoordinates: [CLLocationCoordinate2D]) async {
        isRequestingRoute = true
        requestError = nil
        defer { isRequestingRoute = false }
        do {
            navigationRoutes = try await directionsService.requestRoute(
                waypointCoordinates: waypointCoordinates
            )
            await promotePreferredRoute()
        } catch {
            navigationRoutes = nil
            requestError = error.localizedDescription
        }
    }

    /// Promotes `option` to the main route so navigation starts on whichever one the user picked.
    /// A no-op if `option` is already main.
    func selectRoute(_ option: RouteOption) async {
        guard !option.isMain, let alternativeRoute = option.alternativeRoute,
              let navigationRoutes else { return }
        if let updated = await navigationRoutes.selecting(alternativeRoute: alternativeRoute) {
            self.navigationRoutes = updated
        }
    }

    func clear() {
        navigationRoutes = nil
        requestError = nil
    }

    func updateRideTimeProfile(_ profile: RideTimeProfile) {
        rideTimeProfile = profile
    }

    /// Picks the alternative that best matches the active preference and promotes it to main.
    private func promotePreferredRoute() async {
        let options = routeOptions
        guard options.count > 1 else { return }
        guard let preferred = preferredOption(among: options), !preferred.isMain else { return }
        await selectRoute(preferred)
    }

    private func preferredOption(among options: [RouteOption]) -> RouteOption? {
        switch preference {
        case .fast:
            return options.min(by: { $0.expectedTravelTime < $1.expectedTravelTime })
        case .quiet:
            // Prefer the quietest ride, but don't send someone on a wild detour — ignore
            // options more than 40% slower than the fastest alternative.
            guard let fastest = options.map(\.expectedTravelTime).min() else { return nil }
            let candidates = options.filter { $0.expectedTravelTime <= fastest * 1.4 }
            let pool = candidates.isEmpty ? options : candidates
            return pool.min { lhs, rhs in
                if abs(lhs.stressProfile.score - rhs.stressProfile.score) > 0.02 {
                    return lhs.stressProfile.score < rhs.stressProfile.score
                }
                return lhs.expectedTravelTime < rhs.expectedTravelTime
            }
        }
    }
}
