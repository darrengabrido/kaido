@testable import Kaido
import CoreLocation
import XCTest

final class PolylineSamplerTests: XCTestCase {
    func testShortLineReturnsEndpoints() {
        let start = CLLocationCoordinate2D(latitude: 33.88, longitude: -118.40)
        let end = CLLocationCoordinate2D(latitude: 33.884, longitude: -118.40) // ~440 m north
        let samples = PolylineSampler.coordinates(along: [start, end], everyMeters: 100, maxSamples: 40)
        XCTAssertEqual(samples.first!.latitude, start.latitude, accuracy: 0.00001)
        XCTAssertEqual(samples.last!.latitude, end.latitude, accuracy: 0.00001)
        XCTAssertGreaterThanOrEqual(samples.count, 2)
        XCTAssertLessThanOrEqual(samples.count, 6)
    }

    func testRespectsMaxSamples() {
        // ~5 km north
        let start = CLLocationCoordinate2D(latitude: 33.88, longitude: -118.40)
        let end = CLLocationCoordinate2D(latitude: 33.925, longitude: -118.40)
        let samples = PolylineSampler.coordinates(along: [start, end], everyMeters: 50, maxSamples: 8)
        XCTAssertEqual(samples.count, 8)
        XCTAssertEqual(samples.first!.latitude, start.latitude, accuracy: 0.00001)
        XCTAssertEqual(samples.last!.latitude, end.latitude, accuracy: 0.00001)
    }

    func testSinglePoint() {
        let point = CLLocationCoordinate2D(latitude: 33.88, longitude: -118.40)
        let samples = PolylineSampler.coordinates(along: [point])
        XCTAssertEqual(samples.count, 1)
    }
}
