@testable import Kaido
import XCTest

final class GroupRideInviteLinkBuilderTests: XCTestCase {
    func testRedactionRemovesTokenButKeepsRestOfLink() {
        let rideId = UUID()
        let url = GroupRideInviteLinkBuilder.makeLink(rideId: rideId, token: "super-secret-token")

        let redacted = GroupRideInviteLinkBuilder.redacted(url)

        XCTAssertFalse(redacted.contains("super-secret-token"))
        XCTAssertTrue(redacted.contains("«redacted»"))
        XCTAssertTrue(redacted.contains(rideId.uuidString))
        XCTAssertTrue(redacted.contains("ride-together"))
    }

    func testRedactionIsIdempotentForURLsWithoutAToken() {
        let url = URL(string: "kaido://ride-together/join?ride=\(UUID().uuidString)")!
        let redacted = GroupRideInviteLinkBuilder.redacted(url)
        XCTAssertEqual(redacted, url.absoluteString)
    }
}
