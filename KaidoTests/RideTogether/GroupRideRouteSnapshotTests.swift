@testable import Kaido
import XCTest
import CoreLocation

final class GroupRideRouteSnapshotTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let original = GroupRideRouteSnapshot.fixture()

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GroupRideRouteSnapshot.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.schemaVersion, GroupRideRouteSnapshot.currentSchemaVersion)
        XCTAssertEqual(decoded.orderedWaypoints.map(\.order), [0, 1])
    }

    func testDecodedGeometryRoundTripsThroughEncodedPolyline() throws {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            CLLocationCoordinate2D(latitude: 37.7700, longitude: -122.4300),
            CLLocationCoordinate2D(latitude: 37.7694, longitude: -122.4862)
        ]
        var snapshot = GroupRideRouteSnapshot.fixture()
        snapshot.encodedPolyline = GroupRidePolylineCodec.encode(coordinates)

        let decodedGeometry = try XCTUnwrap(snapshot.decodedGeometry)
        XCTAssertEqual(decodedGeometry.count, coordinates.count)
        for (decoded, expected) in zip(decodedGeometry, coordinates) {
            XCTAssertEqual(decoded.latitude, expected.latitude, accuracy: 0.00001)
            XCTAssertEqual(decoded.longitude, expected.longitude, accuracy: 0.00001)
        }
    }

    func testMissingPolylineYieldsNilGeometry() {
        var snapshot = GroupRideRouteSnapshot.fixture()
        snapshot.encodedPolyline = nil
        XCTAssertNil(snapshot.decodedGeometry)
    }

    func testBuildFromRouteOptionCapturesMainRouteAsNilAlternativeIndex() {
        let mainOption = RouteOption(
            id: "main",
            distanceMeters: 4200,
            expectedTravelTime: 900,
            personalizedTravelTime: 900,
            stressProfile: .init(score: 0.2, quietFraction: 0.8, mixedFraction: 0.2, busyFraction: 0),
            coordinates: [
                CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                CLLocationCoordinate2D(latitude: 37.7694, longitude: -122.4862)
            ],
            isMain: true
        )

        let snapshot = GroupRideRouteSnapshot(
            destinationName: "Golden Gate Park",
            waypointCoordinates: [
                CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                CLLocationCoordinate2D(latitude: 37.7694, longitude: -122.4862)
            ],
            selecting: mainOption,
            among: [mainOption]
        )

        XCTAssertNil(snapshot.selectedAlternativeIndex)
        XCTAssertEqual(snapshot.distanceMeters, 4200)
        XCTAssertEqual(snapshot.destinationLatitude, 37.7694, accuracy: 0.0001)
        XCTAssertNotNil(snapshot.encodedPolyline)
    }
}
