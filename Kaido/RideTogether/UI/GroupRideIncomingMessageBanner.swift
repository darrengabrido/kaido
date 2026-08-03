import SwiftUI

/// Nonmodal incoming-message banner. Positioned by the caller (`NavigationSessionView`) so it
/// never obscures Mapbox's own maneuver banner — `GroupRideMessageCenter` guarantees only one
/// banner is ever current at a time, queueing the rest.
struct GroupRideIncomingMessageBanner: View {
    let message: GroupRideMessage
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.kaidoViolet)
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: "bubble.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(message.senderDisplayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.kaidoVioletOnMap)
                Text(message.body)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.kaidoInk)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss message")
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.senderDisplayName) says \(message.body)")
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
