import Foundation
import SwiftUI
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

    enum PasswordStrength: Int, Comparable {
        case weak, fair, strong

        static func < (lhs: PasswordStrength, rhs: PasswordStrength) -> Bool { lhs.rawValue < rhs.rawValue }

        var label: String {
            switch self {
            case .weak: return "Weak"
            case .fair: return "Fair"
            case .strong: return "Strong"
            }
        }

        var color: Color {
            switch self {
            case .weak: return .statusCritical
            case .fair: return .statusCaution
            case .strong: return .statusGood
            }
        }
    }

    var mode: Mode = .signIn {
        didSet {
            errorMessage = nil
            pendingEmailConfirmation = false
            resetLinkSent = false
        }
    }

    var email = ""
    var password = ""
    var confirmPassword = ""
    var isLoading = false
    var errorMessage: String?
    var pendingEmailConfirmation = false

    var isSendingResetLink = false
    var resetLinkSent = false

    /// `nil` while the field is empty (no error yet), otherwise a user-facing message.
    var emailError: String? {
        guard !email.isEmpty else { return nil }
        return isEmailValid ? nil : "Enter a valid email address"
    }

    var passwordError: String? {
        guard !password.isEmpty else { return nil }
        return password.count >= 6 ? nil : "Use at least 6 characters"
    }

    var confirmPasswordError: String? {
        guard mode == .signUp, !confirmPassword.isEmpty else { return nil }
        return confirmPassword == password ? nil : "Passwords don't match"
    }

    var passwordStrength: PasswordStrength {
        var score = 0
        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        if password.range(of: "[0-9]", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "[^a-zA-Z0-9]", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "[A-Z]", options: .regularExpression) != nil,
           password.range(of: "[a-z]", options: .regularExpression) != nil {
            score += 1
        }
        switch score {
        case 0...1: return .weak
        case 2...3: return .fair
        default: return .strong
        }
    }

    private var isEmailValid: Bool {
        email.contains("@") && email.contains(".") && email.count > 4
    }

    var isValid: Bool {
        guard isEmailValid, password.count >= 6 else { return false }
        guard mode == .signUp else { return true }
        return confirmPassword == password
    }

    /// Clears transient state before showing the email form for a fresh attempt.
    func reset() {
        errorMessage = nil
        pendingEmailConfirmation = false
        resetLinkSent = false
    }

    func submit() async {
        guard let client = KaidoSupabaseClient.shared else {
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
            DebugLog.shared.log("\(mode == .signIn ? "Sign in" : "Sign up") failed: \(error.localizedDescription)", category: "Auth")
            errorMessage = error.localizedDescription
        }
    }

    /// Sends a password-recovery email via Supabase's hosted flow. The link opens a
    /// Supabase-hosted page rather than deep-linking back into Kaido, since the app doesn't
    /// yet register a URL scheme for auth callbacks.
    func sendPasswordReset() async {
        guard let client = KaidoSupabaseClient.shared else {
            errorMessage = Self.notConfiguredMessage
            return
        }
        guard isEmailValid else {
            errorMessage = "Enter your account email first"
            return
        }
        isSendingResetLink = true
        errorMessage = nil
        defer { isSendingResetLink = false }

        do {
            try await client.auth.resetPasswordForEmail(email)
            resetLinkSent = true
        } catch {
            DebugLog.shared.log("Password reset failed: \(error.localizedDescription)", category: "Auth")
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func signInWithApple(idToken: String, nonce: String) async -> Bool {
        guard let client = KaidoSupabaseClient.shared else {
            errorMessage = Self.notConfiguredMessage
            return false
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            _ = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
            )
            return true
        } catch {
            DebugLog.shared.log("Sign in with Apple failed: \(error.localizedDescription)", category: "Auth")
            errorMessage = Self.friendlyAppleSignInMessage(for: error)
            return false
        }
    }

    /// Supabase rejects Apple's id_token server-side when its `aud` (the app's bundle ID)
    /// isn't listed in the Apple provider's Client IDs, surfacing as
    /// "Unacceptable audience in id_token: [...]" — a message that names an internal
    /// claim rather than the fix, so it's rewritten here to point at the actual cause.
    /// See README.md § "Enabling sign-in" step 3.
    private static func friendlyAppleSignInMessage(for error: Error) -> String {
        let description = error.localizedDescription
        guard description.localizedCaseInsensitiveContains("unacceptable audience") else {
            return description
        }
        return "Apple sign-in isn't fully set up on the server yet. In the Supabase dashboard, go to "
            + "Authentication → Providers → Apple and add \"com.oaktreehouse.kaido\" to Client IDs."
    }

    private static let notConfiguredMessage =
        "Sign-in isn't configured yet. Add your Supabase credentials to Config/Secrets.xcconfig."
}
