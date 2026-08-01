import SwiftUI

/// Compact participant-count control shown during active navigation. Tapping it reveals the
/// full `GroupRideParticipantSheet`. Deliberately small and glanceable — this sits alongside
/// Mapbox's own banners and must not compete with maneuver instructions.
struct GroupRideGroupControlPill: View {
    @Environment(GroupRideSessionStore.self) private var sessionStore
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(activeMemberCount)")
                    .font(.subheadline.weight(.semibold))
                Circle()
                    .fill(connectionColor)
                    .frame(width: 6, height: 6)
            }
            .foregroundStyle(Color.kaidoInk)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: Capsule())
        .accessibilityLabel("Ride Together, \(activeMemberCount) riders")
        .accessibilityHint("Opens the group ride panel")
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
}
