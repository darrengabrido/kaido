import CoreLocation
import Foundation

/// One location sample under consideration for publishing. Distinct from `CLLocation` so the
/// throttle decision is a pure, testable function with no CoreLocation runtime dependency.
struct GroupRideLocationSample: Sendable, Equatable {
    var coordinate: CLLocationCoordinate2D
    var horizontalAccuracyMeters: Double
    var courseDegrees: Double?
    var speedMetersPerSecond: Double?
    var timestamp: Date

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.horizontalAccuracyMeters == rhs.horizontalAccuracyMeters
            && lhs.courseDegrees == rhs.courseDegrees
            && lhs.speedMetersPerSecond == rhs.speedMetersPerSecond
            && lhs.timestamp == rhs.timestamp
    }
}

/// Decides whether a new location sample justifies a fresh broadcast, per
/// `GroupRideConfig.Location`: never more often than the minimum interval, sooner after
/// meaningful displacement/heading change, and always at the stationary heartbeat interval.
/// Pure value type — no timers, no CoreLocation callbacks — so it's directly unit testable.
struct GroupRideLocationThrottlePolicy: Sendable {
    private(set) var lastPublished: GroupRideLocationSample?

    init(lastPublished: GroupRideLocationSample? = nil) {
        self.lastPublished = lastPublished
    }

    func shouldPublish(_ candidate: GroupRideLocationSample, now: Date) -> Bool {
        guard let lastPublished else { return true }

        let elapsed = now.timeIntervalSince(lastPublished.timestamp)
        if elapsed >= GroupRideConfig.Location.stationaryHeartbeatInterval {
            return true
        }
        guard elapsed >= GroupRideConfig.Location.minimumPublishInterval else {
            return false
        }

        let displacement = candidate.coordinate.kaidoDistance(to: lastPublished.coordinate)
        if displacement >= GroupRideConfig.Location.meaningfulDisplacementMeters {
            return true
        }

        if let newCourse = candidate.courseDegrees, let oldCourse = lastPublished.courseDegrees,
           Self.headingDelta(from: oldCourse, to: newCourse) >= GroupRideConfig.Location.meaningfulHeadingChangeDegrees {
            return true
        }

        return false
    }

    mutating func recordPublished(_ sample: GroupRideLocationSample) {
        lastPublished = sample
    }

    static func headingDelta(from a: Double, to b: Double) -> Double {
        let normalizedA = a.truncatingRemainder(dividingBy: 360)
        let normalizedB = b.truncatingRemainder(dividingBy: 360)
        let diff = abs(normalizedA - normalizedB)
        return min(diff, 360 - diff)
    }
}

extension CLLocationCoordinate2D {
    func kaidoDistance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}
