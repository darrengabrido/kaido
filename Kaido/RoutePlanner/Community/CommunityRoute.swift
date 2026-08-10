import Foundation
import CoreLocation

/// A route shown in the Routes tab's "Community" section. Distinct from the local, SwiftData-backed
/// `Route` — this is a plain value type so it can come from a bundled catalog today
/// (`CuratedCommunityRoutes`) and a backend later without any model changes. "Add to My Routes"
/// (see `CommunityRouteDetailView`) is what bridges one of these into a local `Route`/`Waypoint`
/// pair, at which point it behaves exactly like any other saved route.
struct CommunityRoute: Identifiable, Codable, Sendable, Hashable {
    struct Waypoint: Codable, Sendable, Hashable {
        var latitude: Double
        var longitude: Double
        var order: Int

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    let id: UUID
    var name: String
    var description: String?
    /// Free-text location context (e.g. "San Francisco, CA") — there's no map-based "near me"
    /// filter yet, so this is how a rider tells at a glance whether a route is even ridable for them.
    var areaName: String?
    /// Who put this route together. Always "Kaido" for the bundled catalog today; kept as a field
    /// (rather than hardcoded in the UI) so a future admin- or user-curated source can vary it.
    var curatorName: String
    var distanceMeters: Double
    var elevationGainMeters: Double
    var waypoints: [Waypoint]

    var orderedWaypoints: [Waypoint] {
        waypoints.sorted { $0.order < $1.order }
    }

    var coordinates: [CLLocationCoordinate2D] {
        orderedWaypoints.map(\.coordinate)
    }
}
