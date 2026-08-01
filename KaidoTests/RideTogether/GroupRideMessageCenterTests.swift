@testable import Kaido
import XCTest

@MainActor
final class GroupRideMessageCenterTests: XCTestCase {
    private let rideId = UUID()

    private func message(id: UUID = UUID(), sender: UUID = UUID(), body: String = "All good") -> GroupRideMessage {
        GroupRideMessage(
            id: id,
            rideId: rideId,
            senderUserId: sender,
            senderDisplayName: "Rider",
            kind: .preset,
            body: body,
            presetKey: "all_good",
            clientMessageId: UUID(),
            createdAt: Date()
        )
    }

    func testIngestingANewMessageAddsItToHistory() {
        let center = GroupRideMessageCenter()
        let msg = message()
        XCTAssertTrue(center.ingest(msg, isIncoming: true))
        XCTAssertEqual(center.recentMessages, [msg])
    }

    func testDuplicateDeliveryByIdIsDropped() {
        let center = GroupRideMessageCenter()
        let msg = message()
        XCTAssertTrue(center.ingest(msg, isIncoming: true))
        XCTAssertFalse(center.ingest(msg, isIncoming: true))
        XCTAssertEqual(center.recentMessages.count, 1)
    }

    func testLoadHistoryResetsDedupTracking() {
        let center = GroupRideMessageCenter()
        let msg = message()
        center.loadHistory([msg])
        XCTAssertEqual(center.recentMessages, [msg])
        // Same ID delivered again after a reconnect refetch should still dedup correctly.
        XCTAssertFalse(center.ingest(msg, isIncoming: true))
    }

    func testOnlyIncomingMessagesEnterTheBannerQueue() {
        let center = GroupRideMessageCenter()
        _ = center.ingest(message(), isIncoming: false)
        XCTAssertNil(center.currentBanner)

        let incoming = message()
        _ = center.ingest(incoming, isIncoming: true)
        XCTAssertEqual(center.currentBanner, incoming)
    }

    func testBannersQueueRatherThanOverlap() {
        let center = GroupRideMessageCenter()
        let first = message(body: "First")
        let second = message(body: "Second")

        _ = center.ingest(first, isIncoming: true)
        _ = center.ingest(second, isIncoming: true)

        XCTAssertEqual(center.currentBanner, first)
        XCTAssertEqual(center.bannerQueue, [second])

        center.dismissCurrentBanner()
        XCTAssertEqual(center.currentBanner, second)
        XCTAssertTrue(center.bannerQueue.isEmpty)
    }

    func testResetClearsHistoryAndBanners() {
        let center = GroupRideMessageCenter()
        _ = center.ingest(message(), isIncoming: true)
        center.reset()
        XCTAssertTrue(center.recentMessages.isEmpty)
        XCTAssertNil(center.currentBanner)
    }
}
