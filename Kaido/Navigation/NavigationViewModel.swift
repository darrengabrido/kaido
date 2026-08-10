import Foundation
import CoreLocation
import MapboxDirections
import MapboxNavigationCore

/// Rider-facing turn preview for the place card — keeps Mapbox `RouteStep` / `Route` types out of
/// SwiftUI map views that also import the SwiftData `Route` model.
struct PreviewRouteStep: Identifiable, Sendable {
    let id: Int
    let instructions: String
    let distanceMeters: Double
    let maneuverSymbolName: String
}

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
    /// Async Terrain enrichment keyed by `RouteOption.id`. Missing means hills aren't ready yet.
    var elevationByRouteId: [String: ElevationProfile] = [:]
    var preference: RoutingPreference = RoutingPreferenceStore.current {
        didSet {
            RoutingPreferenceStore.current = preference
            guard oldValue != preference else { return }
            // Re-rank in place — no network round-trip, so toggling never blanks routes.
            Task { await promotePreferredRoute() }
        }
    }

    private let directionsService = DirectionsService()
    private let elevationService = ElevationService()
    private var elevationTask: Task<Void, Never>?
    private var elevationGeneration = 0

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

    /// Turn-by-turn list for the currently selected (main) route, used when the place card expands.
    var mainRoutePreviewSteps: [PreviewRouteStep] {
        guard let route = navigationRoutes?.mainRoute.route else { return [] }
        return route.legs
            .flatMap(\.steps)
            .enumerated()
            .compactMap { index, step in
                let instructions = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !instructions.isEmpty else { return nil }
                return PreviewRouteStep(
                    id: index,
                    instructions: instructions,
                    distanceMeters: step.distance,
                    maneuverSymbolName: NavigationBannerModel.maneuverSymbol(
                        type: step.maneuverType,
                        direction: step.maneuverDirection
                    )
                )
            }
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
            startElevationEnrichment()
        } catch {
            cancelElevationEnrichment()
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
            // Route IDs are stable across promote; cached hills stay valid.
        }
    }

    func clear() {
        cancelElevationEnrichment()
        navigationRoutes = nil
        requestError = nil
    }

    func updateRideTimeProfile(_ profile: RideTimeProfile) {
        rideTimeProfile = profile
    }

    private func cancelElevationEnrichment() {
        elevationGeneration += 1
        elevationTask?.cancel()
        elevationTask = nil
        elevationByRouteId = [:]
    }

    /// Non-blocking Terrain pass. Main route first so the summary strip updates sooner.
    private func startElevationEnrichment() {
        let options = routeOptions
        let liveIDs = Set(options.map(\.id))
        elevationByRouteId = elevationByRouteId.filter { liveIDs.contains($0.key) }

        elevationGeneration += 1
        let generation = elevationGeneration
        elevationTask?.cancel()

        let ordered = options.sorted { lhs, rhs in
            if lhs.isMain != rhs.isMain { return lhs.isMain && !rhs.isMain }
            return lhs.id < rhs.id
        }

        elevationTask = Task { [elevationService] in
            for option in ordered {
                guard !Task.isCancelled, generation == elevationGeneration else { return }
                if elevationByRouteId[option.id] != nil { continue }

                let samples = PolylineSampler.coordinates(along: option.coordinates)
                let heights = await elevationService.elevations(along: samples)
                guard !Task.isCancelled, generation == elevationGeneration else { return }
                guard let profile = ElevationMath.profile(from: heights) else { continue }

                elevationByRouteId[option.id] = profile
            }
        }
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
