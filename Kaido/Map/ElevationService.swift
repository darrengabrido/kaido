import CoreLocation
import Foundation
import MapboxMaps

/// Fetches terrain elevations along a route via Mapbox Tilequery (Terrain v2 contours).
///
/// Contours are quantized to 10 m steps — fine for preview hill labels, not survey-grade.
struct ElevationService {
    private let session: URLSession
    private let maxConcurrentRequests: Int

    init(session: URLSession = .shared, maxConcurrentRequests: Int = 6) {
        self.session = session
        self.maxConcurrentRequests = max(1, maxConcurrentRequests)
    }

    /// Best-effort heights in meters along the route, preserving sample order. Failed points are
    /// dropped. Returns an empty array when the token is missing.
    func elevations(along coordinates: [CLLocationCoordinate2D]) async -> [Double] {
        let accessToken = resolvedAccessToken()
        guard !accessToken.isEmpty, !Self.isPlaceholderToken(accessToken) else { return [] }
        guard !coordinates.isEmpty else { return [] }

        var ordered: [Double?] = Array(repeating: nil, count: coordinates.count)
        var start = 0
        while start < coordinates.count {
            let end = min(start + maxConcurrentRequests, coordinates.count)
            await withTaskGroup(of: (Int, Double?).self) { group in
                for index in start..<end {
                    let coordinate = coordinates[index]
                    group.addTask {
                        (index, await self.elevation(at: coordinate, accessToken: accessToken))
                    }
                }
                for await (index, height) in group {
                    ordered[index] = height
                }
            }
            start = end
        }

        return ordered.compactMap { $0 }
    }

    private func elevation(at coordinate: CLLocationCoordinate2D, accessToken: String) async -> Double? {
        guard var components = URLComponents(
            string: "https://api.mapbox.com/v4/mapbox.mapbox-terrain-v2/tilequery/\(coordinate.longitude),\(coordinate.latitude).json"
        ) else { return nil }

        components.queryItems = [
            URLQueryItem(name: "layers", value: "contour"),
            URLQueryItem(name: "limit", value: "50"),
            URLQueryItem(name: "access_token", value: accessToken),
        ]

        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(TilequeryResponse.self, from: data)
            return decoded.highestContourElevation
        } catch {
            return nil
        }
    }

    private func resolvedAccessToken() -> String {
        let fromOptions = MapboxOptions.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fromOptions.isEmpty { return fromOptions }
        return (Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isPlaceholderToken(_ token: String) -> Bool {
        token.contains("your_mapbox") || token.hasSuffix("_here")
    }
}

private struct TilequeryResponse: Decodable {
    let features: [Feature]

    var highestContourElevation: Double? {
        features.compactMap(\.properties.ele).max()
    }

    struct Feature: Decodable {
        let properties: Properties
    }

    struct Properties: Decodable {
        let ele: Double?
    }
}
