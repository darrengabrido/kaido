import Foundation

/// Drives the Routes tab's "Community" section. `load()` is cheap and idempotent since today's
/// `CommunityRouteService` is just an in-memory bundled catalog, but the loading/error surface
/// still behaves like a real network fetch so swapping in a backend-driven service later is a
/// drop-in change.
@Observable
@MainActor
final class CommunityRoutesViewModel {
    var routes: [CommunityRoute] = []
    var isLoading = false
    var errorMessage: String?

    private let service: CommunityRouteService
    private var hasLoaded = false

    init(service: CommunityRouteService = CuratedCommunityRouteService()) {
        self.service = service
    }

    /// Fetches once per view model lifetime — safe to call from `.task {}` every time the
    /// Community section appears without re-fetching on every tab switch. Call `refresh()`
    /// directly (e.g. from a pull-to-refresh) to force a reload.
    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await refresh()
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            routes = try await service.fetchCuratedRoutes()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
