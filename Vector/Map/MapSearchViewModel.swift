import Foundation
import CoreLocation

@Observable
@MainActor
final class MapSearchViewModel {
    var query = ""
    var results: [SearchResult] = []
    var isSearching = false
    var searchError: String?
    var selectedDestination: SearchResult?
    var proximity: CLLocationCoordinate2D?

    private let geocodingService = GeocodingService()
    private var searchTask: Task<Void, Never>?
    private var suppressNextQueryChange = false

    /// Call from the view's `.onChange(of: query)` — property observers on `@Observable`
    /// stored properties don't reliably run before SwiftUI's own binding update lands,
    /// so search-on-type is driven explicitly from the view instead.
    func queryDidChange() {
        if suppressNextQueryChange {
            suppressNextQueryChange = false
            return
        }
        scheduleSearch()
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            searchError = nil
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await runSearch(query: trimmed)
        }
    }

    private func runSearch(query: String) async {
        isSearching = true
        searchError = nil
        do {
            let found = try await geocodingService.search(query: query, proximity: proximity)
            guard !Task.isCancelled else { return }
            results = found
        } catch {
            guard !Task.isCancelled else { return }
            searchError = error.localizedDescription
        }
        isSearching = false
    }

    func selectResult(_ result: SearchResult) {
        searchTask?.cancel()
        selectedDestination = result
        results = []
        suppressNextQueryChange = true
        query = result.name
    }

    func clearSelection() {
        searchTask?.cancel()
        selectedDestination = nil
        results = []
        suppressNextQueryChange = true
        query = ""
    }
}
