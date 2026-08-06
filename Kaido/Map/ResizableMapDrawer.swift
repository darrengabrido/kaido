import SwiftUI

/// Built once and reused, so a drag doesn't rebuild them every frame.
///
/// These live outside the generic drawer type because Swift doesn't allow static stored
/// properties in a generic type.
private enum DrawerHighlight {
    /// Specular sheen along the top edge and into the corners.
    static let gradient = LinearGradient(
        colors: [Color.white.opacity(0.34), Color.white.opacity(0.06), .clear],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Only the top edge should read as lit — the sides and bottom run off screen and shouldn't
    /// show a border.
    static let mask = LinearGradient(
        colors: [.white, .white.opacity(0.25), .clear],
        startPoint: .top,
        endPoint: .center
    )
}

/// The drawer's appearance: full-bleed glass, rounded only where it meets the map, laid out once
/// at full height with the body below a pinned header.
///
/// Deliberately has no gesture and no offset. `DrawerPanHost` positions it with a UIKit
/// constraint, because routing a drag through SwiftUI means every intermediate position pays for
/// view-tree diffing — which is what kept this stuttering over a live map.
struct DrawerSurface<Header: View, Content: View>: View {
    let model: MapDrawerModel
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var surfaceShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 30,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 30
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(maxWidth: .infinity)
                // Compact wraps this exactly, so the measurement has to land on the layout pass
                // that produces it.
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    model.updateHeaderHeight(height)
                }

            ScrollView {
                content
                    .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(surface)
        .clipShape(surfaceShape)
        // Fixed radius: animating a shadow's blur re-renders it every frame.
        .shadow(color: .black.opacity(0.22), radius: 16, y: -2)
    }

    /// One primary glass surface. Every layer paints a *constant* colour and varies only through
    /// `.opacity` — changing alpha inside a fill is a new paint, so the layer re-rasterises,
    /// whereas `.opacity` on a rendered layer is a GPU composite.
    @ViewBuilder
    private var surface: some View {
        if reduceTransparency {
            surfaceShape.fill(Color.kaidoMidnight.opacity(0.97))
        } else {
            ZStack {
                surfaceShape
                    .fill(.clear)
                    .glassEffect(.regular, in: surfaceShape)

                surfaceShape
                    .fill(Color.kaidoMidnight)
                    .opacity(0.10 + 0.22 * model.progress)

                surfaceShape
                    .stroke(DrawerHighlight.gradient, lineWidth: 1)
                    .mask(DrawerHighlight.mask)
                    .opacity(0.6 + 0.4 * model.progress)
            }
        }
    }
}
