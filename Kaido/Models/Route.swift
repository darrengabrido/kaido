import Foundation
import SwiftData

@Model
final class Route {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var distanceMeters: Double = 0
    var elevationGainMeters: Double = 0
    var isFavorite: Bool = false

    // Community routes — additive/optional so existing routes saved before this feature existed
    // are unaffected (nil for every route that has never been shared). Set when this route is
    // published to the community (see `ShareRouteToCommunitySheet`), cleared again if the rider
    // removes it. Never synced back from Supabase — this is purely "did *I* publish this from
    // *this* local route", not a live mirror of the community row's state.
    var sharedCommunityRouteId: UUID?

    @Relationship(deleteRule: .cascade, inverse: \Waypoint.route)
    var waypoints: [Waypoint]? = []

    @Relationship(deleteRule: .nullify, inverse: \Ride.route)
    var rides: [Ride]? = []

    init(
        name: String,
        distanceMeters: Double = 0,
        elevationGainMeters: Double = 0,
        isFavorite: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.distanceMeters = distanceMeters
        self.elevationGainMeters = elevationGainMeters
        self.isFavorite = isFavorite
    }

    var orderedWaypoints: [Waypoint] {
        (waypoints ?? []).sorted { $0.order < $1.order }
    }
}
