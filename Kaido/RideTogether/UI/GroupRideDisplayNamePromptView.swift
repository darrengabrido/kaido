import SwiftUI

/// Requests a short, temporary display name for Ride Together — shown whenever one isn't already
/// remembered on this device. Never presented as account registration: this name is used only
/// for the group ride feature, independent of any permanent Kaido account.
struct GroupRideDisplayNamePromptView: View {
    let title: String
    let message: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var name = GroupRideDisplayNameStore.current ?? ""
    @FocusState private var isFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.bold())
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            field

            Button {
                submit()
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
            }
            .buttonStyle(.glassProminent)
            .tint(.kaidoViolet)
            .disabled(trimmedName.isEmpty)

            Button("Cancel", role: .cancel) { onCancel() }
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .task { isFocused = true }
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.fill")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            TextField("Your name", text: $name)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isFocused)
                .onSubmit(submit)
                .onChange(of: name) { _, value in
                    if value.count > GroupRideConfig.maxDisplayNameLength {
                        name = String(value.prefix(GroupRideConfig.maxDisplayNameLength))
                    }
                }
                .accessibilityLabel("Your display name for this ride")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func submit() {
        guard !trimmedName.isEmpty else { return }
        onSubmit(trimmedName)
    }
}
