import Foundation
import Auth
import Supabase

@Observable
@MainActor
final class AuthViewModel {
    enum Mode: CaseIterable {
        case signIn, signUp

        var title: String {
            switch self {
            case .signIn: return "Sign In"
            case .signUp: return "Sign Up"
            }
        }

        var actionTitle: String {
            switch self {
            case .signIn: return "Sign In"
            case .signUp: return "Create Account"
            }
        }
    }

    var mode: Mode = .signIn {
        didSet {
            errorMessage = nil
            pendingEmailConfirmation = false
        }
    }

    var email = ""
    var password = ""
    var isLoading = false
    var errorMessage: String?
    var pendingEmailConfirmation = false

    var isValid: Bool {
        email.contains("@") && email.count > 3 && password.count >= 6
    }

    /// Clears transient state before showing the email form for a fresh attempt.
    func reset() {
        errorMessage = nil
        pendingEmailConfirmation = false
    }

    func submit() async {
        guard let client = VectorSupabaseClient.shared else {
            errorMessage = Self.notConfiguredMessage
            return
        }
        isLoading = true
        errorMessage = nil
        pendingEmailConfirmation = false
        defer { isLoading = false }

        do {
            switch mode {
            case .signIn:
                _ = try await client.auth.signIn(email: email, password: password)
            case .signUp:
                let response = try await client.auth.signUp(email: email, password: password)
                if case .user = response {
                    pendingEmailConfirmation = true
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signInWithApple(idToken: String) async {
        guard let client = VectorSupabaseClient.shared else {
            errorMessage = Self.notConfiguredMessage
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            _ = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static let notConfiguredMessage =
        "Sign-in isn't configured yet. Add your Supabase credentials to Config/Secrets.xcconfig."
}
