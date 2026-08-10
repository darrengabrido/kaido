import Foundation

enum CommunityRouteServiceError: LocalizedError, Equatable {
    case notConfigured
    case notAuthenticated
    case notOwner
    case server(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return String(localized: "Community routes aren't configured yet.")
        case .notAuthenticated:
            return String(localized: "You need to be signed in (or continue as a guest) to share a route.")
        case .notOwner:
            return String(localized: "You can only remove a route you published.")
        case .server(let message):
            return message
        case .decoding:
            return String(localized: "Couldn't read the server's response. Try again.")
        }
    }
}

/// Supplies and manages the routes shown in the Routes tab's "Community" section: browsing,
/// publishing one of the rider's own saved routes, and removing one they previously published.
protocol CommunityRouteService: Sendable {
    func fetchPublished(limit: Int) async throws -> [CommunityRoute]

    func publish(
        name: String,
        description: String?,
        distanceMeters: Double,
        elevationGainMeters: Double,
        waypoints: [CommunityRoute.Waypoint],
        displayName: String
    ) async throws -> CommunityRoute

    func remove(routeId: UUID) async throws
}

/// Always-available seed content bundled with the app (see `CuratedCommunityRoutes`) — no
/// network, no Supabase dependency. Read-only: there's no backend row behind a curated route, so
/// `publish`/`remove` aren't meaningful operations here and simply fail with `.notConfigured`.
/// `CompositeCommunityRouteService` (what the app actually injects by default) is what layers a
/// real backend's `publish`/`remove` on top of this catalog.
struct CuratedCommunityRouteService: CommunityRouteService {
    func fetchPublished(limit: Int) async throws -> [CommunityRoute] {
        Array(CuratedCommunityRoutes.all.prefix(limit))
    }

    func publish(
        name: String,
        description: String?,
        distanceMeters: Double,
        elevationGainMeters: Double,
        waypoints: [CommunityRoute.Waypoint],
        displayName: String
    ) async throws -> CommunityRoute {
        throw CommunityRouteServiceError.notConfigured
    }

    func remove(routeId: UUID) async throws {
        throw CommunityRouteServiceError.notConfigured
    }
}

/// The service `CommunityRoutesViewModel` actually uses: the bundled curated catalog is always
/// shown (so the feed is never empty, even offline or before any rider has published a route),
/// with whatever's been published to Supabase — if configured — appended after it. Publishing and
/// removing always go straight to the backend; a curated route was never "published" through this
/// service in the first place, so there's nothing for those calls to do with it.
struct CompositeCommunityRouteService: CommunityRouteService {
    private let curated: CommunityRouteService
    private let backend: CommunityRouteService

    init(
        curated: CommunityRouteService = CuratedCommunityRouteService(),
        backend: CommunityRouteService = SupabaseCommunityRouteService()
    ) {
        self.curated = curated
        self.backend = backend
    }

    func fetchPublished(limit: Int) async throws -> [CommunityRoute] {
        let curatedRoutes = try await curated.fetchPublished(limit: limit)
        let backendRoutes: [CommunityRoute]
        do {
            backendRoutes = try await backend.fetchPublished(limit: limit)
        } catch CommunityRouteServiceError.notConfigured {
            backendRoutes = []
        }
        return curatedRoutes + backendRoutes
    }

    func publish(
        name: String,
        description: String?,
        distanceMeters: Double,
        elevationGainMeters: Double,
        waypoints: [CommunityRoute.Waypoint],
        displayName: String
    ) async throws -> CommunityRoute {
        try await backend.publish(
            name: name,
            description: description,
            distanceMeters: distanceMeters,
            elevationGainMeters: elevationGainMeters,
            waypoints: waypoints,
            displayName: displayName
        )
    }

    func remove(routeId: UUID) async throws {
        try await backend.remove(routeId: routeId)
    }
}
