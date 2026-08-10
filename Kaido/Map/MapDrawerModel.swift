import SwiftUI

/// Canonical state for the map screen's bottom drawer.
///
/// There is exactly one vertical position — `height` — and both the gesture and the rendering
/// read it, so they can never disagree. Detents are derived from the live viewport rather than
/// hard-coded, so the drawer sits correctly on any device.
///
/// This is `@Observable` on purpose. `height` changes every frame during a drag, and with
/// observation only the views that actually *read* it re-render: the drawer itself and the
/// small map-control stack. The map screen's own body never touches `height`, so it stays out
/// of the per-frame path — the thing that made the earlier hand-rolled drawer stutter.
@Observable
@MainActor
final class MapDrawerModel {
    enum Detent: Int, CaseIterable, Comparable {
        case compact, medium, full

        static func < (lhs: Detent, rhs: Detent) -> Bool { lhs.rawValue < rhs.rawValue }

        var accessibilityName: String {
            switch self {
            case .compact: String(localized: "Compact")
            case .medium: String(localized: "Medium")
            case .full: String(localized: "Expanded")
            }
        }
    }

    // MARK: Geometry, supplied by the map screen from its GeometryReader

    /// Height available to the screen, excluding the top safe area.
    private(set) var usableHeight: CGFloat = 0
    private(set) var bottomSafeArea: CGFloat = 0
    /// Measured height of the search header, so compact can wrap it exactly rather than guess.
    private(set) var headerHeight: CGFloat = 0

    // MARK: Canonical position

    /// Distance from the bottom edge of the screen to the top of the drawer. The single source
    /// of truth for where the drawer is, mid-drag and at rest alike.
    private(set) var height: CGFloat = 0
    private(set) var detent: Detent = .medium
    private(set) var dragVelocity: CGFloat = 0

    /// Content offset of the body's scroll view. Drives gesture hand-off at full height.
    var bodyScrollOffset: CGFloat = 0
    var isSearchFocused = false
    var isKeyboardVisible = false

    /// True once geometry has arrived; the drawer shouldn't render or animate before that.
    var isReady: Bool { usableHeight > 0 }

    // MARK: Detent heights

    /// Wraps the search header and the bottom safe area, nothing else — the drawer should read
    /// as a bottom search bar here, not as a shortened panel.
    var compactHeight: CGFloat {
        // Measured rather than assumed, so the collapse wraps the header exactly and leaves no
        // dead panel beneath the search bar. The fallback only applies for the first frame,
        // before the header has reported its size.
        let header = headerHeight > 0 ? headerHeight : 96
        return header + bottomSafeArea + 14
    }

    /// The drawer's top edge sits this far down the usable height, so the fraction is measured
    /// from the top of the screen and the drawer occupies what's left below it.
    private static let defaultMediumTopFraction: CGFloat = 0.40

    /// Place details uses a higher fraction so the resting card leaves more map visible.
    /// `nil` restores the search/browse medium height.
    var mediumTopFractionOverride: CGFloat? {
        didSet {
            guard oldValue != mediumTopFractionOverride, !isDragging else { return }
            if detent == .medium {
                height = mediumHeight
            }
        }
    }

    private var mediumTopFraction: CGFloat {
        mediumTopFractionOverride ?? Self.defaultMediumTopFraction
    }

    var mediumHeight: CGFloat {
        max(compactHeight, usableHeight * (1 - mediumTopFraction))
    }

    /// Rests immediately below the top safe area.
    var fullHeight: CGFloat { max(mediumHeight, usableHeight) }

    func height(for detent: Detent) -> CGFloat {
        switch detent {
        case .compact: compactHeight
        case .medium: mediumHeight
        case .full: fullHeight
        }
    }

    /// 0 at compact, 1 at full. Drives glass tint, edge highlight, shadow, and the map
    /// controls' translation and opacity, so they all move from one number.
    var progress: CGFloat {
        let span = fullHeight - compactHeight
        guard span > 0 else { return 0 }
        return min(max((height - compactHeight) / span, 0), 1)
    }

    // MARK: Updates

    func updateGeometry(usableHeight: CGFloat, bottomSafeArea: CGFloat) {
        let wasReady = isReady
        self.usableHeight = usableHeight
        self.bottomSafeArea = bottomSafeArea
        // Keep the resting position correct through rotation and split-view resizes.
        if !wasReady || !isDragging {
            height = height(for: detent)
        }
    }

    func updateHeaderHeight(_ value: CGFloat) {
        guard value > 0, abs(value - headerHeight) > 0.5 else { return }
        headerHeight = value
        if !isDragging, detent == .compact {
            height = compactHeight
        }
    }

    private(set) var isDragging = false
    private var dragStartHeight: CGFloat = 0

    func beginDrag() {
        guard !isDragging else { return }
        isDragging = true
        dragStartHeight = height
    }

    /// Follows the finger 1:1, with resistance once past either end. No easing while the finger
    /// is down — the drawer is under direct manipulation.
    func drag(translation: CGFloat) {
        guard isDragging else { return }
        let proposed = dragStartHeight - translation
        height = rubberBanded(proposed)
    }

    private func rubberBanded(_ proposed: CGFloat) -> CGFloat {
        if proposed < compactHeight { return compactHeight - (compactHeight - proposed) * 0.55 }
        if proposed > fullHeight { return fullHeight + (proposed - fullHeight) * 0.55 }
        return proposed
    }

    /// A deliberate flick past this speed advances one detent; anything slower settles on
    /// whichever detent the projected position is nearest.
    private static let flickVelocity: CGFloat = 420

    /// - Returns: the detent to settle on. The caller animates `height` to it, so the spring
    ///   stays in the view layer where SwiftUI can interrupt it.
    func endDrag(predictedTranslation: CGFloat, velocity: CGFloat) -> Detent {
        isDragging = false
        dragVelocity = velocity

        let target: Detent
        if abs(velocity) > Self.flickVelocity {
            // Upward drag is negative translation, and raises the drawer.
            target = velocity < 0 ? adjacent(to: detent, rising: true)
                                  : adjacent(to: detent, rising: false)
        } else {
            let projected = rubberBanded(dragStartHeight - predictedTranslation)
            target = nearestDetent(to: projected)
        }
        detent = target
        return target
    }

    /// Ordinary gestures move between neighbours; compact never jumps straight to full.
    private func adjacent(to detent: Detent, rising: Bool) -> Detent {
        let next = detent.rawValue + (rising ? 1 : -1)
        return Detent(rawValue: min(max(next, 0), Detent.allCases.count - 1)) ?? detent
    }

    func nearestDetent(to value: CGFloat) -> Detent {
        Detent.allCases.min { abs(height(for: $0) - value) < abs(height(for: $1) - value) } ?? detent
    }

    /// Moves the drawer programmatically — tapping search, picking a destination. The caller
    /// wraps this in the animation it wants.
    func settle(to detent: Detent) {
        self.detent = detent
        height = height(for: detent)
    }

    func step(_ direction: AccessibilityAdjustmentDirection) -> Detent? {
        let target: Detent
        switch direction {
        case .increment: target = adjacent(to: detent, rising: true)
        case .decrement: target = adjacent(to: detent, rising: false)
        @unknown default: return nil
        }
        guard target != detent else { return nil }
        return target
    }
}
