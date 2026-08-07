@testable import Kaido
import XCTest

final class PlaceCategoryTests: XCTestCase {
    func testCategorizeBucketsKnownMakiValues() {
        XCTAssertEqual(PlaceCategory.categorize(maki: "cafe", isPOI: true).category, .coffee)
        XCTAssertEqual(PlaceCategory.categorize(maki: "restaurant-pizza", isPOI: true).category, .food)
        XCTAssertEqual(PlaceCategory.categorize(maki: "park", isPOI: true).category, .park)
        XCTAssertEqual(PlaceCategory.categorize(maki: "bicycle-share", isPOI: true).category, .cycling)
    }

    func testCategorizePreservesFineGrainedIconWithinABucket() {
        // Airport and rail both bucket into .transit but should keep their own icon.
        let airport = PlaceCategory.categorize(maki: "airport", isPOI: true)
        let rail = PlaceCategory.categorize(maki: "rail", isPOI: true)
        XCTAssertEqual(airport.category, .transit)
        XCTAssertEqual(rail.category, .transit)
        XCTAssertEqual(airport.iconName, "airplane")
        XCTAssertEqual(rail.iconName, "tram.fill")
    }

    func testCategorizeFallsBackToOtherForUnknownMaki() {
        let result = PlaceCategory.categorize(maki: "some-unrecognized-maki", isPOI: true)
        XCTAssertEqual(result.category, .other)
        XCTAssertEqual(result.iconName, "mappin.circle.fill")
    }

    func testCategorizeFallsBackForNilMakiRespectingIsPOI() {
        XCTAssertEqual(PlaceCategory.categorize(maki: nil, isPOI: true).iconName, "mappin.circle.fill")
        XCTAssertEqual(PlaceCategory.categorize(maki: nil, isPOI: false).iconName, "location.circle.fill")
    }

    func testIconNameFallbackInitializerRoundTripsBucketIcons() {
        for category in PlaceCategory.allCases {
            XCTAssertEqual(PlaceCategory(iconName: category.iconName), category)
        }
    }

    func testIconNameFallbackInitializerHandlesUnknownIcon() {
        XCTAssertEqual(PlaceCategory(iconName: "not.a.real.symbol"), .other)
    }
}
