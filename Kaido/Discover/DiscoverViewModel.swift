import Foundation
import CoreLocation

/// Loads AI-curated nearby POI suggestions while the rider is in free ride mode.
@Observable
@MainActor
final class DiscoverViewModel {
    var recommendations: [POIRecommendation] = []
    var isLoading = false
    var error: String?
    var areaDescription: String?
    var isPanelExpanded = true

    private(set) var ridePurpose: RidePurpose?
    private(set) var interestTags: [InterestTag] = []

    private let geocodingService = GeocodingService()
    private let aiService = AIRecommendationService()
    private var refreshTask: Task<Void, Never>?
    private var lastRefreshCoordinate: CLLocationCoordinate2D?

    var isAIEnabled: Bool { aiService.isAIEnabled }

    /// Only fetch suggestions when browsing the map with no active destination or route.
    func refreshIfNeeded(
        location: CLLocation?,
        isFreeRideMode: Bool,
        ridePurpose: RidePurpose? = nil,
        interestTags: [InterestTag] = []
    ) {
        guard isFreeRideMode, let location else { return }
        self.ridePurpose = ridePurpose
        self.interestTags = interestTags

        if let last = lastRefreshCoordinate,
           location.coordinate.distance(to: last) < 400,
           !recommendations.isEmpty || isLoading {
            return
        }

        refresh(location: location)
    }

    func refresh(location: CLLocation) {
        lastRefreshCoordinate = nil
        refreshTask?.cancel()
        refreshTask = Task {
            await loadRecommendations(near: location)
        }
    }

    func clear() {
        refreshTask?.cancel()
        recommendations = []
        error = nil
        areaDescription = nil
        lastRefreshCoordinate = nil
    }

    private func loadRecommendations(near location: CLLocation) async {
        isLoading = true
        error = nil

        do {
            let area = try await geocodingService.reverseGeocode(coordinate: location.coordinate)
            guard !Task.isCancelled else { return }

            let candidates = try await geocodingService.nearbyPOIs(
                coordinate: location.coordinate,
                categories: Self.discoveryCategories(interestTags: interestTags),
                limitPerCategory: 3
            )
            guard !Task.isCancelled else { return }

            guard !candidates.isEmpty else {
                recommendations = []
                areaDescription = area
                error = "No nearby places found yet. Try riding a bit further."
                isLoading = false
                lastRefreshCoordinate = location.coordinate
                return
            }

            let curated = try await aiService.curate(
                areaDescription: area,
                candidates: candidates,
                userCoordinate: location.coordinate,
                ridePurpose: ridePurpose,
                interestTags: interestTags
            )
            guard !Task.isCancelled else { return }

            recommendations = curated
            areaDescription = area
            lastRefreshCoordinate = location.coordinate
        } catch let loadError {
            guard !Task.isCancelled else { return }
            recommendations = []
            error = loadError.localizedDescription
        }

        isLoading = false
    }

    /// Categories biased toward casual exploration on a bike ride.
    private static let baseDiscoveryCategories = [
        "coffee",
        "park",
        "restaurant",
        "bakery",
        "tourist_attraction"
    ]

    /// The base categories, plus anything the rider's selected interest tags pull in
    /// (e.g. nightlife adds "bar") that isn't already covered.
    private static func discoveryCategories(interestTags: [InterestTag]) -> [String] {
        var categories = baseDiscoveryCategories
        for tag in interestTags {
            for category in tag.poiCategories where !categories.contains(category) {
                categories.append(category)
            }
        }
        return categories
    }
}

private extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}
