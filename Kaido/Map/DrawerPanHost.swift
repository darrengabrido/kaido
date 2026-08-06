import SwiftUI
import UIKit

/// Drives the map drawer's position from UIKit instead of SwiftUI.
///
/// Every frame of a SwiftUI `DragGesture` goes through view-tree diffing, and over a live Mapbox
/// surface that is enough to make a drag visibly uneven no matter how cheap the drawn content
/// is. Here a `UIPanGestureRecognizer` moves a layout constraint on a hosted view, so
/// intermediate positions never reach SwiftUI's update cycle at all — the same reason the system
/// sheet felt right, without a sheet's habit of covering the tab bar.
///
/// It also removes the gesture conflict that stopped compact being reachable: with two SwiftUI
/// gestures arbitrating against the scroll view's own recogniser, drags were being truncated and
/// their end position landed short of the bottom detent. One recogniser, with an explicit
/// hand-off rule, decides.
struct DrawerPanHost<Header: View, Content: View>: UIViewControllerRepresentable {
    let model: MapDrawerModel
    let reduceMotion: Bool
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    func makeUIViewController(context: Context) -> DrawerPanController<Header, Content> {
        DrawerPanController(model: model, rootView: surface)
    }

    func updateUIViewController(_ controller: DrawerPanController<Header, Content>, context: Context) {
        controller.reduceMotion = reduceMotion
        controller.update(rootView: surface)
    }

    private var surface: DrawerSurface<Header, Content> {
        DrawerSurface(model: model, header: { header }, content: { content })
    }
}

final class DrawerPanController<Header: View, Content: View>: UIViewController, UIGestureRecognizerDelegate {
    private let model: MapDrawerModel
    private let host: UIHostingController<DrawerSurface<Header, Content>>
    private var topConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    private var animator: UIViewPropertyAnimator?
    private var dragStartHeight: CGFloat = 0
    var reduceMotion = false

    init(model: MapDrawerModel, rootView: DrawerSurface<Header, Content>) {
        self.model = model
        self.host = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(rootView: DrawerSurface<Header, Content>) {
        host.rootView = rootView
        syncToModelIfIdle()
    }

    override func loadView() {
        // Only the drawer itself should take touches; everything above it belongs to the map.
        view = PassthroughView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let top = host.view.topAnchor.constraint(equalTo: view.topAnchor)
        let height = host.view.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            top,
            height
        ])
        topConstraint = top
        heightConstraint = height

        (view as? PassthroughView)?.contentView = host.view

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.delegate = self
        host.view.addGestureRecognizer(pan)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        model.updateGeometry(usableHeight: view.bounds.height, bottomSafeArea: 0)
        heightConstraint?.constant = model.fullHeight
        syncToModelIfIdle()
    }

    /// Keeps the constraint in step with the model when nothing is being dragged or animated —
    /// covers programmatic moves like tapping search or picking a destination, which set the
    /// model directly and never touch the pan.
    private func syncToModelIfIdle() {
        guard animator?.isRunning != true, !model.isDragging else { return }
        let target = max(view.bounds.height - model.height, 0)
        guard let topConstraint, abs(topConstraint.constant - target) > 0.5 else { return }

        // A first layout has nothing to animate from; anything later is a deliberate move.
        guard view.window != nil, topConstraint.constant != 0 || model.height > 0 else {
            topConstraint.constant = target
            return
        }
        animator?.stopAnimation(true)
        let animator = UIViewPropertyAnimator(
            duration: reduceMotion ? 0.22 : 0.42,
            timingParameters: reduceMotion
                ? UICubicTimingParameters(animationCurve: .easeOut)
                : UISpringTimingParameters(dampingRatio: 0.92)
        )
        animator.addAnimations { [weak self] in
            topConstraint.constant = target
            self?.view.layoutIfNeeded()
        }
        animator.startAnimation()
        self.animator = animator
    }

    private func setTop(for height: CGFloat, animated: Bool) {
        let constant = max(view.bounds.height - height, 0)
        guard let topConstraint, topConstraint.constant != constant else { return }
        topConstraint.constant = constant
        if animated { view.layoutIfNeeded() }
    }

    // MARK: Pan

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        let translation = pan.translation(in: view).y
        let velocity = pan.velocity(in: view).y

        switch pan.state {
        case .began:
            animator?.stopAnimation(true)
            animator = nil
            dragStartHeight = model.height
            model.beginDrag()

        case .changed:
            // Dragging down with the keyboard up dismisses the keyboard and leaves the drawer.
            if translation > 0, model.isKeyboardVisible {
                model.isSearchFocused = false
                return
            }
            model.drag(translation: translation)
            // Direct constraint write — no SwiftUI layout pass for the intermediate positions.
            setTop(for: model.height, animated: false)

        case .ended, .cancelled, .failed:
            let projected = translation + velocity * 0.12
            let detent = model.endDrag(predictedTranslation: projected, velocity: velocity)
            settle(to: detent, velocity: velocity)

        default:
            break
        }
    }

    private func settle(to detent: MapDrawerModel.Detent, velocity: CGFloat) {
        let target = model.height(for: detent)
        model.settle(to: detent)

        let distance = abs(target - (view.bounds.height - (topConstraint?.constant ?? 0)))
        // Carry the flick's speed into the spring so the hand-off has no visible discontinuity.
        let initial = distance > 0 ? min(abs(velocity) / distance, 12) : 0

        animator?.stopAnimation(true)
        let timing: UITimingCurveProvider = reduceMotion
            ? UICubicTimingParameters(animationCurve: .easeOut)
            : UISpringTimingParameters(
                dampingRatio: 0.92,
                initialVelocity: CGVector(dx: 0, dy: initial)
              )
        let animator = UIViewPropertyAnimator(duration: reduceMotion ? 0.22 : 0.42, timingParameters: timing)
        animator.addAnimations { [weak self] in
            self?.setTop(for: target, animated: true)
        }
        animator.startAnimation()
        self.animator = animator
    }

    // MARK: Scroll hand-off

    /// The drawer and the body's scroll view share vertical drags, so they must recognise
    /// together — the decision about who actually moves is made in `gestureRecognizerShouldBegin`.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        other is UIPanGestureRecognizer && other.view is UIScrollView
    }

    /// Below full, the drawer always wins. At full, the body scrolls until it's back at its top
    /// and the drag is heading down — only then does the drawer take over.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let translation = pan.translation(in: view).y
        // Horizontal intent isn't ours.
        guard abs(translation) >= abs(pan.translation(in: view).x) else { return false }
        guard model.detent == .full else { return true }
        guard let scrollView = bodyScrollView else { return true }
        return translation > 0 && scrollView.contentOffset.y <= scrollView.adjustedContentInset.top + 0.5
    }

    private var bodyScrollView: UIScrollView? {
        var stack: [UIView] = [host.view]
        while let candidate = stack.popLast() {
            if let scrollView = candidate as? UIScrollView { return scrollView }
            stack.append(contentsOf: candidate.subviews)
        }
        return nil
    }
}

/// Lets touches outside the drawer reach the map behind it.
private final class PassthroughView: UIView {
    weak var contentView: UIView?

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard let contentView else { return false }
        return contentView.frame.contains(point)
    }
}
