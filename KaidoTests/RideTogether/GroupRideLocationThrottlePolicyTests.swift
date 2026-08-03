@testable import Kaido
import XCTest
import CoreLocation

final class GroupRideLocationThrottlePolicyTests: XCTestCase {
    private let origin = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(
        latitude: Double? = nil,
        longitude: Double? = nil,
        course: Double? = 90,
        secondsAfterBase: TimeInterval
    ) -> GroupRideLocationSample {
        GroupRideLocationSample(
            coordinate: CLLocationCoordinate2D(latitude: latitude ?? origin.latitude, longitude: longitude ?? origin.longitude),
            horizontalAccuracyMeters: 5,
            courseDegrees: course,
            speedMetersPerSecond: 4,
            timestamp: baseDate.addingTimeInterval(secondsAfterBase)
        )
    }

    func testFirstSampleAlwaysPublishes() {
        let policy = GroupRideLocationThrottlePolicy()
        XCTAssertTrue(policy.shouldPublish(sample(secondsAfterBase: 0), now: baseDate))
    }

    func testWithinMinimumIntervalNeverPublishesEvenWithMovement() {
        var policy = GroupRideLocationThrottlePolicy()
        let first = sample(secondsAfterBase: 0)
        policy.recordPublished(first)

        // 1s later, ~50m away — well past the displacement threshold, but under the 2s floor.
        let candidate = sample(latitude: origin.latitude + 0.0005, secondsAfterBase: 1)
        XCTAssertFalse(policy.shouldPublish(candidate, now: baseDate.addingTimeInterval(1)))
    }

    func testMeaningfulDisplacementPublishesSoonerThanHeartbeat() {
        var policy = GroupRideLocationThrottlePolicy()
        policy.recordPublished(sample(secondsAfterBase: 0))

        // ~50m north after 3s (past the 2s floor, well under the 10s heartbeat).
        let candidate = sample(latitude: origin.latitude + 0.00045, secondsAfterBase: 3)
        XCTAssertTrue(policy.shouldPublish(candidate, now: baseDate.addingTimeInterval(3)))
    }

    func testMeaningfulHeadingChangePublishesSoonerThanHeartbeat() {
        var policy = GroupRideLocationThrottlePolicy()
        policy.recordPublished(sample(course: 0, secondsAfterBase: 0))

        let candidate = sample(course: 40, secondsAfterBase: 3)
        XCTAssertTrue(policy.shouldPublish(candidate, now: baseDate.addingTimeInterval(3)))
    }

    func testNoMovementOrHeadingChangeWaitsForHeartbeat() {
        var policy = GroupRideLocationThrottlePolicy()
        policy.recordPublished(sample(course: 90, secondsAfterBase: 0))

        let stillStationary = sample(course: 91, secondsAfterBase: 5)
        XCTAssertFalse(policy.shouldPublish(stillStationary, now: baseDate.addingTimeInterval(5)))

        let heartbeat = sample(course: 91, secondsAfterBase: 10)
        XCTAssertTrue(policy.shouldPublish(heartbeat, now: baseDate.addingTimeInterval(10)))
    }

    func testHeadingDeltaWrapsAroundZeroDegrees() {
        XCTAssertEqual(GroupRideLocationThrottlePolicy.headingDelta(from: 350, to: 10), 20, accuracy: 0.001)
        XCTAssertEqual(GroupRideLocationThrottlePolicy.headingDelta(from: 10, to: 350), 20, accuracy: 0.001)
        XCTAssertEqual(GroupRideLocationThrottlePolicy.headingDelta(from: 0, to: 180), 180, accuracy: 0.001)
    }
}
