import SwiftUI

/// Floating pill offering to re-run the active search around wherever the rider just panned to —
/// same move Google Maps offers once the visible map drifts away from the current results.
struct SearchThisAreaButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Search this area", systemImage: "arrow.clockwise")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.kaidoInk)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .accessibilityHint("Searches again using the area currently shown on the map")
    }
}
