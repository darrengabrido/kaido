@testable import Kaido
import XCTest

final class GroupRideInviteParserTests: XCTestCase {
    private let rideId = UUID()

    func testParsesCustomSchemeLink() throws {
        let url = try XCTUnwrap(URL(string: "kaido://ride-together/join?ride=\(rideId.uuidString)&token=abc123"))
        let link = GroupRideInviteParser.parse(url)
        XCTAssertEqual(link, GroupRideInviteLink(rideId: rideId, token: "abc123"))
    }

    func testBuilderAndParserRoundTrip() {
        let url = GroupRideInviteLinkBuilder.makeLink(rideId: rideId, token: "s3cr3t-token")
        let parsed = GroupRideInviteParser.parse(url)
        XCTAssertEqual(parsed, GroupRideInviteLink(rideId: rideId, token: "s3cr3t-token"))
    }

    func testRejectsWrongHost() {
        let url = URL(string: "kaido://spotify-callback?ride=\(rideId.uuidString)&token=abc")!
        XCTAssertNil(GroupRideInviteParser.parse(url))
    }

    func testRejectsWrongPath() {
        let url = URL(string: "kaido://ride-together/leave?ride=\(rideId.uuidString)&token=abc")!
        XCTAssertNil(GroupRideInviteParser.parse(url))
    }

    func testRejectsMissingToken() {
        let url = URL(string: "kaido://ride-together/join?ride=\(rideId.uuidString)")!
        XCTAssertNil(GroupRideInviteParser.parse(url))
    }

    func testRejectsMalformedRideId() {
        let url = URL(string: "kaido://ride-together/join?ride=not-a-uuid&token=abc")!
        XCTAssertNil(GroupRideInviteParser.parse(url))
    }

    func testRejectsUnrelatedURL() {
        let url = URL(string: "https://example.com/anything")!
        XCTAssertNil(GroupRideInviteParser.parse(url))
    }
}
