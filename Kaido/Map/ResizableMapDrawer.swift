import SwiftUI

/// The map screen's bottom drawer: full-bleed glass, three detents, one canonical position.
///
/// The body is laid out once at full height and revealed by moving the whole surface — never
/// rebuilt, rescaled, or repositioned piece by piece. What's below the screen edge is simply
/// clipped away, so collapsing to compact leaves the header sitting on the bottom edge like a
/// search bar rather than a shortened panel.
///
/// Gesture state lives here rather than in the map screen. `@GestureState`-style updates
/// re-evaluate the body of whichever view owns them on every touch-move, and the map screen's
/// body is large enough that doing so at refresh rate is what made an earlier version stutter.
/// Here a drag re-runs only this view and the small control stack that reads `progress`.
struct ResizableMapDrawer<Header: View, Content: View>: View {
    let model: MapDrawerModel
    /// Called when a gesture or programmatic move should settle the drawer, so the caller owns
    /// the animation and SwiftUI can interrupt an in-flight spring with the next drag.
    let onSettle: (MapDrawerModel.Detent) -> Void
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private static var topCornerRadius: CGFloat { 30 }

    /// Square along the bottom and sides — the drawer is flush to those edges — and rounded
    /// only where it meets the map.
    private var surfaceShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: Self.topCornerRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: Self.topCornerRadius
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(maxWidth: .infinity)
                .background(headerHeightReader)
                .contentShape(Rectangle())
                // The header is the drag surface in every state.
                .gesture(drawerDrag)

            scrollingBody
        }
        .frame(maxWidth: .infinity, alignment: .top)
        // Laid out once at full height; position comes from the transform below. Resizing the
        // frame instead would re-lay-out the contents and re-rasterise the glass every frame.
        .frame(height: model.fullHeight, alignment: .top)
        .background(surface)
        .clipShape(surfaceShape)
        // Radius is fixed on purpose. Animating a shadow's radius re-renders the blur every
        // frame, which is one of the most expensive things you can do during a drag; only the
        // opacity varies, and that composites on the GPU for free.
        .shadow(color: .black.opacity(0.22), radius: 16, y: -2)
        .offset(y: max(model.fullHeight - model.height, 0))
    }

    // MARK: Body

    private var scrollingBody: some View {
        ScrollView {
            content
                // Keeps the last row clear of the bottom edge once the drawer is tall enough
                // for the content to reach it.
                .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        // Below full the drawer owns vertical gestures outright, so the body can't steal them.
        .scrollDisabled(model.detent != .full)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            model.bodyScrollOffset = offset
        }
        // At full, a downward drag that starts with the body already at its top collapses the
        // drawer instead of rubber-banding the scroll view.
        .simultaneousGesture(bodyDrag)
    }

    private var headerHeightReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { model.updateHeaderHeight(proxy.size.height) }
                .onChange(of: proxy.size.height) { _, height in
                    model.updateHeaderHeight(height)
                }
        }
    }

    // MARK: Gestures

    private var drawerDrag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                // Ignore incidental horizontal movement — this is a vertical control.
                guard abs(value.translation.height) > abs(value.translation.width) * 0.6 else { return }
                if dismissKeyboardIfDraggingDown(value.translation.height) { return }
                model.beginDrag()
                model.drag(translation: value.translation.height)
            }
            .onEnded { value in
                guard model.isDragging else { return }
                onSettle(
                    model.endDrag(
                        predictedTranslation: value.predictedEndTranslation.height,
                        velocity: value.velocity.height
                    )
                )
            }
    }

    /// Only takes over when the scroll view has nothing left to give: at full height, already
    /// at the top, and heading down. Otherwise the body scrolls normally.
    private var bodyDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard shouldBodyDragMoveDrawer(translation: value.translation.height) else { return }
                if dismissKeyboardIfDraggingDown(value.translation.height) { return }
                model.beginDrag()
                model.drag(translation: value.translation.height)
            }
            .onEnded { value in
                guard model.isDragging else { return }
                onSettle(
                    model.endDrag(
                        predictedTranslation: value.predictedEndTranslation.height,
                        velocity: value.velocity.height
                    )
                )
            }
    }

    private func shouldBodyDragMoveDrawer(translation: CGFloat) -> Bool {
        guard abs(translation) > 0 else { return false }
        // Below full the scroll view is disabled, so every drag here is the drawer's.
        guard model.detent == .full else { return true }
        // Already dragging — keep ownership so the hand-off can't flicker mid-gesture.
        if model.isDragging { return true }
        return translation > 0 && model.bodyScrollOffset <= 0.5
    }

    /// A downward drag with the keyboard up dismisses the keyboard first, and leaves the drawer
    /// where it is.
    private func dismissKeyboardIfDraggingDown(_ translation: CGFloat) -> Bool {
        guard translation > 0, model.isKeyboardVisible else { return false }
        model.isSearchFocused = false
        return true
    }

    // MARK: Surface

    /// One primary glass surface, with the scrim and edge highlight layered over it.
    ///
    /// Every layer here is painted with *constant* colours and varied only through `.opacity`.
    /// That distinction is the whole performance story: changing the alpha inside a fill or
    /// gradient is a new paint, so the layer re-rasterises on every frame of a drag — over
    /// Liquid Glass, that is ruinous. `.opacity` on an already-rendered layer is a GPU
    /// composite, so the same visual result costs nothing to animate.
    @ViewBuilder
    private var surface: some View {
        if reduceTransparency {
            surfaceShape.fill(Color.kaidoMidnight.opacity(0.97))
        } else {
            ZStack {
                surfaceShape
                    .fill(.clear)
                    .glassEffect(.regular, in: surfaceShape)

                // Adaptive scrim — barely there at compact, enough at full to hold contrast
                // over bright map tiles.
                surfaceShape
                    .fill(Color.kaidoMidnight)
                    .opacity(0.10 + 0.22 * model.progress)

                // Specular highlight along the top edge and into the corners. Constant paint;
                // only its opacity tracks expansion.
                surfaceShape
                    .stroke(Self.highlightGradient, lineWidth: 1)
                    .mask(Self.highlightMask)
                    .opacity(0.6 + 0.4 * model.progress)
            }
        }
    }

    /// Hoisted to static so the gradient and mask are built once rather than per frame.
    private static let highlightGradient = LinearGradient(
        colors: [Color.white.opacity(0.34), Color.white.opacity(0.06), .clear],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Only the top edge should read as lit — the sides and bottom run off screen and shouldn't
    /// show a border.
    private static let highlightMask = LinearGradient(
        colors: [.white, .white.opacity(0.25), .clear],
        startPoint: .top,
        endPoint: .center
    )
}
