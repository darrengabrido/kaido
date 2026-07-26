import SwiftUI
import AuthenticationServices

struct AuthGateView: View {
    @Environment(AuthState.self) private var authState
    @State private var viewModel = AuthViewModel()
    @FocusState private var focusedField: Field?

    private enum Field {
        case email, password
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                credentialsCard
                divider
                appleButton
                guestButton
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "bicycle")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(Color.routeTeal)
            Text("Vector")
                .font(.largeTitle.bold())
            Text("Ride navigation built for ebikes")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }

    private var credentialsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Mode", selection: $viewModel.mode) {
                ForEach(AuthViewModel.Mode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            field(icon: "envelope") {
                TextField("Email", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
            }

            field(icon: "lock") {
                SecureField("Password", text: $viewModel.password)
                    .textContentType(viewModel.mode == .signUp ? .newPassword : .password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { submit() }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if viewModel.pendingEmailConfirmation {
                Text("Check your email to confirm your account, then sign in.")
                    .font(.caption)
                    .foregroundStyle(Color.routeTeal)
            }

            Button {
                submit()
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(viewModel.mode.actionTitle)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.glassProminent)
            .tint(.goGreen)
            .disabled(viewModel.isLoading || !viewModel.isValid)
        }
        .padding()
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
    }

    private func field<Content: View>(
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    private var divider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(.secondary.opacity(0.3)).frame(height: 1)
            Text("or")
                .font(.caption)
                .foregroundStyle(.secondary)
            Rectangle().fill(.secondary.opacity(0.3)).frame(height: 1)
        }
    }

    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = [.email, .fullName]
        } onCompletion: { result in
            handleAppleCompletion(result)
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .disabled(viewModel.isLoading)
    }

    private var guestButton: some View {
        Button("Continue as Guest") {
            authState.continueAsGuest()
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private func submit() {
        focusedField = nil
        Task { await viewModel.submit() }
    }

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

#Preview {
    AuthGateView()
        .environment(AuthState())
        .preferredColorScheme(.dark)
}
