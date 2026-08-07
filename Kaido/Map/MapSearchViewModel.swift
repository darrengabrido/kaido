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
    /// nil means "All" — every category shown.
    var selectedCategory: PlaceCategory?

    private let geocodingService = GeocodingService()
    private var searchTask: Task<Void, Never>?
    private var suppressNextQueryChange = false

    /// `results`, narrowed to `selectedCategory` when a category pill is active. What the
    /// results list and the map's POI pins both actually render.
    var filteredResults: [SearchResult] {
        guard let selectedCategory else { return results }
        return results.filter { $0.placeCategory == selectedCategory }
    }

    /// Distinct categories present in `results` with their counts, most common first — the
    /// data behind the category pill row.
    var categoryTallies: [PlaceCategoryTally] {
        Dictionary(grouping: results, by: \.placeCategory)
            .map { PlaceCategoryTally(category: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

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
        // A single character is rarely a useful query and just burns Search Box requests while
        // flickering the results list — wait for at least two.
        guard trimmed.count >= 2 else {
            results = []
            selectedCategory = nil
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
            // A pill from the previous result set may no longer apply to this one.
            selectedCategory = nil
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
        selectedCategory = nil
        suppressNextQueryChange = true
        query = result.name
    }

    func clearSelection() {
        searchTask?.cancel()
        selectedDestination = nil
        results = []
        selectedCategory = nil
        suppressNextQueryChange = true
        query = ""
    }
}
