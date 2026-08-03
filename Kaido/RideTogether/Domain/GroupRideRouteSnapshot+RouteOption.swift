import CoreLocation
import Foundation

/// Bridges the app's existing route-preview types (`RouteOption`, built from a live
/// `NavigationRoutes` in `NavigationViewModel`) into the app-owned, storable snapshot. Keeping
/// this in its own file lets `GroupRideRouteSnapshot` itself stay free of any dependency on the
/// navigation stack while still only ever touching plain value types here (no Mapbox SDK object
/// is captured or archived).
extension GroupRideRouteSnapshot {
    init(
        destinationName: String,
        waypointCoordinates: [CLLocationCoordinate2D],
        selecting option: RouteOption,
        among allOptions: [RouteOption],
        routingProfile: String = "cycling"
    ) {
        let alternativeIndex: Int?
        if option.isMain {
            alternativeIndex = nil
        } else {
            alternativeIndex = allOptions.filter { !$0.isMain }.firstIndex { $0.id == option.id }
        }

        let destinationCoordinate = waypointCoordinates.last ?? option.coordinates.last
            ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)

        self.init(
            schemaVersion: Self.currentSchemaVersion,
            destinationName: destinationName,
            destinationLatitude: destinationCoordinate.latitude,
            destinationLongitude: destinationCoordinate.longitude,
            waypoints: waypointCoordinates.enumerated().map { index, coordinate in
                Waypoint(latitude: coordinate.latitude, longitude: coordinate.longitude, order: index)
            },
            routingProfile: routingProfile,
            selectedAlternativeIndex: alternativeIndex,
            encodedPolyline: option.coordinates.count > 1
                ? GroupRidePolylineCodec.encode(option.coordinates)
                : nil,
            distanceMeters: option.distanceMeters,
            expectedDurationSeconds: option.expectedTravelTime,
            capturedAt: Date()
        )
    }
}
