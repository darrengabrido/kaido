import Foundation
import CoreLocation
import MapboxDirections
import MapboxNavigationCore

struct DirectionsService {
    @MainActor
    func requestRoute(waypointCoordinates: [CLLocationCoordinate2D]) async throws -> NavigationRoutes {
        let waypoints = waypointCoordinates.map { MapboxDirections.Waypoint(coordinate: $0) }
        let options = NavigationRouteOptions(waypoints: waypoints, profileIdentifier: .cycling)
        return try await EbikeNavigationProvider.shared.routingProvider()
            .calculateRoutes(options: options)
            .value
    }
}
