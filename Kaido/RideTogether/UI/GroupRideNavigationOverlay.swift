import SwiftUI

/// Hosts every piece of Ride Together's active-navigation chrome — the group control pill,
/// participant sheet, quick messages, incoming banner, and tapped-rider card — as one child
/// `UIHostingController` added by `NavigationSessionView`, alongside Mapbox's own banners. Laid
/// out to keep clear of the bottom banner region so an incoming message never obscures a
/// maneuver instruction.
struct GroupRideNavigationOverlay: View {
    let overlayController: GroupRideMapOverlayController

    @Environment(GroupRideSessionStore.self) private var sessionStore
    @State private var isPresentingParticipants = false
    @State private var isPresentingQuickMessages = false
    @State private var selectedMemberId: UUID?
    @State private var shareURL: URL?

    var body: some View {
        VStack {
            HStack {
                Spacer()
                GroupRideGroupControlPill { isPresentingParticipants = true }
            }
            .padding(.trailing, 12)
            .padding(.top, 8)

            Spacer()

            if let banner = sessionStore.messageCenter.currentBanner {
                GroupRideIncomingMessageBanner(message: banner) {
                    sessionStore.messageCenter.dismissCurrentBanner()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 150)
            }
        }
        .onChange(of: sessionStore.messageCenter.currentBanner) { _, banner in
            guard let banner else { return }
            RideAudioCoordinator.shared.speakIncomingMessageIfEnabled(
                sender: banner.senderDisplayName,
                body: banner.body
            )
        }
        .onAppear {
            overlayController.onSelectMember = { memberId in selectedMemberId = memberId }
        }
        .sheet(isPresented: $isPresentingParticipants) {
            GroupRideParticipantSheet(
                shareURL: shareURL,
                onPrepareShare: { Task { await prepareShare() } },
                onOpenQuickMessages: {
                    isPresentingParticipants = false
                    isPresentingQuickMessages = true
                },
                onShowGroup: {
                    guard let destination = sessionStore.ride?.routeSnapshot.destinationCoordinate else { return }
                    overlayController.showGroup(destination: destination)
                }
            )
        }
        .sheet(isPresented: $isPresentingQuickMessages) {
            GroupRideQuickMessageSheet()
        }
        .sheet(item: riderCardBinding) { member in
            GroupRideRiderCardView(
                member: member,
                location: sessionStore.participantLocations.locationsByMemberId[member.id],
                freshness: sessionStore.participantLocations.freshness(for: member.id),
                distanceFromMe: nil
            )
            .presentationDetents([.height(200)])
        }
    }

    private var riderCardBinding: Binding<GroupRideMember?> {
        Binding(
            get: {
                guard let selectedMemberId else { return nil }
                return sessionStore.members.first { $0.userId == selectedMemberId }
            },
            set: { newValue in
                if newValue == nil { selectedMemberId = nil }
            }
        )
    }

    private func prepareShare() async {
        guard let ride = sessionStore.ride else { return }
        guard let rotation = try? await sessionStore.rotateInvite() else { return }
        shareURL = GroupRideInviteLinkBuilder.makeLink(rideId: ride.id, token: rotation.rawInviteToken)
    }
}
