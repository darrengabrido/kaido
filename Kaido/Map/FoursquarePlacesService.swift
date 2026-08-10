import Foundation
import CoreLocation

/// Photos/rating/reviews for a place, sourced from Foursquare — Mapbox's Search Box API (the
/// rest of this app's place data) doesn't carry any of this.
struct FoursquarePlaceEnrichment {
    let rating: Double?
    let priceLevel: Int?
    let photoURLs: [URL]
    let tips: [String]
}

/// Optional — active only when `FOURSQUARE_API_KEY` is configured; otherwise the place-details
/// card simply omits this section. Same shape as `AIRecommendationService`'s OpenAI gating.
///
/// Targets Foursquare's current Places API (`places-api.foursquare.com`), not the legacy v3
/// `api.foursquare.com/v3` API, which is deprecated. `SearchResult` carries no Foursquare id, so
/// each call starts with a name+coordinate search to find the best-match place first.
struct FoursquarePlacesService {
    private static let baseURL = "https://places-api.foursquare.com"
    /// Foursquare's current API is versioned by date header rather than a URL path segment —
    /// verify this is still the latest version string when wiring in a real API key.
    private static let apiVersion = "2025-06-17"

    var isEnabled: Bool {
        guard let apiKey = Self.apiKey else { return false }
        return !apiKey.isEmpty
    }

    /// Returns `nil` (never throws to the caller) when the feature is disabled, no confident
    /// match is found, or any request fails — the place-details card just omits the section.
    func fetchEnrichment(name: String, coordinate: CLLocationCoordinate2D) async -> FoursquarePlaceEnrichment? {
        guard let apiKey = Self.apiKey, !apiKey.isEmpty else { return nil }

        guard let match = try? await search(name: name, coordinate: coordinate, apiKey: apiKey) else {
            return nil
        }

        async let photos = fetchPhotos(placeID: match.id, apiKey: apiKey)
        async let tips = fetchTips(placeID: match.id, apiKey: apiKey)

        return FoursquarePlaceEnrichment(
            rating: match.rating,
            priceLevel: match.price,
            photoURLs: await photos,
            tips: await tips
        )
    }

    /// One call finds the nearest matching place and asks for rating/price up front — Foursquare
    /// classifies both as Premium fields, but they're requestable via `fields` on search itself,
    /// so this avoids a second `/places/{id}` details round trip just for two numbers.
    private func search(
        name: String,
        coordinate: CLLocationCoordinate2D,
        apiKey: String
    ) async throws -> SearchResponse.Result? {
        guard var components = URLComponents(string: "\(Self.baseURL)/places/search") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "query", value: name),
            URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "radius", value: "100"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "fields", value: "fsq_place_id,rating,price")
        ]
        guard let url = components.url else { return nil }

        let (data, response) = try await Self.send(url: url, apiKey: apiKey)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.results.first
    }

    /// Photos and tips are separate, dedicated endpoints in the current Places API (not fields
    /// requestable on search/details) — each keyed by the place id found above.
    private func fetchPhotos(placeID: String, apiKey: String) async -> [URL] {
        guard let url = URL(string: "\(Self.baseURL)/places/\(placeID)/photos") else { return [] }
        guard let (data, response) = try? await Self.send(url: url, apiKey: apiKey),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return []
        }
        let decoded = (try? JSONDecoder().decode([PhotoResponse].self, from: data)) ?? []
        // Foursquare photo URLs are built by concatenating prefix + size + suffix.
        return decoded.prefix(6).compactMap { URL(string: "\($0.prefix)300x300\($0.suffix)") }
    }

    private func fetchTips(placeID: String, apiKey: String) async -> [String] {
        guard let url = URL(string: "\(Self.baseURL)/places/\(placeID)/tips") else { return [] }
        guard let (data, response) = try? await Self.send(url: url, apiKey: apiKey),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return []
        }
        let decoded = (try? JSONDecoder().decode([TipResponse].self, from: data)) ?? []
        return decoded.prefix(3).map(\.text)
    }

    private static func send(url: URL, apiKey: String) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiVersion, forHTTPHeaderField: "X-Places-Api-Version")
        return try await URLSession.shared.data(for: request)
    }

    private static var apiKey: String? {
        Bundle.main.object(forInfoDictionaryKey: "FoursquareAPIKey") as? String
    }
}

private struct SearchResponse: Decodable {
    let results: [Result]

    struct Result: Decodable {
        let id: String
        // Foursquare's own scale — confirm 0–5 vs 0–10 against a live response before display.
        let rating: Double?
        let price: Int?

        enum CodingKeys: String, CodingKey {
            case id = "fsq_place_id"
            case rating
            case price
        }
    }
}

private struct PhotoResponse: Decodable {
    let prefix: String
    let suffix: String
}

private struct TipResponse: Decodable {
    let text: String
}
