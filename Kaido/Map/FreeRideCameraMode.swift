import Foundation

/// How the map camera frames the rider while following the puck in Free Ride.
///
/// Mapbox already does the hard part (follow-puck with course bearing); each mode is just a
/// zoom and a pitch. Overhead is the classic top-down browse view and stays the default
/// everywhere outside Free Ride, so navigation and planning framing are untouched.
enum FreeRideCameraMode: String, CaseIterable, Identifiable, Sendable {
    /// Straight down, the same framing as browsing the map.
    case overhead
    /// Camera pulled back and up behind the rider, puck visible moving through the world.
    case thirdPerson
    /// Camera low and tilted hard down the road ahead, as if through the rider's eyes.
    case firstPerson

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overhead: "Overhead"
        case .thirdPerson: "Third person"
        case .firstPerson: "First person"
        }
    }

    var systemImage: String {
        switch self {
        case .overhead: "square.grid.2x2"
        case .thirdPerson: "figure.outdoor.cycle"
        case .firstPerson: "eye"
        }
    }

    /// Mapbox zoom level. Higher is closer to the ground.
    var zoom: CGFloat {
        switch self {
        case .overhead: 15.5
        case .thirdPerson: 16.5
        case .firstPerson: 17.5
        }
    }

    /// Camera tilt in degrees from straight down. Mapbox caps this at 85.
    var pitch: CGFloat {
        switch self {
        case .overhead: 0
        case .thirdPerson: 55
        case .firstPerson: 70
        }
    }
}

enum FreeRideCameraModeStore {
    private static let key = "kaido.freeRide.cameraMode"

    static var current: FreeRideCameraMode {
        get {
            UserDefaults.standard.string(forKey: key).flatMap(FreeRideCameraMode.init(rawValue:)) ?? .overhead
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}
