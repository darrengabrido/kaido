import Foundation
import SwiftData
import CoreLocation

struct TrackedCoordinate: Codable {
    var latitude: Double
    var longitude: Double
    var timestamp: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

@Model
final class Ride {
    var id: UUID = UUID()
    var route: Route?
    var startedAt: Date = Date()
    var endedAt: Date?
    var distanceMeters: Double = 0
    var avgSpeedMetersPerSecond: Double = 0
    var maxSpeedMetersPerSecond: Double = 0

    @Attribute(.externalStorage)
    var recordedPathData: Data?

    // Ride Together — additive/optional so existing solo-ride CloudKit records are unaffected
    // (nil/false for every ride recorded before this feature existed, and for every solo ride
    // going forward). Never stores other riders' locations — only this rider's own summary.
    var groupRideId: UUID?
    var groupRideParticipantCount: Int?
    var wasGroupRideHost: Bool = false

    init(route: Route? = nil) {
        self.id = UUID()
        self.route = route
        self.startedAt = Date()
        self.distanceMeters = 0
        self.avgSpeedMetersPerSecond = 0
        self.maxSpeedMetersPerSecond = 0
    }

    var recordedPath: [TrackedCoordinate] {
        get {
            guard let recordedPathData else { return [] }
            return (try? JSONDecoder().decode([TrackedCoordinate].self, from: recordedPathData)) ?? []
        }
        set {
            recordedPathData = try? JSONEncoder().encode(newValue)
        }
    }
}
