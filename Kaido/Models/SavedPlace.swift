import CoreLocation
import Foundation
import SwiftData

@Model
final class SavedPlace {
    var id: UUID = UUID()
    var mapboxIdentifier: String = ""
    var name: String = ""
    var address: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var category: String = ""
    var iconName: String = "mappin.circle.fill"
    var isPOI: Bool = false
    var isHome: Bool = false
    var isFavorite: Bool = false
    var lastUsedAt: Date?
    var createdAt: Date = Date()

    init(
        result: SearchResult,
        isHome: Bool = false,
        isFavorite: Bool = false
    ) {
        id = UUID()
        createdAt = Date()
        self.isHome = isHome
        self.isFavorite = isFavorite
        update(from: result)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var searchResult: SearchResult {
        let resolvedIconName = isHome ? "house.fill" : iconName
        return SearchResult(
            id: mapboxIdentifier.isEmpty ? "saved:\(id.uuidString)" : mapboxIdentifier,
            name: name,
            placeFormatted: address.isEmpty ? nil : address,
            coordinate: coordinate,
            category: category.isEmpty ? nil : category,
            iconName: resolvedIconName,
            isPOI: isPOI,
            placeCategory: PlaceCategory(iconName: iconName)
        )
    }

    func update(from result: SearchResult) {
        mapboxIdentifier = result.id
        name = result.name
        address = result.placeFormatted ?? ""
        latitude = result.coordinate.latitude
        longitude = result.coordinate.longitude
        category = result.category ?? ""
        // A saved Home is presented with a synthetic house icon. Preserve the place's original
        // Mapbox icon so it remains appropriate if Home is later unset but the place is favorited.
        if !(isHome && result.iconName == "house.fill") {
            iconName = result.iconName
        }
        isPOI = result.isPOI
    }

    func matches(_ result: SearchResult) -> Bool {
        if !mapboxIdentifier.isEmpty, mapboxIdentifier == result.id {
            return true
        }

        return abs(latitude - result.coordinate.latitude) < 0.000_01
            && abs(longitude - result.coordinate.longitude) < 0.000_01
    }
}
