import SwiftUI
import CoreLocation

/// Compact card shown when a rider's marker is tapped. Deliberately shows only an approximate
/// distance and a freshness label — never exact coordinates.
struct GroupRideRiderCardView: View {
    let member: GroupRideMember
    let location: GroupRideParticipantLocation?
    let freshness: GroupRideMarkerFreshness?
    let distanceFromMe: CLLocationDistance?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Circle()
                    .fill(GroupRideAvatarStyle.color(for: member.avatarSeed))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Text(GroupRideAvatarStyle.initials(for: member.displayName))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(member.displayName)
                            .font(.headline)
                        if member.isHost {
                            Text("HOST")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.kaidoVioletOnMap)
                        }
                    }
                    Text(freshnessLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if let course = location?.courseDegrees {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.kaidoDim)
                        .rotationEffect(.degrees(course))
                        .accessibilityHidden(true)
                }
            }

            if let distanceFromMe {
                Text("About \(formattedDistance(distanceFromMe)) away")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .accessibilityElement(children: .combine)
    }

    private var freshnessLabel: String {
        switch freshness {
        case .fresh, .none:
            return String(localized: "Live")
        case .stale:
            return String(localized: "Signal delayed")
        case .expired:
            return String(localized: "Last seen a moment ago")
        }
    }

    private func formattedDistance(_ meters: CLLocationDistance) -> String {
        Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))
    }
}
