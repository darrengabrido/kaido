import SwiftUI

/// Lightweight password-recovery flow, presented from the sign-in form. Sends the reset link
/// through Supabase's hosted flow — the rider finishes choosing a new password in the browser,
/// since Kaido doesn't yet register a URL scheme for auth callbacks.
struct ForgotPasswordView: View {
    @Bindable var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isEmailFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            if viewModel.resetLinkSent {
                confirmation
            } else {
                form
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear { isEmailFocused = true }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reset your password")
                    .font(.title2.bold())
                Text("We'll email you a link to choose a new one.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "envelope")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                TextField("Email", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isEmailFocused)
                    .submitLabel(.send)
                    .onSubmit { send() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.statusCritical)
            }

            Button {
                send()
            } label: {
                Group {
                    if viewModel.isSendingResetLink {
                        ProgressView()
                    } else {
                        Text("Send reset link")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
            }
            .buttonStyle(.glassProminent)
            .tint(.kaidoViolet)
            .disabled(viewModel.isSendingResetLink || viewModel.email.isEmpty)
            .padding(.top, 4)
        }
        .animation(.easeOut(duration: 0.18), value: viewModel.errorMessage)
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Check \(viewModel.email) for a reset link.", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.statusGood)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.statusGood.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
            }
            .buttonStyle(.glassProminent)
            .tint(.kaidoViolet)
        }
        .transition(.opacity)
    }

    private func send() {
        Task { await viewModel.sendPasswordReset() }
    }
}

#Preview {
    ForgotPasswordView(viewModel: AuthViewModel())
}
