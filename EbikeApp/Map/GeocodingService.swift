import Foundation
import CoreLocation
import MapboxMaps

struct SearchResult: Identifiable {
    let id: String
    let name: String
    let placeFormatted: String?
    let coordinate: CLLocationCoordinate2D
    let category: String?
    let iconName: String
    let isPOI: Bool
}

enum GeocodingError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Couldn't reach search. Try again."
        }
    }
}

/// Wraps Mapbox's **Search Box** forward endpoint (not the Geocoding API) so that
/// business/POI queries — "Blue Bottle Coffee", "REI", "Safeway" — return the actual
/// places with categories, rather than the address-only results the Geocoding API gives.
struct GeocodingService {
    func search(query: String, proximity: CLLocationCoordinate2D?) async throws -> [SearchResult] {
        guard var components = URLComponents(string: "https://api.mapbox.com/search/searchbox/v1/forward") else {
            throw GeocodingError.invalidResponse
        }
        var queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "8"),
            URLQueryItem(name: "access_token", value: MapboxOptions.accessToken)
        ]
        if let proximity {
            queryItems.append(URLQueryItem(name: "proximity", value: "\(proximity.longitude),\(proximity.latitude)"))
        }
        components.queryItems = queryItems

        guard let url = components.url else { throw GeocodingError.invalidResponse }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GeocodingError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(SearchBoxResponse.self, from: data)
        return decoded.features.map { feature in
            let props = feature.properties
            let isPOI = props.featureType == "poi"
            return SearchResult(
                id: props.mapboxId ?? UUID().uuidString,
                name: props.name,
                placeFormatted: props.fullAddress ?? props.placeFormatted,
                coordinate: CLLocationCoordinate2D(
                    latitude: props.coordinates.latitude,
                    longitude: props.coordinates.longitude
                ),
                category: props.poiCategory?.first?.capitalized,
                iconName: Self.symbolName(maki: props.maki, isPOI: isPOI),
                isPOI: isPOI
            )
        }
    }

    /// Maps Mapbox "maki" icon names to the closest SF Symbol.
    private static func symbolName(maki: String?, isPOI: Bool) -> String {
        guard let maki else { return isPOI ? "mappin.circle.fill" : "location.circle.fill" }
        switch maki {
        case "cafe", "coffee": return "cup.and.saucer.fill"
        case "restaurant", "restaurant-pizza", "fast-food": return "fork.knife"
        case "bar", "beer", "alcohol-shop": return "wineglass.fill"
        case "grocery", "shop": return "cart.fill"
        case "fuel", "charging-station": return "fuelpump.fill"
        case "lodging": return "bed.double.fill"
        case "bicycle", "bicycle-share": return "bicycle"
        case "bank": return "banknote.fill"
        case "hospital", "pharmacy", "doctor": return "cross.fill"
        case "park", "garden": return "tree.fill"
        case "school", "college": return "graduationcap.fill"
        case "fitness-centre", "gym": return "figure.run"
        case "cinema", "theatre": return "film.fill"
        case "parking": return "parkingsign"
        case "airport", "airfield": return "airplane"
        case "rail", "rail-metro", "bus": return "tram.fill"
        default: return isPOI ? "mappin.circle.fill" : "location.circle.fill"
        }
    }
}

private struct SearchBoxResponse: Decodable {
    let features: [Feature]

    struct Feature: Decodable {
        let properties: Properties
    }

    struct Properties: Decodable {
        let mapboxId: String?
        let name: String
        let featureType: String?
        let fullAddress: String?
        let placeFormatted: String?
        let coordinates: Coordinates
        let maki: String?
        let poiCategory: [String]?

        enum CodingKeys: String, CodingKey {
            case mapboxId = "mapbox_id"
            case name
            case featureType = "feature_type"
            case fullAddress = "full_address"
            case placeFormatted = "place_formatted"
            case coordinates
            case maki
            case poiCategory = "poi_category"
        }
    }

    struct Coordinates: Decodable {
        let longitude: Double
        let latitude: Double
    }
}
