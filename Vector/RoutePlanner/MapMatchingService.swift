import Foundation
import CoreLocation

struct MapMatchingResult {
    var coordinates: [CLLocationCoordinate2D]
    var distanceMeters: Double
}

enum MapMatchingError: LocalizedError {
    case invalidResponse
    case noMatch

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Received an invalid response from Mapbox."
        case .noMatch:
            return "No road match found for this route."
        }
    }
}

struct MapMatchingService {
    private let accessToken: String

    init() {
        accessToken = Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String ?? ""
    }

    func match(coordinates: [CLLocationCoordinate2D], profile: String = "cycling") async throws -> MapMatchingResult {
        let coordinateString = coordinates
            .map { "\($0.longitude),\($0.latitude)" }
            .joined(separator: ";")

        guard var components = URLComponents(
            string: "https://api.mapbox.com/matching/v5/mapbox/\(profile)/\(coordinateString)"
        ) else {
            throw MapMatchingError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "geometries", value: "geojson"),
            URLQueryItem(name: "overview", value: "full"),
            URLQueryItem(name: "access_token", value: accessToken),
        ]

        guard let url = components.url else {
            throw MapMatchingError.invalidResponse
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw MapMatchingError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(MatchingResponse.self, from: data)
        guard let matching = decoded.matchings.first else {
            throw MapMatchingError.noMatch
        }

        let matchedCoordinates = matching.geometry.coordinates.map {
            CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0])
        }

        return MapMatchingResult(coordinates: matchedCoordinates, distanceMeters: matching.distance)
    }
}

private struct MatchingResponse: Decodable {
    var matchings: [Matching]
}

private struct Matching: Decodable {
    var distance: Double
    var geometry: GeoJSONLineString
}

private struct GeoJSONLineString: Decodable {
    var coordinates: [[Double]]
}
