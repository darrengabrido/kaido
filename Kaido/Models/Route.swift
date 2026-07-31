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
