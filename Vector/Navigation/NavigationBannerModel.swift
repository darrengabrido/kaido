import CoreLocation
import Foundation
// ManeuverType/ManeuverDirection aren't re-exported by MapboxNavigationCore. Safe to import
// directly here because this file never names `Route` or `Waypoint`, which collide with the
// SwiftData models of the same name.
import MapboxDirections
import MapboxNavigationCore

/// Shared state behind the custom glass navigation banners. Mapbox pushes updates in through the
/// `NavigationComponent` callbacks on the banner controllers; both banners read from here.
@Observable
final class NavigationBannerModel {
    var instruction: VisualInstructionBanner?
    var distanceToManeuver: CLLocationDistance = 0
    var durationRemaining: TimeInterval = 0
    var distanceRemaining: CLLocationDistance = 0
    var fractionTraveled: Double = 0
    var remainingSteps: [RouteStep] = []

    var arrivalDate: Date {
        Date().addingTimeInterval(durationRemaining)
    }

    func update(with progress: RouteProgress) {
        distanceToManeuver = progress.currentLegProgress.currentStepProgress.distanceRemaining
        durationRemaining = progress.durationRemaining
        distanceRemaining = progress.distanceRemaining
        fractionTraveled = progress.fractionTraveled
        remainingSteps = progress.remainingSteps
    }

    // MARK: - Formatting

    static func distanceText(_ meters: CLLocationDistance) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: max(seconds, 60)) ?? ""
    }

    /// SF Symbol standing in for Mapbox's own `ManeuverView`, which is UIKit-only and can't be
    /// dropped into a SwiftUI banner.
    static func maneuverSymbol(
        type: ManeuverType?,
        direction: ManeuverDirection?
    ) -> String {
        switch type {
        case .depart: return "location.north.line.fill"
        case .arrive: return "flag.checkered"
        case .merge: return "arrow.triangle.merge"
        case .takeOnRamp: return "arrow.up.right"
        case .takeOffRamp: return "arrow.down.right"
        case .reachFork: return "arrow.triangle.branch"
        case .takeRoundabout, .takeRotary, .turnAtRoundabout, .exitRoundabout, .exitRotary:
            return "arrow.triangle.turn.up.right.circle"
        default:
            break
        }

        switch direction {
        case .left: return "arrow.turn.up.left"
        case .right: return "arrow.turn.up.right"
        case .slightLeft: return "arrow.up.left"
        case .slightRight: return "arrow.up.right"
        case .sharpLeft: return "arrow.turn.left.down"
        case .sharpRight: return "arrow.turn.right.down"
        case .uTurn: return "arrow.uturn.down"
        default: return "arrow.up"
        }
    }
}
