@testable import Kaido
import XCTest

final class ElevationMathTests: XCTestCase {
    func testRequiresAtLeastThreeSamples() {
        XCTAssertNil(ElevationMath.profile(from: []))
        XCTAssertNil(ElevationMath.profile(from: [10, 20]))
    }

    func testFlatRouteHasZeroGainAndLoss() {
        let profile = ElevationMath.profile(from: [100, 100, 100, 100])
        XCTAssertEqual(profile?.gainMeters, 0)
        XCTAssertEqual(profile?.lossMeters, 0)
        XCTAssertEqual(profile?.hillLabel, "Flat")
    }

    func testSingleClimb() {
        let profile = ElevationMath.profile(from: [10, 20, 40, 70])
        XCTAssertEqual(profile?.gainMeters, 60)
        XCTAssertEqual(profile?.lossMeters, 0)
        XCTAssertEqual(profile?.hillLabel, "Moderate hill")
    }

    func testClimbAndDescent() {
        let profile = ElevationMath.profile(from: [0, 40, 80, 50, 20])
        XCTAssertEqual(profile?.gainMeters, 80)
        XCTAssertEqual(profile?.lossMeters, 60)
        XCTAssertEqual(profile?.hillLabel, "Moderate hill")
    }

    func testNoiseFloorIgnoresJitter() {
        let profile = ElevationMath.profile(
            from: [100, 100.4, 100.2, 100.5, 100.1],
            noiseFloorMeters: 1.0
        )
        XCTAssertEqual(profile?.gainMeters, 0)
        XCTAssertEqual(profile?.lossMeters, 0)
    }

    func testHillLabelBands() {
        XCTAssertEqual(ElevationMath.profile(from: [0, 5, 10])?.hillLabel, "Flat")
        XCTAssertEqual(ElevationMath.profile(from: [0, 10, 30])?.hillLabel, "Gentle hill")
        XCTAssertEqual(ElevationMath.profile(from: [0, 80, 160])?.hillLabel, "Steep hill")
    }
}
