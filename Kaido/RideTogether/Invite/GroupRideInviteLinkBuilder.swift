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
    ///
    /// Builds the query string by hand rather than assigning `"«redacted»"` through
    /// `URLComponents.queryItems` and reading back `.url` — `URLComponents` percent-encodes query
    /// item values (the guillemets become `%C2%AB…%C2%BB`), which would make this string no
    /// longer contain the literal `«redacted»` placeholder callers and tests look for.
    static func redacted(_ url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems, !queryItems.isEmpty else {
            return url.absoluteString
        }

        var withoutQuery = components
        withoutQuery.queryItems = nil
        guard let prefix = withoutQuery.url?.absoluteString else {
            return "«redacted invite link»"
        }

        let redactedQuery = queryItems.map { item -> String in
            guard item.name == "token" else {
                let value = item.value?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                return "\(item.name)=\(value)"
            }
            return "\(item.name)=«redacted»"
        }.joined(separator: "&")

        return "\(prefix)?\(redactedQuery)"
    }
}
