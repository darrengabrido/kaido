import SwiftUI

/// Pre-start group ride screen: destination/route preview, host, participants, invite sharing,
/// and Start/Cancel (host) or Leave (rider). Also doubles as the transition screen once the ride
/// goes active — `onStartNavigating` fires for host and riders alike the moment
/// `sessionStore.ride?.status` becomes `.active`, whether that's this device tapping Start or a
/// remote status notice arriving for someone who joined an already-active ride.
struct GroupRideLobbyView: View {
    let onStartNavigating: () -> Void
    let onDismiss: () -> Void

    @Environment(GroupRideSessionStore.self) private var sessionStore
    @State private var rawInviteToken: String?
    @State private var isConfirmingCancel = false
    @State private var isConfirmingLeave = false
    @State private var isStarting = false
    @State private var actionError: String?

    init(initialRawInviteToken: String?, onStartNavigating: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self._rawInviteToken = State(initialValue: initialRawInviteToken)
        self.onStartNavigating = onStartNavigating
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Ride Together")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(sessionStore.isHost ? "Cancel" : "Leave") {
                            if sessionStore.isHost {
                                isConfirmingCancel = true
                            } else {
                                isConfirmingLeave = true
                            }
                        }
                    }
                }
        }
        .onChange(of: sessionStore.ride?.status) { _, status in
            handleStatusChange(status)
        }
        .onAppear { handleStatusChange(sessionStore.ride?.status) }
        .confirmationDialog(
            "Cancel this group ride for everyone?",
            isPresented: $isConfirmingCancel,
            titleVisibility: .visible
        ) {
            Button("Cancel Ride", role: .destructive) {
                Task {
                    try? await sessionStore.cancelRide()
                    onDismiss()
                }
            }
        }
        .confirmationDialog("Leave the lobby?", isPresented: $isConfirmingLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) {
                Task {
                    try? await sessionStore.leaveRide()
                    onDismiss()
                }
            }
        }
    }

    private func handleStatusChange(_ status: GroupRideStatus?) {
        switch status {
        case .active:
            onStartNavigating()
        case .ended, .cancelled:
            onDismiss()
            sessionStore.clearSession()
        case .lobby, nil:
            break
        }
    }

    @ViewBuilder
    private var content: some View {
        if let ride = sessionStore.ride {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    destinationSummary(ride)
                    participantsSection

                    if let actionError {
                        Text(actionError)
                            .font(.caption)
                            .foregroundStyle(Color.statusCritical)
                    }

                    shareInviteSection(ride)

                    if sessionStore.isHost {
                        startButton
                    } else {
                        Text("Waiting for the host to start the ride…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(20)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func destinationSummary(_ ride: GroupRide) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ride.destinationName)
                .font(.title2.bold())

            HStack(spacing: 12) {
                statChip(
                    value: formattedDistance(ride.routeSnapshot.distanceMeters),
                    label: String(localized: "distance")
                )
                statChip(
                    value: formattedDuration(ride.routeSnapshot.expectedDurationSeconds),
                    label: String(localized: "est. time")
                )
                statChip(
                    value: "\(sessionStore.members.filter(\.isActive).count)/\(ride.maxMembers)",
                    label: String(localized: "riders")
                )
            }
        }
    }

    private func statChip(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 17, weight: .semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.kaidoInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var participantsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RIDERS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.kaidoDim)

            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(sessionStore.members.filter(\.isActive)) { member in
                        VStack(spacing: 6) {
                            Circle()
                                .fill(GroupRideAvatarStyle.color(for: member.avatarSeed))
                                .frame(width: 52, height: 52)
                                .overlay {
                                    Text(GroupRideAvatarStyle.initials(for: member.displayName))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                }
                                .overlay {
                                    if member.isHost {
                                        Circle().stroke(Color.kaidoVioletOnMap, lineWidth: 2)
                                    }
                                }
                            Text(member.displayName)
                                .font(.caption2)
                                .lineLimit(1)
                                .frame(width: 60)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(member.isHost ? "\(member.displayName), host" : member.displayName)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func shareInviteSection(_ ride: GroupRide) -> some View {
        if let rawInviteToken {
            ShareLink(
                item: GroupRideInviteLinkBuilder.makeLink(rideId: ride.id, token: rawInviteToken),
                subject: Text("Ride Together"),
                message: Text("Join my ride on Kaido")
            ) {
                Label("Share Invite", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(.kaidoViolet)
        } else if sessionStore.isHost {
            Button {
                Task { await generateInvite() }
            } label: {
                Label("Generate Invite Link", systemImage: "link")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(.kaidoViolet)
        }
    }

    private var startButton: some View {
        Button {
            Task {
                isStarting = true
                actionError = nil
                do {
                    try await sessionStore.startRide()
                } catch {
                    actionError = error.localizedDescription
                }
                isStarting = false
            }
        } label: {
            if isStarting {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Text("Start Ride Together")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.kaidoViolet)
        .controlSize(.large)
        .disabled(isStarting)
    }

    private func generateInvite() async {
        do {
            let rotation = try await sessionStore.rotateInvite()
            rawInviteToken = rotation.rawInviteToken
        } catch {
            actionError = error.localizedDescription
        }
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
