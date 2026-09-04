@testable import Kaido
import CoreLocation
import XCTest

final class CompanionStopCuratorTests: XCTestCase {
    private let here = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

    private func candidate(_ id: String, category: String?, offsetMeters: Double) -> SearchResult {
        // ~0.00001 deg latitude ≈ 1.1 m, close enough for ordering.
        SearchResult(
            id: id,
            name: id.capitalized,
            placeFormatted: nil,
            coordinate: CLLocationCoordinate2D(latitude: here.latitude + offsetMeters / 111_000, longitude: here.longitude),
            category: category,
            iconName: "mappin",
            isPOI: true
        )
    }

    func testParseKeepsOnlyRealCandidatesInModelOrder() throws {
        let candidates = [candidate("cafe", category: "Coffee", offsetMeters: 100), candidate("park", category: "Park", offsetMeters: 300)]
        let reply = #"{"recommendations":[{"id":"park","blurb":"Green."},{"id":"made-up","blurb":"Nope."},{"id":"cafe","blurb":"Beans."}]}"#
        let picks = try CompanionStopCurator.parse(reply, candidates: candidates, userCoordinate: here)
        XCTAssertEqual(picks.map(\.id), ["park", "cafe"])
        XCTAssertEqual(picks.first?.blurb, "Green.")
        XCTAssertEqual(picks.first?.distanceMeters ?? 0, 300, accuracy: 5)
    }

    func testParseRejectsNonJSON() {
        XCTAssertThrowsError(try CompanionStopCurator.parse("Sure! Here are some places.", candidates: [], userCoordinate: here)) { error in
            XCTAssertEqual(error as? CompanionClientError, .notJSON)
        }
    }

    func testLocalFallbackPrefersVarietyThenDistance() {
        let candidates = [
            candidate("cafe-near", category: "Coffee", offsetMeters: 50),
            candidate("cafe-mid", category: "Coffee", offsetMeters: 80),
            candidate("cafe-far", category: "Coffee", offsetMeters: 120),
            candidate("park", category: "Park", offsetMeters: 400),
            candidate("bakery", category: "Bakery", offsetMeters: 600),
            candidate("cafe-farther", category: "Coffee", offsetMeters: 900)
        ]
        let picks = CompanionStopCurator.curateLocally(candidates: candidates, userCoordinate: here)
        XCTAssertEqual(picks.count, 5)
        XCTAssertEqual(picks.prefix(3).map(\.id), ["cafe-near", "cafe-mid", "cafe-far"])
        XCTAssertTrue(picks.map(\.id).contains("park"))
        XCTAssertTrue(picks.map(\.id).contains("bakery"))
        XCTAssertFalse(picks.map(\.id).contains("cafe-farther"))
    }

    func testPromptListsEveryCandidateWithDistance() throws {
        let candidates = [candidate("cafe", category: "Coffee", offsetMeters: 100)]
        let prompt = try CompanionStopCurator.prompt(areaDescription: "Mission", candidates: candidates, userCoordinate: here)
        XCTAssertTrue(prompt.user.contains("Area: Mission"))
        XCTAssertTrue(prompt.user.contains("\"id\":\"cafe\""))
        XCTAssertTrue(prompt.user.contains("distance_m"))
        XCTAssertTrue(prompt.system.contains("recommendations"))
    }
}
