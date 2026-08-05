import SwiftUI

/// Rides the lower-right map controls on top of the drawer.
///
/// Isolated into a modifier so that reading the drawer's live position re-renders only this
/// small piece. The map screen's body never reads it, so a drag doesn't rebuild the screen —
/// and the map itself never moves, which is the point: only these controls are coupled.
struct DrawerCoupledControls: ViewModifier {
    let model: MapDrawerModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Distance the stack keeps above the drawer's top edge.
    private static let clearance: CGFloat = 14

    /// Once the drawer is near full there's nowhere left to sit, so the stack fades out rather
    /// than colliding with the top safe area.
    private var opacity: CGFloat {
        let fadeStart: CGFloat = 0.72
        guard model.progress > fadeStart else { return 1 }
        return max(0, 1 - (model.progress - fadeStart) / (1 - fadeStart))
    }

    func body(content: Content) -> some View {
        content
            .offset(y: -(model.height + Self.clearance))
            .opacity(opacity)
            // Non-interactive once faded, so invisible controls can't take taps.
            .allowsHitTesting(opacity > 0.15)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : nil, value: model.height)
    }
}
