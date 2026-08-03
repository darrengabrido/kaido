@testable import Kaido
import XCTest

final class GroupRideMessageValidatorTests: XCTestCase {
    func testValidBodyPasses() {
        XCTAssertNoThrow(try GroupRideMessageValidator.validate(body: "Slow down"))
    }

    func testEmptyBodyIsRejected() {
        XCTAssertThrowsError(try GroupRideMessageValidator.validate(body: "")) { error in
            XCTAssertEqual(error as? GroupRideMessageValidationError, .empty)
        }
    }

    func testBodyAtLimitPasses() {
        let body = String(repeating: "a", count: GroupRideConfig.maxMessageBodyLength)
        XCTAssertNoThrow(try GroupRideMessageValidator.validate(body: body))
    }

    func testBodyOverLimitIsRejected() {
        let body = String(repeating: "a", count: GroupRideConfig.maxMessageBodyLength + 1)
        XCTAssertThrowsError(try GroupRideMessageValidator.validate(body: body)) { error in
            XCTAssertEqual(error as? GroupRideMessageValidationError, .tooLong(limit: GroupRideConfig.maxMessageBodyLength))
        }
    }
}
