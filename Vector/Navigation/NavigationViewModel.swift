import Foundation
import CoreLocation
import MapboxNavigationCore

struct RouteOption: Identifiable {
    let id: String
    let distanceMeters: Double
    let expectedTravelTime: TimeInterval
    let coordinates: [CLLocationCoordinate2D]
    let isMain: Bool
    fileprivate let alternativeRoute: AlternativeRoute?
}

@Observable
@MainActor
final class NavigationViewModel {
    var isRequestingRoute = false
    var requestError: String?
    var navigationRoutes: NavigationRoutes?

    private let directionsService = DirectionsService()

    var routeOptions: [RouteOption] {
        guard let navigationRoutes else { return [] }
        let main = navigationRoutes.mainRoute
        var options = [
            RouteOption(
                id: main.routeId.description,
                distanceMeters: main.route.distance,
                expectedTravelTime: main.route.expectedTravelTime,
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
            navigationRoutes = try await directionsService.requestRoute(waypointCoordinates: waypointCoordinates)
        } catch {
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
}
