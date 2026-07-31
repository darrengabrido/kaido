import Foundation
import Auth
import Supabase

@Observable
@MainActor
final class AuthState {
    private(set) var session: Session?
    private(set) var isLoading = true

    private(set) var isGuest: Bool {
        didSet { UserDefaults.standard.set(isGuest, forKey: Self.guestKey) }
    }

    private static let guestKey = "kaido.continuedAsGuest"

    var isAuthenticated: Bool { session != nil }
    var shouldShowGate: Bool { !isLoading && session == nil && !isGuest }
    var user: User? { session?.user }

    init() {
        isGuest = UserDefaults.standard.bool(forKey: Self.guestKey)
    }

    func start() async {
        guard let client = KaidoSupabaseClient.shared else {
            isLoading = false
            return
        }
        for await (_, session) in client.auth.authStateChanges {
            self.session = session
            if session != nil {
                isGuest = false
            }
            isLoading = false
        }
    }

    func continueAsGuest() {
        isGuest = true
    }

    func exitGuestMode() {
        isGuest = false
    }

    func signOut() async throws {
        try await KaidoSupabaseClient.shared?.auth.signOut()
        session = nil
        isGuest = false
    }
}
