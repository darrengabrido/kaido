import SwiftUI

/// The bottom drawer on the map screen, resizable by dragging its header.
///
/// The point of this being its own view is where the drag state lives. `@GestureState` updates
/// on every touch-move, and whichever view owns it has its body re-evaluated that often — so
/// when the gesture lived in `MapboxMapView`, a drag re-ran a ~1,200-line body at screen
/// refresh rate, rebuilding the drawer's contents, its Liquid Glass material, and the map
/// chrome each time. That is what made the drag stutter.
///
/// Here, the header and content arrive already built and are stored as-is, so a drag re-runs
/// only this small body and re-applies a transform to them. `MapboxMapView` no longer
/// participates in the gesture at all; it hears about the drawer once, when the drag settles.
///
/// A system sheet with `presentationDetents` would get the same isolation for free, plus real
/// momentum — but sheets present modally over the whole screen, and this app keeps a tab bar
/// below the map, which a sheet would cover.
struct ResizableMapDrawer<Header: View, Content: View>: View {
    let detents: [CGFloat]

    /// The settled height. Written only when a drag ends — never mid-gesture, which is what
    /// keeps the parent out of the per-frame path.
    @Binding var height: CGFloat

    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    @GestureState private var dragTranslation: CGFloat = 0

    private var minHeight: CGFloat { detents.first ?? 190 }
    private var maxHeight: CGFloat { detents.last ?? 560 }

    /// Live height during a drag, including overscroll resistance past either end.
    private var resolvedHeight: CGFloat {
        let proposed = height - dragTranslation
        if proposed < minHeight { return minHeight - (minHeight - proposed) * 0.16 }
        if proposed > maxHeight { return maxHeight + (proposed - maxHeight) * 0.16 }
        return proposed
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                // Simultaneous so controls inside the header still take their own taps.
                .simultaneousGesture(dragGesture)

            ScrollView {
                content
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity)
        // Laid out once at full height and moved with a transform. Resizing the frame instead
        // would re-lay-out the contents — and re-rasterise the glass — on every frame.
        .frame(height: maxHeight)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .offset(y: maxHeight - resolvedHeight)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                // Throw to wherever the flick was heading, not to where the finger stopped.
                snap(to: height - value.predictedEndTranslation.height)
            }
    }

    private func snap(to proposed: CGFloat) {
        let clamped = min(max(proposed, minHeight), maxHeight)
        let nearest = detents.min { abs($0 - clamped) < abs($1 - clamped) } ?? height
        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.86, blendDuration: 0.18)) {
            height = nearest
        }
    }
}
