import Foundation
import MapboxDirections

/// Estimates how stressful a cycling route is from Mapbox step metadata.
///
/// Lower scores are quieter. Dedicated cycle infrastructure and quiet streets
/// score low; primary arterials, trunks, and motorways score high. Distance-weighted
/// so a short dash on a busy road doesn't dominate a mostly-quiet ride.
enum RouteStressScorer {
    /// Distance share in each stress band, plus the mean score used for ranking.
    struct Profile: Sendable {
        /// Distance-weighted mean stress in `0...1`. Lower is quieter.
        let score: Double
        /// Fraction of route distance classified quiet / mixed / busy. Sum ≈ 1.
        let quietFraction: Double
        let mixedFraction: Double
        let busyFraction: Double

        var summary: String {
            let quietPct = Int((quietFraction * 100).rounded())
            let mixedPct = Int((mixedFraction * 100).rounded())
            let busyPct = Int((busyFraction * 100).rounded())
            return "\(quietPct)% quiet · \(mixedPct)% mixed · \(busyPct)% busy"
        }

        var headline: String {
            switch score {
            case ..<0.35: "Mostly bike paths & quiet streets"
            case ..<0.55: "Mix of quiet streets and busier roads"
            default: "More time on busier roads"
            }
        }
    }

    static func profile(for route: MapboxDirections.Route) -> Profile {
        var weighted = 0.0
        var quietDistance = 0.0
        var mixedDistance = 0.0
        var busyDistance = 0.0
        var totalDistance = 0.0

        for leg in route.legs {
            for step in leg.steps {
                let distance = step.distance
                guard distance > 0 else { continue }
                let stepStress = stress(for: step)
                weighted += stepStress * distance
                totalDistance += distance

                switch stepStress {
                case ..<0.35: quietDistance += distance
                case ..<0.55: mixedDistance += distance
                default: busyDistance += distance
                }
            }
        }

        guard totalDistance > 0 else {
            return Profile(score: 0, quietFraction: 1, mixedFraction: 0, busyFraction: 0)
        }

        return Profile(
            score: min(1, max(0, weighted / totalDistance)),
            quietFraction: quietDistance / totalDistance,
            mixedFraction: mixedDistance / totalDistance,
            busyFraction: busyDistance / totalDistance
        )
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
