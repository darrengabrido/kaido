import Foundation

struct GroupRideInviteLink: Sendable, Equatable {
    let rideId: UUID
    let token: String
}

/// Parses an incoming Ride Together invite link — either the custom-scheme development fallback
/// or a future universal link once an associated domain is configured. See
/// `GroupRideInviteLinkBuilder` for how these are produced.
enum GroupRideInviteParser {
    static func parse(_ url: URL) -> GroupRideInviteLink? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }

        if url.scheme?.lowercased() == "kaido", url.host?.lowercased() == "ride-together" {
            guard components.path == "/join" else { return nil }
            return link(from: components.queryItems, rideIdKey: "ride", tokenKey: "token")
        }

        if url.scheme?.lowercased() == "https", let host = url.host, isConfiguredAssociatedDomain(host) {
            let segments = url.pathComponents.filter { $0 != "/" }
            guard segments.count >= 2, segments[0] == "ride", let rideId = UUID(uuidString: segments[1]),
                  let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
                  !token.isEmpty
            else { return nil }
            return GroupRideInviteLink(rideId: rideId, token: token)
        }

        return nil
    }

    private static func link(
        from queryItems: [URLQueryItem]?,
        rideIdKey: String,
        tokenKey: String
    ) -> GroupRideInviteLink? {
        guard let rideIdString = queryItems?.first(where: { $0.name == rideIdKey })?.value,
              let rideId = UUID(uuidString: rideIdString),
              let token = queryItems?.first(where: { $0.name == tokenKey })?.value,
              !token.isEmpty
        else { return nil }
        return GroupRideInviteLink(rideId: rideId, token: token)
    }

    /// No associated domain is configured for this project (see `docs/RideTogether.md`) — this
    /// always returns `false` today. Kept as its own seam so wiring one up later is a one-line
    /// change here rather than a change to the parsing logic above.
    private static func isConfiguredAssociatedDomain(_ host: String) -> Bool {
        false
    }
}
