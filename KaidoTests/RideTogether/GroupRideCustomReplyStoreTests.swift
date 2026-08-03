@testable import Kaido
import XCTest

final class GroupRideCustomReplyStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        GroupRideCustomReplyStore.replies = []
    }

    override func tearDown() {
        GroupRideCustomReplyStore.replies = []
        super.tearDown()
    }

    func testAddingAValidReplyPersists() throws {
        let result = try GroupRideCustomReplyStore.add("Stopping for water")
        XCTAssertEqual(result, ["Stopping for water"])
        XCTAssertEqual(GroupRideCustomReplyStore.replies, ["Stopping for water"])
    }

    func testEmptyReplyIsRejected() {
        XCTAssertThrowsError(try GroupRideCustomReplyStore.add("   ")) { error in
            XCTAssertEqual(error as? GroupRideCustomReplyError, .empty)
        }
    }

    func testReplyOverLengthLimitIsRejected() {
        let tooLong = String(repeating: "x", count: GroupRideConfig.maxCustomQuickReplyLength + 1)
        XCTAssertThrowsError(try GroupRideCustomReplyStore.add(tooLong)) { error in
            XCTAssertEqual(error as? GroupRideCustomReplyError, .tooLong(limit: GroupRideConfig.maxCustomQuickReplyLength))
        }
    }

    func testCannotExceedMaximumCustomReplyCount() throws {
        for index in 0..<GroupRideConfig.maxCustomQuickReplies {
            _ = try GroupRideCustomReplyStore.add("Reply \(index)")
        }
        XCTAssertThrowsError(try GroupRideCustomReplyStore.add("One too many")) { error in
            XCTAssertEqual(error as? GroupRideCustomReplyError, .tooMany(limit: GroupRideConfig.maxCustomQuickReplies))
        }
    }

    func testRemoveAtIndex() throws {
        _ = try GroupRideCustomReplyStore.add("Keep")
        _ = try GroupRideCustomReplyStore.add("Remove me")
        GroupRideCustomReplyStore.remove(at: 1)
        XCTAssertEqual(GroupRideCustomReplyStore.replies, ["Keep"])
    }
}
