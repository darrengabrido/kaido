import Foundation
import CoreLocation

/// A nearby place surfaced during free ride mode, optionally with an AI-written blurb.
struct POIRecommendation: Identifiable, Equatable {
    let id: String
    let name: String
    let placeFormatted: String?
    let coordinate: CLLocationCoordinate2D
    let category: String?
    let iconName: String
    let blurb: String
    let distanceMeters: Double

    var searchResult: SearchResult {
        SearchResult(
            id: id,
            name: name,
            placeFormatted: placeFormatted,
            coordinate: coordinate,
            category: category,
            iconName: iconName,
            isPOI: true
        )
    }

    static func == (lhs: POIRecommendation, rhs: POIRecommendation) -> Bool {
        lhs.id == rhs.id
    }
}
