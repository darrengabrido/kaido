import SwiftUI

/// Shown when the app opens a Ride Together invite link. Previews the destination and route
/// before anyone joins, and requires explicit consent — joining always means live location
/// sharing starts immediately, and this screen is where that's disclosed.
struct GroupRideJoinPreviewView: View {
    let link: GroupRideInviteLink
    let onJoined: () -> Void
    let onDismiss: () -> Void

    @Environment(GroupRideSessionStore.self) private var sessionStore
    @State private var preview: GroupRideInvitePreview?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isJoining = false
    @State private var isPromptingDisplayName = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Ride Together")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onDismiss() }
                    }
                }
        }
        .task { await loadPreview() }
        .sheet(isPresented: $isPromptingDisplayName) {
            GroupRideDisplayNamePromptView(
                title: String(localized: "What should riders call you?"),
                message: String(localized: "This name is only shown to riders in this group, for this ride."),
                onSubmit: { name in
                    isPromptingDisplayName = false
                    Task { await join(displayName: name) }
                },
                onCancel: { isPromptingDisplayName = false }
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading invite…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            errorState(errorMessage)
        } else if let preview {
            previewContent(preview)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.statusCritical)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Try Again") { Task { await loadPreview() } }
                .buttonStyle(.bordered)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func previewContent(_ preview: GroupRideInvitePreview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(preview.destinationName)
                        .font(.title2.bold())
                    Text("Hosted by \(preview.hostDisplayName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    statChip(
                        value: formattedDistance(preview.routeSnapshot.distanceMeters),
                        label: String(localized: "distance")
                    )
                    statChip(
                        value: formattedDuration(preview.routeSnapshot.expectedDurationSeconds),
                        label: String(localized: "est. time")
                    )
                    statChip(
                        value: "\(preview.activeMemberCount)/\(preview.maxMembers)",
                        label: String(localized: "riders")
                    )
                }

                if preview.status.isTerminal {
                    terminalBanner(preview.status)
                }

                locationDisclosure

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Color.statusCritical)
                }

                joinButton(preview)
                    .padding(.top, 4)
            }
            .padding(20)
        }
    }

    private func statChip(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.kaidoInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func terminalBanner(_ status: GroupRideStatus) -> some View {
        Text(status == .ended ? "This group ride has ended." : "This group ride was cancelled.")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.statusCritical)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.statusCritical.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private var locationDisclosure: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "location.fill")
                .foregroundStyle(Color.kaidoVioletOnMap)
            Text("Joining shares your live location with this group while you're navigating together. It stops the moment you leave or the ride ends.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.kaidoViolet.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func joinButton(_ preview: GroupRideInvitePreview) -> some View {
        Button {
            if GroupRideDisplayNameStore.current != nil {
                Task { await join(displayName: GroupRideDisplayNameStore.current ?? "Rider") }
            } else {
                isPromptingDisplayName = true
            }
        } label: {
            if isJoining {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Text("Join Ride Together")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.kaidoViolet)
        .controlSize(.large)
        .disabled(isJoining || preview.status.isTerminal)
    }

    private func loadPreview() async {
        isLoading = true
        errorMessage = nil
        do {
            preview = try await sessionStore.previewInvite(rideId: link.rideId, token: link.token)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func join(displayName: String) async {
        isJoining = true
        errorMessage = nil
        do {
            try await sessionStore.joinRide(rideId: link.rideId, token: link.token, displayName: displayName)
            onJoined()
        } catch {
            errorMessage = error.localizedDescription
        }
        isJoining = false
    }

    private func formattedDistance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: max(seconds, 60)) ?? ""
    }
}
