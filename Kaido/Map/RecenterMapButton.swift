import SwiftUI

/// Circular glass control that restores puck-following after the user pans the map.
struct RecenterMapButton: View {
    let isFollowing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isFollowing ? "location.fill" : "location")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isFollowing ? Color.kaidoVioletOnMap : Color.kaidoInk)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: Circle())
        .accessibilityLabel(isFollowing ? "Following your location" : "Recenter map on your location")
        .accessibilityHint(isFollowing ? "Camera is tracking you" : "Returns the camera to your GPS position")
    }
}
