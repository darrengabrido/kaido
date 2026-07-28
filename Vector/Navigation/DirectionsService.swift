import Foundation
import CoreLocation
import MapboxDirections
import MapboxNavigationCore

struct DirectionsService {
    @MainActor
    func requestRoute(
        waypointCoordinates: [CLLocationCoordinate2D],
        preference: RoutingPreference
    ) async throws -> NavigationRoutes {
        let waypoints = waypointCoordinates.map { MapboxDirections.Waypoint(coordinate: $0) }
        let options = NavigationRouteOptions(waypoints: waypoints, profileIdentifier: .cycling)
        // Calm prefers continuous land routes — ferries are the one cycling-supported exclude
        // Mapbox documents for this profile. Fast leaves the graph unconstrained so the
        // engine can pick the quickest bike-legal path.
        switch preference {
        case .calm:
            options.roadClassesToAvoid = [.ferry]
        case .fast:
            options.roadClassesToAvoid = []
        }
        return try await VectorNavigationProvider.shared.routingProvider()
            .calculateRoutes(options: options)
            .value
    }
}
