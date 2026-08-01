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

            TextField("Your name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(submit)
                .accessibilityLabel("Your display name for this ride")

            Button {
                submit()
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.kaidoViolet)
            .disabled(trimmedName.isEmpty)

            Button("Cancel", role: .cancel) { onCancel() }
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .task { isFocused = true }
    }

    private func submit() {
        guard !trimmedName.isEmpty else { return }
        onSubmit(trimmedName)
    }
}
