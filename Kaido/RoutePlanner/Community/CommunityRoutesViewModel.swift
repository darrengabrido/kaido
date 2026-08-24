import Foundation

/// Drives the Routes tab's "Community" section: browsing, publishing one of the rider's own
/// saved routes, and removing one they previously published.
@Observable
@MainActor
final class CommunityRoutesViewModel {
    var routes: [CommunityRoute] = []
    var isLoading = false
    var errorMessage: String?

    /// `nil` until the first `refresh()` resolves — deliberately never forces a sign-in just to
    /// figure out ownership, so browsing stays possible with no session at all. Until it resolves,
    /// `isMine` conservatively reports `false` for everything.
    private(set) var currentUserId: UUID?

    private let service: CommunityRouteService
    private let identityProvider: GroupRideIdentityProvider
    private var hasLoaded = false

    init(
        service: CommunityRouteService = CompositeCommunityRouteService(),
        identityProvider: GroupRideIdentityProvider = SupabaseGroupRideIdentityProvider()
    ) {
        self.service = service
        self.identityProvider = identityProvider
    }

    /// Fetches once per view model lifetime — safe to call from `.task {}` every time the
    /// Community section appears without re-fetching on every tab switch. Call `refresh()`
    /// directly (e.g. from a pull-to-refresh, or right after publishing/removing) to force a reload.
    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await refresh()
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        currentUserId = await identityProvider.currentUserId()
        do {
            routes = try await service.fetchPublished(limit: 100)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func isMine(_ route: CommunityRoute) -> Bool {
        guard let currentUserId else { return false }
        return currentUserId == route.authorUserId
    }

    @discardableResult
    func publish(from route: Route, description: String?, displayName: String) async throws -> CommunityRoute {
        let waypoints = route.orderedWaypoints.map {
            CommunityRoute.Waypoint(latitude: $0.latitude, longitude: $0.longitude, order: $0.order)
        }
        let published = try await service.publish(
            name: route.name,
            description: description,
            distanceMeters: route.distanceMeters,
            elevationGainMeters: route.elevationGainMeters,
            waypoints: waypoints,
            displayName: displayName
        )
        routes.insert(published, at: 0)
        return published
    }

    func remove(_ route: CommunityRoute) async throws {
        try await service.remove(routeId: route.id)
        routes.removeAll { $0.id == route.id }
    }
}
