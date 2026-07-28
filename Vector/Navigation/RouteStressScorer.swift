import Foundation
import MapboxDirections

/// Estimates how stressful a cycling route is from Mapbox step metadata.
///
/// Lower scores are calmer. Dedicated cycle infrastructure and quiet streets
/// score low; primary arterials, trunks, and motorways score high. Distance-weighted
/// so a short dash on a busy road doesn't dominate a mostly-calm ride.
enum RouteStressScorer {
    /// Distance-weighted mean stress in `0...1`.
    static func score(for route: MapboxDirections.Route) -> Double {
        var weighted = 0.0
        var totalDistance = 0.0

        for leg in route.legs {
            for step in leg.steps {
                let distance = step.distance
                guard distance > 0 else { continue }
                weighted += stress(for: step) * distance
                totalDistance += distance
            }
        }

        guard totalDistance > 0 else { return 0 }
        return min(1, max(0, weighted / totalDistance))
    }

    private static func stress(for step: RouteStep) -> Double {
        var values: [Double] = [stress(for: step.transportType)]

        if let intersections = step.intersections {
            for intersection in intersections {
                if let roadClass = intersection.outletMapboxStreetsRoadClass {
                    values.append(stress(for: roadClass))
                }
                if let classes = intersection.outletRoadClasses {
                    if classes.contains(.motorway) { values.append(1.0) }
                    if classes.contains(.ferry) { values.append(0.95) }
                    if classes.contains(.unpaved) { values.append(0.55) }
                }
            }
        }

        return values.reduce(0, +) / Double(values.count)
    }

    private static func stress(for transportType: TransportType) -> Double {
        switch transportType {
        case .cycling: 0.12
        case .walking: 0.22
        case .ferry: 0.95
        case .train: 0.7
        case .automobile, .movableBridge: 0.85
        case .inaccessible: 1.0
        }
    }

    private static func stress(for roadClass: MapboxStreetsRoadClass) -> Double {
        switch roadClass {
        case .path, .pedestrian, .streetLimited:
            0.08
        case .street, .service, .track, .golf:
            0.28
        case .tertiary, .tertiaryLink:
            0.48
        case .secondary, .secondaryLink:
            0.68
        case .primary, .primaryLink:
            0.82
        case .trunk, .trunkLink, .motorway, .motorwayLink:
            1.0
        case .ferry:
            0.95
        case .construction:
            0.75
        case .aerialway, .majorRail, .minorRail, .serviceRail:
            0.9
        case .undefined:
            0.5
        }
    }
}
