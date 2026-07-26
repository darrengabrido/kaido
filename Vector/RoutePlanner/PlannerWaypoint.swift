import Foundation
import CoreLocation

struct PlannerWaypoint: Identifiable, Equatable {
    let id = UUID()
    var coordinate: CLLocationCoordinate2D

    static func == (lhs: PlannerWaypoint, rhs: PlannerWaypoint) -> Bool {
        lhs.id == rhs.id
    }
}
