import Foundation
import CoreLocation
import OSLog

private let logger = Logger(subsystem: "com.oaktreehouse.kaido", category: "foursquare")

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
    /// Rating, price, photos, and tips are all Premium fields — billed from the first call, no
    /// free tier, regardless of any free Pro-call balance. Flip this to `true` once billing/
    /// credits are set up on the Foursquare account. While `false`, only the free Pro-tier
    /// search call runs, so this is a connectivity check, not the real feature — enrichment
    /// will always come back empty (no rating, no photos, no tips).
    private static let includePremiumFields = false

    var isEnabled: Bool {
        guard let apiKey = Self.apiKey else { return false }
        return !apiKey.isEmpty
    }

    /// Returns `nil` (never throws to the caller) when the feature is disabled, no confident
    /// match is found, or any request fails — the place-details card just omits the section.
    func fetchEnrichment(name: String, coordinate: CLLocationCoordinate2D) async -> FoursquarePlaceEnrichment? {
        guard let apiKey = Self.apiKey, !apiKey.isEmpty else {
            logger.debug("Disabled — no FOURSQUARE_API_KEY configured.")
            return nil
        }

        guard let match = await search(name: name, coordinate: coordinate, apiKey: apiKey) else {
            return nil
        }
        logger.debug("Matched \"\(name, privacy: .public)\" -> place id \(match.id, privacy: .public), rating=\(match.rating.map(String.init) ?? "nil", privacy: .public), price=\(match.price.map(String.init) ?? "nil", privacy: .public)")

        guard Self.includePremiumFields else {
            logger.debug("Premium fields disabled (includePremiumFields = false) — skipping photos/tips, matched place confirms free-tier connectivity only.")
            return FoursquarePlaceEnrichment(rating: nil, priceLevel: nil, photoURLs: [], tips: [])
        }

        async let photos = fetchPhotos(placeID: match.id, apiKey: apiKey)
        async let tips = fetchTips(placeID: match.id, apiKey: apiKey)
        let (photoURLs, tipTexts) = await (photos, tips)
        logger.debug("\(photoURLs.count, privacy: .public) photo(s), \(tipTexts.count, privacy: .public) tip(s) for place id \(match.id, privacy: .public)")

        return FoursquarePlaceEnrichment(
            rating: match.rating,
            priceLevel: match.price,
            photoURLs: photoURLs,
            tips: tipTexts
        )
    }

    /// One call finds the nearest matching place and asks for rating/price up front — Foursquare
    /// classifies both as Premium fields, but they're requestable via `fields` on search itself,
    /// so this avoids a second `/places/{id}` details round trip just for two numbers.
    private func search(
        name: String,
        coordinate: CLLocationCoordinate2D,
        apiKey: String
    ) async -> SearchResponse.Result? {
        guard var components = URLComponents(string: "\(Self.baseURL)/places/search") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "query", value: name),
            URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "radius", value: "100"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "fields", value: "fsq_place_id,rating,price")
        ]
        guard let url = components.url else { return nil }

        guard let (data, statusCode) = await Self.send(url: url, apiKey: apiKey, label: "search") else {
            return nil
        }
        guard statusCode == 200 else {
            logger.error("search HTTP \(statusCode, privacy: .public): \(Self.bodyPreview(data), privacy: .public)")
            return nil
        }

        do {
            let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
            if decoded.results.isEmpty {
                logger.debug("search for \"\(name, privacy: .public)\" returned zero results.")
            }
            return decoded.results.first
        } catch {
            logger.error("search decode failed: \(String(describing: error), privacy: .public) — body: \(Self.bodyPreview(data), privacy: .public)")
            return nil
        }
    }

    /// Photos and tips are separate, dedicated endpoints in the current Places API (not fields
    /// requestable on search/details) — each keyed by the place id found above.
    private func fetchPhotos(placeID: String, apiKey: String) async -> [URL] {
        guard let url = URL(string: "\(Self.baseURL)/places/\(placeID)/photos") else { return [] }
        guard let (data, statusCode) = await Self.send(url: url, apiKey: apiKey, label: "photos") else {
            return []
        }
        guard statusCode == 200 else {
            logger.error("photos HTTP \(statusCode, privacy: .public): \(Self.bodyPreview(data), privacy: .public)")
            return []
        }
        do {
            let decoded = try JSONDecoder().decode([PhotoResponse].self, from: data)
            // Foursquare photo URLs are built by concatenating prefix + size + suffix.
            return decoded.prefix(6).compactMap { URL(string: "\($0.prefix)300x300\($0.suffix)") }
        } catch {
            logger.error("photos decode failed: \(String(describing: error), privacy: .public) — body: \(Self.bodyPreview(data), privacy: .public)")
            return []
        }
    }

    private func fetchTips(placeID: String, apiKey: String) async -> [String] {
        guard let url = URL(string: "\(Self.baseURL)/places/\(placeID)/tips") else { return [] }
        guard let (data, statusCode) = await Self.send(url: url, apiKey: apiKey, label: "tips") else {
            return []
        }
        guard statusCode == 200 else {
            logger.error("tips HTTP \(statusCode, privacy: .public): \(Self.bodyPreview(data), privacy: .public)")
            return []
        }
        do {
            let decoded = try JSONDecoder().decode([TipResponse].self, from: data)
            return decoded.prefix(3).map(\.text)
        } catch {
            logger.error("tips decode failed: \(String(describing: error), privacy: .public) — body: \(Self.bodyPreview(data), privacy: .public)")
            return []
        }
    }

    /// Truncated so a large HTML error page (e.g. a misrouted 404) doesn't flood the console.
    private static func bodyPreview(_ data: Data) -> String {
        String(decoding: data.prefix(500), as: UTF8.self)
    }

    /// Returns `nil` only on a transport-level failure (no connectivity, DNS, etc.) — an HTTP
    /// error status is still a value here, not a thrown error, so callers can log the body.
    private static func send(url: URL, apiKey: String, label: String) async -> (Data, Int)? {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiVersion, forHTTPHeaderField: "X-Places-Api-Version")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                logger.error("\(label, privacy: .public): non-HTTP response")
                return nil
            }
            return (data, http.statusCode)
        } catch {
            logger.error("\(label, privacy: .public) request failed: \(String(describing: error), privacy: .public)")
            return nil
        }
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
