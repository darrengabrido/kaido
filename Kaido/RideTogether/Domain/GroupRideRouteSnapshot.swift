import Foundation
import CoreLocation

/// A versioned, app-owned snapshot of the shared route — never an opaque Mapbox SDK object.
/// The host captures one of these when creating (or updating, pre-start) a group ride; every
/// member decodes it locally to preview or reconstruct the route with their own Mapbox
/// `DirectionsService` call. Once the ride goes `.active` the snapshot is locked (see
/// `GroupRideStateMachine`) — each device's own navigation session then owns map matching and
/// local rerouting from that point on.
struct GroupRideRouteSnapshot: Codable, Sendable, Equatable {
    static let currentSchemaVersion = 1

    struct Waypoint: Codable, Sendable, Equatable {
        var latitude: Double
        var longitude: Double
        var order: Int

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    var schemaVersion: Int
    var destinationName: String
    var destinationLatitude: Double
    var destinationLongitude: Double
    /// Ordered waypoints including the origin used when the host captured the route.
    var waypoints: [Waypoint]
    /// Mapbox routing profile identifier string (e.g. "cycling"), not a live SDK enum.
    var routingProfile: String
    /// Index into the alternatives the host had requested; `nil` means the primary route.
    var selectedAlternativeIndex: Int?
    /// Encoded polyline (precision 1e5) of the selected route's geometry, when Mapbox returned
    /// shape data for it. Optional because a route can be previewed before geometry resolves.
    var encodedPolyline: String?
    var distanceMeters: Double
    var expectedDurationSeconds: Double
    var capturedAt: Date

    var destinationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: destinationLatitude, longitude: destinationLongitude)
    }

    var orderedWaypoints: [Waypoint] {
        waypoints.sorted { $0.order < $1.order }
    }

    /// Decoded geometry for map preview, or `nil` when no polyline was captured — callers should
    /// fall back to drawing a straight line through `orderedWaypoints` in that case.
    var decodedGeometry: [CLLocationCoordinate2D]? {
        guard let encodedPolyline, !encodedPolyline.isEmpty else { return nil }
        let coordinates = GroupRidePolylineCodec.decode(encodedPolyline)
        return coordinates.isEmpty ? nil : coordinates
    }
}
