import Foundation
import CoreLocation

/// Lifecycle state of a community route. Backed by the `community_routes.status` column.
/// Nothing sets `.removed` today — `remove(routeId:)` on `CommunityRouteService` hard-deletes the
/// row — but the case exists so a future moderation pass has somewhere to land without a schema
/// change.
enum CommunityRouteStatus: String, Codable, Sendable, Hashable {
    case published
    case removed
}

/// A route shown in the Routes tab's "Community" section, mirroring the `community_routes` table
/// exactly (see `supabase/migrations/0002_community_routes.sql`). Distinct from the local,
/// SwiftData-backed `Route` — this is a plain value type so it round-trips through
/// `SupabaseCommunityRouteService` (and, for the bundled seed catalog, `CuratedCommunityRoutes`)
/// without any persistence-framework dependency. "Add to My Routes" (see
/// `CommunityRouteDetailView`) is what bridges one of these into a local `Route`/`Waypoint` pair,
/// at which point it behaves exactly like any other saved route.
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
    let authorUserId: UUID
    var authorDisplayName: String
    var name: String
    var description: String?
    var distanceMeters: Double
    var elevationGainMeters: Double
    var waypoints: [Waypoint]
    var startLatitude: Double
    var startLongitude: Double
    var status: CommunityRouteStatus
    let createdAt: Date
    var updatedAt: Date

    var orderedWaypoints: [Waypoint] {
        waypoints.sorted { $0.order < $1.order }
    }

    var coordinates: [CLLocationCoordinate2D] {
        orderedWaypoints.map(\.coordinate)
    }
}
