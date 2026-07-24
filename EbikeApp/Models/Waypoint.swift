import Foundation
import SwiftData

@Model
final class Waypoint {
    var latitude: Double = 0
    var longitude: Double = 0
    var order: Int = 0
    var isSnappedToRoad: Bool = false
    var route: Route?

    init(latitude: Double, longitude: Double, order: Int, isSnappedToRoad: Bool = false) {
        self.latitude = latitude
        self.longitude = longitude
        self.order = order
        self.isSnappedToRoad = isSnappedToRoad
    }
}
