import SwiftUI

/// The compact group control's expanded content: participant list with connection/freshness,
/// mute + quick-message controls, invite sharing, and leave/end — reached from
/// `GroupRideGroupControlPill` during active navigation.
struct GroupRideParticipantSheet: View {
    @Environment(GroupRideSessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss

    /// `nil` until `onPrepareShare` has rotated a fresh invite — the sheet doesn't retain a raw
    /// token across presentations, so sharing during active navigation always rotates first.
    let shareURL: URL?
    let onPrepareShare: () -> Void
    let onOpenQuickMessages: () -> Void
    /// Opens the tapped rider's compact card — triggered from the list row rather than their map
    /// marker (see `GroupRideMapOverlayController`).
    var onSelectMember: ((UUID) -> Void)?
    var onShowGroup: (() -> Void)?

    @State private var isConfirmingEnd = false
    @State private var isConfirmingLeave = false
    @State private var readMessagesAloud = GroupRideMessagingPreferences.readMessagesAloud

    var body: some View {
        NavigationStack {
            List {
                connectionSection
                participantsSection
                controlsSection
                dangerSection
            }
            .navigationTitle("Ride Together")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var connectionSection: some View {
        Section {
            HStack(spacing: 10) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 8, height: 8)
                Text(connectionLabel)
                    .font(.subheadline)
                Spacer()
                Text("\(activeMemberCount)/\(sessionStore.ride?.maxMembers ?? GroupRideConfig.defaultMaxMembers)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var participantsSection: some View {
        Section("Riders") {
            ForEach(sessionStore.members.filter(\.isActive)) { member in
                participantRow(member)
            }
        }
    }

    private func participantRow(_ member: GroupRideMember) -> some View {
        HStack(spacing: 12) {
            Button {
                onSelectMember?(member.userId)
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(GroupRideAvatarStyle.color(for: member.avatarSeed))
                        .frame(width: 32, height: 32)
                        .overlay {
                            Text(GroupRideAvatarStyle.initials(for: member.displayName))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(member.displayName)
                                .font(.subheadline.weight(.medium))
                            if member.isHost {
                                Text("HOST")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.kaidoVioletOnMap)
                            }
                        }
                        Text(statusLabel(for: member))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(member.userId == sessionStore.currentUserId)

            Spacer()

            if sessionStore.isHost, member.userId != sessionStore.currentUserId {
                Menu {
                    Button("Remove from Ride", role: .destructive) {
                        Task { try? await sessionStore.removeMember(userId: member.userId) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .accessibilityLabel("More options for \(member.displayName)")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func statusLabel(for member: GroupRideMember) -> String {
        if member.userId == sessionStore.currentUserId {
            return String(localized: "You")
        }
        guard sessionStore.onlineMemberIds.contains(member.userId) else {
            return String(localized: "Offline")
        }
        switch sessionStore.participantLocations.freshness(for: member.userId) {
        case .fresh, .none:
            return String(localized: "Online")
        case .stale:
            return String(localized: "Signal delayed")
        case .expired:
            return String(localized: "Online · last seen a moment ago")
        }
    }

    private var controlsSection: some View {
        Section {
            Button {
                onOpenQuickMessages()
            } label: {
                Label("Quick Messages", systemImage: "bubble.left.and.bubble.right.fill")
            }

            if let onShowGroup {
                Button {
                    onShowGroup()
                } label: {
                    Label("Show Group on Map", systemImage: "scope")
                }
            }

            Toggle("Read Messages Aloud", isOn: $readMessagesAloud)
                .onChange(of: readMessagesAloud) { _, newValue in
                    GroupRideMessagingPreferences.readMessagesAloud = newValue
                }

            if let shareURL {
                ShareLink(item: shareURL, subject: Text("Ride Together"), message: Text("Join my ride on Kaido")) {
                    Label("Share Invite", systemImage: "square.and.arrow.up")
                }
            } else {
                Button {
                    onPrepareShare()
                } label: {
                    Label("Share Invite", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    @ViewBuilder
    private var dangerSection: some View {
        Section {
            if sessionStore.isHost {
                Button(role: .destructive) {
                    isConfirmingEnd = true
                } label: {
                    Label("End Ride Together", systemImage: "xmark.circle.fill")
                }
                .confirmationDialog(
                    "End Ride Together for everyone?",
                    isPresented: $isConfirmingEnd,
                    titleVisibility: .visible
                ) {
                    Button("End for Everyone", role: .destructive) {
                        Task { try? await sessionStore.endRide() }
                    }
                }
            } else {
                Button(role: .destructive) {
                    isConfirmingLeave = true
                } label: {
                    Label("Leave Ride Together", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .confirmationDialog(
                    "Leave Ride Together? You can keep navigating on your own.",
                    isPresented: $isConfirmingLeave,
                    titleVisibility: .visible
                ) {
                    Button("Leave", role: .destructive) {
                        Task { try? await sessionStore.leaveRide() }
                    }
                }
            }
        }
    }

    private var activeMemberCount: Int {
        sessionStore.members.filter(\.isActive).count
    }

    private var connectionColor: Color {
        switch sessionStore.connectionState {
        case .connected: return .statusGood
        case .connecting, .reconnecting: return .statusCaution
        case .disconnected, .failed: return .statusCritical
        }
    }

    private var connectionLabel: String {
        switch sessionStore.connectionState {
        case .connected: return String(localized: "Connected")
        case .connecting: return String(localized: "Connecting…")
        case .reconnecting: return String(localized: "Reconnecting…")
        case .disconnected: return String(localized: "Disconnected")
        case .failed(let message): return message
        }
    }
}
