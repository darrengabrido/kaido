import SwiftUI

/// Second-step email/password form, presented as a sheet over the landing hero. Handles both
/// sign-in and sign-up behind a single animated toggle so switching intent never feels like
/// leaving the screen.
struct EmailAuthView: View {
    @Bindable var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @Namespace private var modeNamespace

    @State private var isPasswordRevealed = false
    @State private var isConfirmPasswordRevealed = false
    @State private var showForgotPassword = false

    private enum Field {
        case email, password, confirmPassword
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                modeToggle

                Text(viewModel.mode == .signUp
                     ? "Save your routes and rides across devices."
                     : "Sign in to sync your saved routes and ride history.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 14) {
                    emailField
                    passwordField

                    if viewModel.mode == .signUp {
                        confirmPasswordField
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                if viewModel.mode == .signIn {
                    forgotPasswordLink
                }

                if let errorMessage = viewModel.errorMessage {
                    banner(errorMessage, icon: "exclamationmark.triangle.fill", tint: .statusCritical)
                }

                if viewModel.pendingEmailConfirmation {
                    banner(
                        "Check your email to confirm your account, then sign in.",
                        icon: "checkmark.circle.fill",
                        tint: .statusGood
                    )
                }

                submitButton

                if viewModel.mode == .signUp {
                    Text("By creating an account, you agree to Kaido's Terms of Service and Privacy Policy.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
            .animation(.easeOut(duration: 0.2), value: viewModel.mode)
            .animation(.easeOut(duration: 0.18), value: viewModel.errorMessage)
            .animation(.easeOut(duration: 0.18), value: viewModel.pendingEmailConfirmation)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(viewModel.mode.title)
        .safeAreaInset(edge: .top) {
            header
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView(viewModel: viewModel)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text(viewModel.mode == .signUp ? "Create your account" : "Welcome back")
                .font(.title2.bold())
                .contentTransition(.opacity)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .glassEffect(.regular, in: .circle)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    // MARK: Mode toggle

    private var modeToggle: some View {
        HStack(spacing: 2) {
            ForEach(AuthViewModel.Mode.allCases, id: \.self) { mode in
                Button {
                    focusedField = nil
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        viewModel.mode = mode
                    }
                } label: {
                    Text(mode.title)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(viewModel.mode == mode ? Color.kaidoMidnight : Color.primary.opacity(0.65))
                        .background {
                            if viewModel.mode == mode {
                                Capsule()
                                    .fill(Color.kaidoInk)
                                    .matchedGeometryEffect(id: "modePill", in: modeNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: Fields

    private var emailField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldContainer(icon: "envelope", isFocused: focusedField == .email, hasError: viewModel.emailError != nil) {
                TextField("Email", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
            }

            if let error = viewModel.emailError {
                errorCaption(error)
            }
        }
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldContainer(icon: "lock", isFocused: focusedField == .password, hasError: viewModel.passwordError != nil) {
                revealableField(
                    placeholder: "Password",
                    text: $viewModel.password,
                    isRevealed: $isPasswordRevealed,
                    contentType: viewModel.mode == .signUp ? .newPassword : .password
                )
                .focused($focusedField, equals: .password)
                .submitLabel(viewModel.mode == .signUp ? .next : .go)
                .onSubmit {
                    if viewModel.mode == .signUp {
                        focusedField = .confirmPassword
                    } else {
                        submit()
                    }
                }

                revealButton(isRevealed: $isPasswordRevealed)
            }

            if let error = viewModel.passwordError {
                errorCaption(error)
            }

            if viewModel.mode == .signUp, !viewModel.password.isEmpty {
                strengthMeter
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var confirmPasswordField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldContainer(
                icon: "lock.rotation",
                isFocused: focusedField == .confirmPassword,
                hasError: viewModel.confirmPasswordError != nil
            ) {
                revealableField(
                    placeholder: "Confirm password",
                    text: $viewModel.confirmPassword,
                    isRevealed: $isConfirmPasswordRevealed,
                    contentType: .newPassword
                )
                .focused($focusedField, equals: .confirmPassword)
                .submitLabel(.go)
                .onSubmit { submit() }

                revealButton(isRevealed: $isConfirmPasswordRevealed)
            }

            if let error = viewModel.confirmPasswordError {
                errorCaption(error)
            }
        }
    }

    @ViewBuilder
    private func revealableField(
        placeholder: String,
        text: Binding<String>,
        isRevealed: Binding<Bool>,
        contentType: UITextContentType
    ) -> some View {
        Group {
            if isRevealed.wrappedValue {
                TextField(placeholder, text: text)
            } else {
                SecureField(placeholder, text: text)
            }
        }
        .textContentType(contentType)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }

    private func revealButton(isRevealed: Binding<Bool>) -> some View {
        Button {
            isRevealed.wrappedValue.toggle()
        } label: {
            Image(systemName: isRevealed.wrappedValue ? "eye.slash" : "eye")
                .foregroundStyle(.secondary)
                .frame(width: 20)
        }
        .buttonStyle(.plain)
    }

    private var strengthMeter: some View {
        let strength = viewModel.passwordStrength
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index <= strength.rawValue ? strength.color : Color.primary.opacity(0.12))
                        .frame(height: 3)
                }
            }
            Text("\(strength.label) password")
                .font(.caption2)
                .foregroundStyle(strength.color)
        }
    }

    private var forgotPasswordLink: some View {
        Button("Forgot password?") {
            viewModel.errorMessage = nil
            showForgotPassword = true
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(Color.kaidoVioletOnMap)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: Shared building blocks

    private func fieldContainer<Content: View>(
        icon: String,
        isFocused: Bool,
        hasError: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    hasError ? Color.statusCritical : (isFocused ? Color.kaidoViolet : .clear),
                    lineWidth: 1.5
                )
        }
        .animation(.easeOut(duration: 0.16), value: isFocused)
        .animation(.easeOut(duration: 0.16), value: hasError)
    }

    private func errorCaption(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(Color.statusCritical)
            .transition(.opacity)
    }

    private func banner(_ message: String, icon: String, tint: Color) -> some View {
        Label(message, systemImage: icon)
            .font(.caption)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .transition(.opacity)
    }

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    Text(viewModel.mode.actionTitle)
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
        }
        .buttonStyle(.glassProminent)
        .tint(.kaidoViolet)
        .disabled(viewModel.isLoading || !viewModel.isValid)
        .padding(.top, 4)
    }

    private func submit() {
        focusedField = nil
        Task { await viewModel.submit() }
    }
}

#Preview {
    EmailAuthView(viewModel: AuthViewModel())
}
