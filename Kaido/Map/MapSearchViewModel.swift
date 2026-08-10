import Foundation
import CoreLocation

/// Which field a typed query and picked result apply to. Search state (query/results) stays
/// singular — only one field is ever being edited at a time — this just says which one.
enum SearchTarget {
    case origin
    case destination
}

@Observable
@MainActor
final class MapSearchViewModel {
    var query = ""
    var results: [SearchResult] = []
    var isSearching = false
    var searchError: String?
    var selectedDestination: SearchResult?
    /// `nil` means "current location" — the implicit default routing already assumed before
    /// this field existed. An explicit `SearchResult` here means the rider chose a real start.
    var selectedOrigin: SearchResult?
    var activeTarget: SearchTarget = .destination
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
        switch activeTarget {
        case .origin: selectedOrigin = result
        case .destination: selectedDestination = result
        }
        results = []
        suppressNextQueryChange = true
        query = result.name
    }

    func clearSelection() {
        searchTask?.cancel()
        selectedDestination = nil
        selectedOrigin = nil
        activeTarget = .destination
        results = []
        suppressNextQueryChange = true
        query = ""
    }

    /// Wipes the query/results without touching either selected place — for the search field's
    /// "x" button while mid-edit, which must not silently clear an already-picked destination.
    func resetQuery() {
        searchTask?.cancel()
        query = ""
        results = []
        isSearching = false
        searchError = nil
    }

    /// Enters origin-search mode, seeding the query with whatever origin is already set so
    /// re-opening the field to tweak it doesn't start blank.
    func beginEditingOrigin() {
        searchTask?.cancel()
        activeTarget = .origin
        results = []
        suppressNextQueryChange = true
        query = selectedOrigin?.name ?? ""
    }

    /// Only meaningful once origin is an explicit place — "Current Location" has no coordinate
    /// of its own to hand the destination slot, so swapping stays a no-op until then.
    func swapOriginAndDestination() {
        guard let origin = selectedOrigin, let destination = selectedDestination else { return }
        selectedOrigin = destination
        selectedDestination = origin
    }
}
