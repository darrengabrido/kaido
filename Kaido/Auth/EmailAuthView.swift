import SwiftUI

/// Second-step email/password form, presented as a sheet over the landing hero.
struct EmailAuthView: View {
    @Bindable var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    private enum Field {
        case email, password
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Mode", selection: $viewModel.mode) {
                    ForEach(AuthViewModel.Mode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                VStack(spacing: 12) {
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
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if viewModel.pendingEmailConfirmation {
                    Label("Check your email to confirm your account, then sign in.",
                          systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.routeTeal)
                }

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
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(viewModel.mode.title)
        .safeAreaInset(edge: .top) {
            header
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack {
            Text(viewModel.mode == .signUp ? "Create your account" : "Welcome back")
                .font(.title2.bold())
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

    private func field<Content: View>(
        icon: String,
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
    }

    private func submit() {
        focusedField = nil
        Task { await viewModel.submit() }
    }
}

#Preview {
    EmailAuthView(viewModel: AuthViewModel())
}
