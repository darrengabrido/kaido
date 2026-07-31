import Foundation
import CoreLocation
import MapboxDirections
import MapboxNavigationCore

struct DirectionsService {
    @MainActor
    func requestRoute(waypointCoordinates: [CLLocationCoordinate2D]) async throws -> NavigationRoutes {
        let waypoints = waypointCoordinates.map { MapboxDirections.Waypoint(coordinate: $0) }
        // Always use Mapbox's cycling profile (already prefers bike infrastructure). Quiet vs Fast
        // is applied after the response by ranking alternatives — mutating `exclude` here is a
        // fragile lever and is not needed for the preference UX.
        let options = NavigationRouteOptions(waypoints: waypoints, profileIdentifier: .cycling)
        return try await KaidoNavigationProvider.shared.routingProvider()
            .calculateRoutes(options: options)
            .value
    }
}
