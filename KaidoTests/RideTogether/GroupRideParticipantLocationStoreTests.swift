@testable import Kaido
import XCTest
import CoreLocation

@MainActor
final class GroupRideParticipantLocationStoreTests: XCTestCase {
    private let rideId = UUID()
    private let memberId = UUID()
    private let clock = ManualClock(Date(timeIntervalSince1970: 1_700_000_000))

    private func envelope(
        latitude: Double = 37.7749,
        longitude: Double = -122.4194,
        accuracy: Double = 5,
        sequence: UInt64,
        sentSecondsAgo: TimeInterval = 0
    ) -> GroupRideLocationEnvelope {
        GroupRideLocationEnvelope(
            schemaVersion: GroupRideLocationEnvelope.currentSchemaVersion,
            rideId: rideId,
            memberId: memberId,
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracyMeters: accuracy,
            courseDegrees: 90,
            speedMetersPerSecond: 3,
            sentAt: clock.now().addingTimeInterval(-sentSecondsAgo),
            sequence: sequence
        )
    }

    func testValidEnvelopeIsApplied() {
        let store = GroupRideParticipantLocationStore(clock: clock)
        XCTAssertTrue(store.apply(envelope(sequence: 1), receivedAt: clock.now()))
        XCTAssertEqual(store.locationsByMemberId[memberId]?.sequence, 1)
    }

    func testOutOfOrderSequenceIsRejectedAndNeverMovesTheRiderBackward() {
        let store = GroupRideParticipantLocationStore(clock: clock)
        _ = store.apply(envelope(latitude: 37.80, sequence: 5), receivedAt: clock.now())

        let stale = envelope(latitude: 37.70, sequence: 3)
        XCTAssertFalse(store.apply(stale, receivedAt: clock.now()))
        XCTAssertEqual(store.locationsByMemberId[memberId]?.coordinate.latitude, 37.80)
    }

    func testDuplicateSequenceIsRejected() {
        let store = GroupRideParticipantLocationStore(clock: clock)
        _ = store.apply(envelope(sequence: 2), receivedAt: clock.now())
        XCTAssertFalse(store.apply(envelope(sequence: 2), receivedAt: clock.now()))
    }

    func testImplausibleCoordinateIsRejected() {
        let store = GroupRideParticipantLocationStore(clock: clock)
        XCTAssertFalse(store.apply(envelope(latitude: 0, longitude: 0, sequence: 1), receivedAt: clock.now()))
        XCTAssertFalse(store.apply(envelope(latitude: 200, sequence: 1), receivedAt: clock.now()))
    }

    func testInaccurateLocationIsRejected() {
        let store = GroupRideParticipantLocationStore(clock: clock)
        XCTAssertFalse(store.apply(envelope(accuracy: 500, sequence: 1), receivedAt: clock.now()))
    }

    func testTooOldPacketIsRejected() {
        let store = GroupRideParticipantLocationStore(clock: clock)
        XCTAssertFalse(store.apply(envelope(sequence: 1, sentSecondsAgo: 120), receivedAt: clock.now()))
    }

    func testFreshnessBucketsMatchConfiguredWindows() {
        let store = GroupRideParticipantLocationStore(clock: clock)
        _ = store.apply(envelope(sequence: 1), receivedAt: clock.now())

        XCTAssertEqual(store.freshness(for: memberId, now: clock.now()), .fresh)

        clock.advance(by: GroupRideConfig.Location.freshWindow + 1)
        XCTAssertEqual(store.freshness(for: memberId, now: clock.now()), .stale)

        clock.advance(by: GroupRideConfig.Location.removalWindow)
        XCTAssertEqual(store.freshness(for: memberId, now: clock.now()), .expired)
    }

    func testExpiredLocationsAreExcludedFromVisibleLocationsButRetainedInMemory() {
        let store = GroupRideParticipantLocationStore(clock: clock)
        _ = store.apply(envelope(sequence: 1), receivedAt: clock.now())
        XCTAssertEqual(store.visibleLocations(now: clock.now()).count, 1)

        let farFuture = clock.now().addingTimeInterval(GroupRideConfig.Location.removalWindow + 5)
        XCTAssertTrue(store.visibleLocations(now: farFuture).isEmpty)
        // Still retained for "last seen" purposes rather than deleted outright.
        XCTAssertNotNil(store.locationsByMemberId[memberId])
    }
}
