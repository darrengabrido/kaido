import Foundation

/// Supplies the routes shown in the Routes tab's "Community" section.
///
/// `CuratedCommunityRouteService` is the only conformer today — a small, hand-picked catalog
/// bundled with the app (see `CuratedCommunityRoutes`), with no network or Supabase dependency.
/// The protocol still returns `async throws` so a later backend-driven catalog (admin-curated or,
/// eventually, user-submitted) can be swapped in without any change to `CommunityRoutesViewModel`
/// or the views built on top of it.
protocol CommunityRouteService: Sendable {
    func fetchCuratedRoutes() async throws -> [CommunityRoute]
}

struct CuratedCommunityRouteService: CommunityRouteService {
    func fetchCuratedRoutes() async throws -> [CommunityRoute] {
        CuratedCommunityRoutes.all
    }
}
