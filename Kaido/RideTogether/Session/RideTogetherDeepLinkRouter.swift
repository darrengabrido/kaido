import Foundation

/// Bridges `onOpenURL` (app-wide, no view-owned target — see `MediaPlayerManager`'s identical
/// need for the Spotify callback) into a Ride Together join-preview presentation.
@Observable
@MainActor
final class RideTogetherDeepLinkRouter {
    private(set) var pendingInvite: GroupRideInviteLink?

    func handle(_ url: URL) {
        guard let link = GroupRideInviteParser.parse(url) else { return }
        pendingInvite = link
    }

    func clearPendingInvite() {
        pendingInvite = nil
    }
}
