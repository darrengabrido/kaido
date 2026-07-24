import Foundation
import CoreLocation
import MapboxNavigationCore

@Observable
@MainActor
final class NavigationViewModel {
    var isRequestingRoute = false
    var requestError: String?
    var navigationRoutes: NavigationRoutes?

    private let directionsService = DirectionsService()

    func startNavigation(waypointCoordinates: [CLLocationCoordinate2D]) async {
        isRequestingRoute = true
        requestError = nil
        defer { isRequestingRoute = false }
        do {
            navigationRoutes = try await directionsService.requestRoute(waypointCoordinates: waypointCoordinates)
        } catch {
            requestError = error.localizedDescription
        }
    }

    func clear() {
        navigationRoutes = nil
        requestError = nil
    }
}
