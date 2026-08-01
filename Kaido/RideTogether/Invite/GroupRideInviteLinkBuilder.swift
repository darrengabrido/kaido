import Foundation

/// Builds and redacts Ride Together invite links.
///
/// Kaido has no associated domain configured for universal links yet (see
/// `docs/RideTogether.md` for exactly what's needed to add one), so invites use the app's
/// existing custom URL scheme as a development-friendly fallback:
///
///     kaido://ride-together/join?ride=<ride-id>&token=<invite-token>
///
/// Once an associated domain exists, only this file needs to change to emit
///
///     https://<associated-domain>/ride/<ride-id>?token=<invite-token>
///
/// — `GroupRideInviteParser` already accepts both forms.
enum GroupRideInviteLinkBuilder {
    static func makeLink(rideId: UUID, token: String) -> URL {
        var components = URLComponents()
        components.scheme = "kaido"
        components.host = "ride-together"
        components.path = "/join"
        components.queryItems = [
            URLQueryItem(name: "ride", value: rideId.uuidString),
            URLQueryItem(name: "token", value: token)
        ]
        return components.url ?? URL(string: "kaido://ride-together/join")!
    }

    /// Never pass a raw invite URL to `OSLog`/`print`/analytics — always route it through this
    /// first. Redacts the token query item only; every other component is preserved so the rest
    /// of the link is still useful in diagnostics.
    static func redacted(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return "«redacted invite link»"
        }
        components.queryItems = components.queryItems?.map { item in
            guard item.name == "token" else { return item }
            return URLQueryItem(name: item.name, value: "«redacted»")
        }
        return components.url?.absoluteString ?? "«redacted invite link»"
    }
}
