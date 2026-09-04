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

    private let geocodingService = GeocodingService()
    private let aiService = AIRecommendationService()
    private var refreshTask: Task<Void, Never>?

    /// Where the last *finished* load looked (success or a clean "nothing nearby"/error result).
    /// Nil until one completes.
    private var lastRefreshCoordinate: CLLocationCoordinate2D?

    /// Where the load currently in flight is looking, if any. Kept separate from
    /// `lastRefreshCoordinate` so a location tick arriving mid-load doesn't count as "never
    /// fetched here" and restart the request.
    private var inFlightCoordinate: CLLocationCoordinate2D?

    /// Bumped on every `refresh`/`clear`. A load only mutates state if it is still the newest
    /// one, so a superseded load can't clobber a newer result or leave `isLoading` stuck.
    private var loadGeneration = 0

    /// Suggestions are considered still fresh within this radius of where they were fetched.
    private static let refetchDistanceMeters: CLLocationDistance = 400

    var isAIEnabled: Bool { aiService.isAIEnabled }

    /// Only fetch suggestions when browsing the map with no active destination or route.
    ///
    /// Called from several places on the map view (appear, every location update, and the
    /// Free Ride toggle), so it has to be cheap and idempotent. Core Location delivers a new
    /// fix roughly once a second even when standing still, and this previously cancelled and
    /// restarted the in-flight request on every one of those ticks — the reverse geocode plus
    /// five category searches never got a chance to finish, so the panel sat empty.
    func refreshIfNeeded(location: CLLocation?, isFreeRideMode: Bool) {
        guard isFreeRideMode, let location else { return }

        if let inFlight = inFlightCoordinate,
           location.coordinate.distance(to: inFlight) < Self.refetchDistanceMeters {
            return
        }

        if let last = lastRefreshCoordinate,
           location.coordinate.distance(to: last) < Self.refetchDistanceMeters {
            return
        }

        refresh(location: location)
    }

    /// Unconditionally fetch fresh suggestions for `location` (the panel's refresh button).
    func refresh(location: CLLocation) {
        refreshTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        inFlightCoordinate = location.coordinate
        refreshTask = Task {
            await loadRecommendations(near: location, generation: generation)
        }
    }

    func clear() {
        refreshTask?.cancel()
        loadGeneration += 1
        inFlightCoordinate = nil
        isLoading = false
        recommendations = []
        error = nil
        areaDescription = nil
        lastRefreshCoordinate = nil
    }

    private func loadRecommendations(near location: CLLocation, generation: Int) async {
        isLoading = true
        error = nil

        defer {
            if generation == loadGeneration {
                isLoading = false
                inFlightCoordinate = nil
            }
        }

        do {
            let area = try await geocodingService.reverseGeocode(coordinate: location.coordinate)
            guard isCurrent(generation) else { return }

            let candidates = try await geocodingService.nearbyPOIs(
                coordinate: location.coordinate,
                categories: Self.discoveryCategories,
                limitPerCategory: 3
            )
            guard isCurrent(generation) else { return }

            guard !candidates.isEmpty else {
                recommendations = []
                areaDescription = area
                error = "No nearby places found yet. Try riding a bit further."
                lastRefreshCoordinate = location.coordinate
                return
            }

            let curated = try await aiService.curate(
                areaDescription: area,
                candidates: candidates,
                userCoordinate: location.coordinate
            )
            guard isCurrent(generation) else { return }

            recommendations = curated
            areaDescription = area
            lastRefreshCoordinate = location.coordinate
        } catch let loadError {
            guard isCurrent(generation) else { return }
            recommendations = []
            error = loadError.localizedDescription
            // Remember the attempt so a persistent failure (bad token, no network) retries on
            // the next 400 m of riding or a manual refresh, not on every location tick.
            lastRefreshCoordinate = location.coordinate
        }
    }

    private func isCurrent(_ generation: Int) -> Bool {
        generation == loadGeneration && !Task.isCancelled
    }

    /// Categories biased toward casual exploration on a bike ride.
    private static let discoveryCategories = [
        "coffee",
        "park",
        "restaurant",
        "bakery",
        "tourist_attraction"
    ]
}

private extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}
