import Foundation
import CoreLocation

/// Loads Foursquare photos/rating/tips for the currently selected place, if the feature is
/// configured. Purely additive to the place-details card — nothing else depends on this state.
@Observable
@MainActor
final class PlaceEnrichmentViewModel {
    var enrichment: FoursquarePlaceEnrichment?

    private let service = FoursquarePlacesService()
    private var loadTask: Task<Void, Never>?

    func load(for destination: SearchResult) {
        loadTask?.cancel()
        enrichment = nil
        guard service.isEnabled else { return }
        loadTask = Task {
            let result = await service.fetchEnrichment(name: destination.name, coordinate: destination.coordinate)
            guard !Task.isCancelled else { return }
            enrichment = result
        }
    }

    func clear() {
        loadTask?.cancel()
        enrichment = nil
    }
}
