import Foundation
import Supabase

struct GroupRideIdentity: Sendable, Equatable {
    let userId: UUID
    /// Whether this is a Supabase anonymous-auth session rather than a permanent account —
    /// used to decide whether the display-name prompt should present as "you're browsing as a
    /// guest" copy rather than implying a real account was just created.
    let isAnonymous: Bool
}

enum GroupRideIdentityError: LocalizedError {
    case notConfigured
    case signInFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return String(localized: "Ride Together isn't configured yet.")
        case .signInFailed(let message):
            return message
        }
    }
}

/// Resolves the Supabase identity Ride Together should act as, reusing the app's one shared
/// `KaidoSupabaseClient` and its existing session (guest or permanent) rather than standing up a
/// second, competing auth store.
///
/// A rider who is fully signed in (or already has an anonymous session from a previous Ride
/// Together use) is reused as-is. A rider in guest mode with no session at all gets a
/// transparent anonymous Supabase session created on first use — this is scoped to the group
/// feature's need for a stable `auth.uid()` for RLS, never presented as account creation, and
/// never overwrites an existing permanent session.
protocol GroupRideIdentityProvider: Sendable {
    func ensureIdentity() async throws -> GroupRideIdentity
    func currentUserId() async -> UUID?
}

struct SupabaseGroupRideIdentityProvider: GroupRideIdentityProvider {
    private let client: SupabaseClient?

    init(client: SupabaseClient? = KaidoSupabaseClient.shared) {
        self.client = client
    }

    func currentUserId() async -> UUID? {
        guard let client else { return nil }
        return try? await client.auth.session.user.id
    }

    func ensureIdentity() async throws -> GroupRideIdentity {
        guard let client else { throw GroupRideIdentityError.notConfigured }

        if let session = try? await client.auth.session {
            return GroupRideIdentity(userId: session.user.id, isAnonymous: session.user.isAnonymous)
        }

        do {
            let session = try await client.auth.signInAnonymously()
            return GroupRideIdentity(userId: session.user.id, isAnonymous: session.user.isAnonymous)
        } catch {
            throw GroupRideIdentityError.signInFailed(error.localizedDescription)
        }
    }
}
