import SwiftUI
import AuthenticationServices

/// Landing / hero screen. Leads with brand identity and the two lowest-friction paths
/// (Sign in with Apple, Continue as guest), and reveals email/password on a second step.
struct AuthGateView: View {
    @Environment(AuthState.self) private var authState
    @State private var viewModel = AuthViewModel()
    @State private var showEmailAuth = false
    @State private var appear = false

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                hero
                Spacer(minLength: 0)
                Spacer(minLength: 0)
                actions
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
            .padding(.top, 60)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showEmailAuth) {
            EmailAuthView(viewModel: viewModel)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { appear = true }
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 22) {
            Image(systemName: "bicycle")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 104, height: 104)
                .glassEffect(.regular, in: .rect(cornerRadius: 30))
                .shadow(color: .vectorViolet.opacity(0.45), radius: 24, y: 8)
                .scaleEffect(appear ? 1 : 0.85)

            VStack(spacing: 10) {
                Text("Vector")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Your intelligent ride companion")
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 16)
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.email, .fullName]
            } onCompletion: { result in
                handleAppleCompletion(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .disabled(viewModel.isLoading)

            Button {
                viewModel.reset()
                showEmailAuth = true
            } label: {
                Label("Continue with email", systemImage: "envelope.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .buttonStyle(.glass)
            .foregroundStyle(.white)

            Button("Continue as guest") {
                authState.continueAsGuest()
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.7))
            .padding(.top, 6)
        }
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 24)
    }

    // MARK: Apple sign-in

    private func handleAppleCompletion(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                viewModel.errorMessage = "Apple didn't return a usable sign-in token."
                return
            }
            Task { await viewModel.signInWithApple(idToken: idToken) }
        case .failure(let error):
            guard (error as? ASAuthorizationError)?.code != .canceled else { return }
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

/// A slow-drifting mesh gradient blending indigo-violet into the brand teal over a near-black base,
/// giving the landing screen a living, high-impact backdrop.
private struct AuroraBackground: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                    [0.0, 0.5],
                    [drift(t, 0.31, 0.5, 0.18), drift(t, 0.24, 0.5, 0.18)],
                    [1.0, 0.5],
                    [0.0, 1.0],
                    [drift(t, 0.19, 0.5, 0.12), 1.0],
                    [1.0, 1.0]
                ],
                colors: [
                    // Monochromatic violet aurora — Instrument keeps the brand backdrop a single
                    // hue story rather than mixing in a second accent.
                    .vectorMidnight, .vectorIndigo, .vectorMidnight,
                    .vectorViolet, .vectorIndigo, .vectorVioletOnMap,
                    .vectorMidnight, .vectorVioletOnMap.opacity(0.6), .vectorMidnight
                ]
            )
        }
        .overlay(
            LinearGradient(
                colors: [.clear, .vectorMidnight.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )
        )
        .ignoresSafeArea()
    }

    /// A value oscillating around `center` by `amount`, at the given `speed`.
    private func drift(_ t: TimeInterval, _ speed: Double, _ center: Double, _ amount: Double) -> Float {
        Float(center + amount * sin(t * speed))
    }
}

#Preview {
    AuthGateView()
        .environment(AuthState())
}
