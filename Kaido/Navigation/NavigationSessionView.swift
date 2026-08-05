import SwiftUI
import Combine
import MapboxMaps
import MapboxNavigationCore
import MapboxNavigationUIKit
import UIKit

struct NavigationSessionView: UIViewControllerRepresentable {
    let navigationRoutes: NavigationRoutes
    let telemetry: BikeTelemetry
    let rideTimeProfile: RideTimeProfile
    /// Present only when Ride Together is active for this navigation session — `nil` (the
    /// default) reproduces solo navigation exactly as before this feature existed.
    var groupRideSessionStore: GroupRideSessionStore? = nil
    let onDismiss: (Bool) -> Void

    func makeUIViewController(context: Context) -> NavigationViewController {
        let provider = KaidoNavigationProvider.shared
        let nightStyle = StandardNightStyle()
        nightStyle.tintColor = UIColor(Color.kaidoViolet)

        let bannerModel = context.coordinator.bannerModel
        let bottomBanner = GlassBottomBannerController(model: bannerModel, telemetry: telemetry)

        let navigationOptions = NavigationOptions(
            mapboxNavigation: provider.mapboxNavigation,
            voiceController: provider.routeVoiceController,
            eventsManager: provider.eventsManager(),
            styles: [nightStyle],
            topBanner: GlassTopBannerController(model: bannerModel),
            bottomBanner: bottomBanner
        )
        let viewController = NavigationViewController(
            navigationRoutes: navigationRoutes,
            navigationOptions: navigationOptions
        )
        viewController.delegate = context.coordinator
        bottomBanner.navigationViewController = viewController
        context.coordinator.navigationViewController = viewController

        // Don't touch `viewController.view` here — loading it starts active guidance before
        // the fullScreenCover has presented (Mapbox documents this as a footgun). Install
        // chrome on the next run loop once the VC is in the hierarchy.
        DispatchQueue.main.async {
            self.addNavigationChrome(to: viewController, coordinator: context.coordinator)
            if let groupRideSessionStore, groupRideSessionStore.hasActiveRide {
                context.coordinator.attachGroupRide(sessionStore: groupRideSessionStore, to: viewController)
            }
        }
        return viewController
    }

    /// Docks the Now Playing bar and a Kaido recenter control above Mapbox's bottom banner.
    /// The stock Resume button sits on the leading edge of that same band and ends up under
    /// the media bar, so we hide it and expose our own trailing control instead.
    private func addNavigationChrome(
        to viewController: NavigationViewController,
        coordinator: Coordinator
    ) {
        Self.hideStockResumeButtons(in: viewController.view)

        // Same bike puck as the browsing/route-preview maps (BikePuckImage) — this is the view
        // that's actually on screen while GPS is driving turn-by-turn guidance.
        if let navigationMapView = viewController.navigationMapView {
            navigationMapView.puckType = .puck2D(
                Puck2DConfiguration(bearingImage: BikePuckImage.bearing, pulsing: BikePuckImage.pulsing)
            )
        }

        let barController = UIHostingController(
            rootView: MediaPlayerBar(manager: MediaPlayerManager.shared)
        )
        barController.view.backgroundColor = .clear
        barController.view.translatesAutoresizingMaskIntoConstraints = false

        let recenterController = UIHostingController(
            rootView: NavigationRecenterButton(isFollowing: true) {
                coordinator.recenterOnUser()
            }
        )
        recenterController.view.backgroundColor = .clear
        recenterController.view.translatesAutoresizingMaskIntoConstraints = false

        viewController.addChild(barController)
        viewController.addChild(recenterController)
        viewController.view.addSubview(barController.view)
        viewController.view.addSubview(recenterController.view)
        barController.didMove(toParent: viewController)
        recenterController.didMove(toParent: viewController)

        let bottomBanner = viewController.navigationView.bottomBannerContainerView
        NSLayoutConstraint.activate([
            // 12pt matches the outer inset GlassTopBanner/GlassBottomBanner apply to
            // themselves, so all three docked cards share the same edges.
            barController.view.leadingAnchor.constraint(
                equalTo: viewController.view.leadingAnchor,
                constant: 12
            ),
            barController.view.trailingAnchor.constraint(
                equalTo: viewController.view.trailingAnchor,
                constant: -12
            ),
            barController.view.bottomAnchor.constraint(
                equalTo: bottomBanner.topAnchor,
                constant: -8
            ),

            recenterController.view.trailingAnchor.constraint(
                equalTo: viewController.view.trailingAnchor,
                constant: -16
            ),
            recenterController.view.bottomAnchor.constraint(
                equalTo: barController.view.topAnchor,
                constant: -12
            ),
            recenterController.view.widthAnchor.constraint(equalToConstant: 44),
            recenterController.view.heightAnchor.constraint(equalToConstant: 44)
        ])

        let paddingProbe = NavigationPaddingProbeView()
        paddingProbe.translatesAutoresizingMaskIntoConstraints = false
        paddingProbe.onLayout = { [weak coordinator] in
            coordinator?.refreshViewportPadding()
        }
        viewController.view.insertSubview(paddingProbe, at: 0)
        NSLayoutConstraint.activate([
            paddingProbe.widthAnchor.constraint(equalToConstant: 0),
            paddingProbe.heightAnchor.constraint(equalToConstant: 0),
            paddingProbe.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
            paddingProbe.topAnchor.constraint(equalTo: viewController.view.topAnchor)
        ])

        coordinator.mediaPlayerView = barController.view
        coordinator.recenterHostingController = recenterController
        coordinator.startCameraObservation()
        coordinator.refreshViewportPadding()
    }

    func updateUIViewController(_ uiViewController: NavigationViewController, context: Context) {
        // OrnamentsController re-shows Resume whenever the camera leaves following.
        Self.hideStockResumeButtons(in: uiViewController.view)
        context.coordinator.refreshViewportPadding()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss, rideTimeProfile: rideTimeProfile)
    }

    /// `NavigationView.resumeButton` is internal to Mapbox, so we hide by type instead.
    fileprivate static func hideStockResumeButtons(in root: UIView) {
        var stack: [UIView] = [root]
        while let view = stack.popLast() {
            if view is ResumeButton {
                view.isHidden = true
                view.alpha = 0
                view.isUserInteractionEnabled = false
            }
            stack.append(contentsOf: view.subviews)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NavigationViewControllerDelegate {
        let onDismiss: (Bool) -> Void
        /// Owned here so it outlives `makeUIViewController` and stays shared by both banners.
        let bannerModel: NavigationBannerModel

        weak var navigationViewController: NavigationViewController?
        weak var mediaPlayerView: UIView?
        weak var recenterHostingController: UIHostingController<NavigationRecenterButton>?

        private var cameraCancellable: AnyCancellable?
        private var lastAppliedPadding: UIEdgeInsets?
        private var lastFollowState: Bool?

        private var groupRideSessionStore: GroupRideSessionStore?
        private var groupRideOverlayController: GroupRideMapOverlayController?
        private weak var groupRideHostingController: UIViewController?

        init(
            onDismiss: @escaping (Bool) -> Void,
            rideTimeProfile: RideTimeProfile
        ) {
            self.onDismiss = onDismiss
            bannerModel = NavigationBannerModel(rideTimeProfile: rideTimeProfile)
        }

        @MainActor
        func startCameraObservation() {
            guard let navigationMapView = navigationViewController?.navigationMapView else { return }
            cameraCancellable = navigationMapView.navigationCamera.cameraStates
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    MainActor.assumeIsolated {
                        self?.handleCameraState(state)
                    }
                }
            handleCameraState(navigationMapView.navigationCamera.currentCameraState)
        }

        @MainActor
        func recenterOnUser() {
            navigationViewController?.navigationMapView?.navigationCamera
                .update(cameraState: .following)
            if let root = navigationViewController?.view {
                NavigationSessionView.hideStockResumeButtons(in: root)
            }
        }

        /// Mapbox's padding accounts for the glass banners but not the Spotify bar docked
        /// above them. Without the extra inset the follow camera parks the puck under that bar.
        @MainActor
        func refreshViewportPadding() {
            guard let navigationViewController,
                  let navigationMapView = navigationViewController.navigationMapView
            else { return }

            let navigationView = navigationViewController.navigationView
            let safe = navigationMapView.safeAreaInsets
            let topBannerHeight = navigationView.topBannerContainerView.bounds.height
            let bottomBannerHeight = navigationView.bottomBannerContainerView.bounds.height
            let wayNameHeight = navigationView.wayNameView.bounds.height
            let mediaHeight = mediaPlayerView?.bounds.height ?? 56
            let mediaGap: CGFloat = 8
            let floatingWidth = navigationViewController.floatingButtons?
                .map(\.bounds.width)
                .max() ?? 0

            let topPadding = max(topBannerHeight - safe.top, 0) + 10
            let bottomPadding = max(bottomBannerHeight - safe.bottom, 0)
                + wayNameHeight
                + mediaHeight
                + mediaGap
                + 10

            let padding = UIEdgeInsets(
                top: topPadding,
                left: 0,
                bottom: bottomPadding,
                right: floatingWidth
            )

            let currentViewportPadding = navigationMapView.viewportPadding

            // Avoid a layout feedback loop: only write when Mapbox (or us) drifted.
            if lastAppliedPadding != padding || currentViewportPadding != padding {
                lastAppliedPadding = padding
                navigationMapView.viewportPadding = padding
            }

            NavigationSessionView.hideStockResumeButtons(in: navigationViewController.view)
        }

        @MainActor
        private func handleCameraState(_ state: NavigationCameraState) {
            let following = state == .following
            if let root = navigationViewController?.view {
                NavigationSessionView.hideStockResumeButtons(in: root)
            }

            if lastFollowState != following {
                lastFollowState = following
                recenterHostingController?.rootView = NavigationRecenterButton(isFollowing: following) { [weak self] in
                    self?.recenterOnUser()
                }
            }
            refreshViewportPadding()
        }

        /// Wires Ride Together into this navigation session's existing map: a location source
        /// reusing Mapbox's own map-matched puck feed, a marker overlay on that same `MapView`,
        /// and the SwiftUI chrome (group pill, participant sheet, quick messages, banners) as one
        /// additional child `UIHostingController`, mirroring how the Now Playing bar is added.
        @MainActor
        func attachGroupRide(sessionStore: GroupRideSessionStore, to viewController: NavigationViewController) {
            guard let mapView = viewController.navigationMapView?.mapView else { return }

            groupRideSessionStore = sessionStore
            sessionStore.attachLiveNavigation(locationSource: NavigationMapViewLocationSource(mapView: mapView))

            let overlayController = GroupRideMapOverlayController(mapView: mapView, sessionStore: sessionStore)
            groupRideOverlayController = overlayController

            let hosting = UIHostingController(
                rootView: GroupRideNavigationOverlay(overlayController: overlayController)
                    .environment(sessionStore)
            )
            hosting.view.backgroundColor = .clear
            hosting.view.translatesAutoresizingMaskIntoConstraints = false

            viewController.addChild(hosting)
            viewController.view.addSubview(hosting.view)
            hosting.didMove(toParent: viewController)
            groupRideHostingController = hosting

            NSLayoutConstraint.activate([
                hosting.view.topAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.topAnchor),
                hosting.view.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
                hosting.view.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor),
                hosting.view.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor)
            ])
        }

        /// Guarantees location publication and the marker refresh loop stop the moment this
        /// navigation session ends, regardless of whether Ride Together was ever attached.
        @MainActor
        private func detachGroupRideIfNeeded() {
            groupRideOverlayController?.stop()
            groupRideOverlayController = nil
            groupRideSessionStore?.detachLiveNavigation()
            groupRideSessionStore = nil
            groupRideHostingController?.willMove(toParent: nil)
            groupRideHostingController?.view.removeFromSuperview()
            groupRideHostingController?.removeFromParent()
            groupRideHostingController = nil
        }

        func navigationViewControllerDidDismiss(
            _ navigationViewController: NavigationViewController,
            byCanceling canceled: Bool
        ) {
            cameraCancellable?.cancel()
            detachGroupRideIfNeeded()
            onDismiss(canceled)
        }
    }
}

/// Glass recenter control hosted inside the UIKit navigation session.
struct NavigationRecenterButton: View {
    let isFollowing: Bool
    let action: () -> Void

    var body: some View {
        RecenterMapButton(isFollowing: isFollowing, action: action)
            .opacity(isFollowing ? 0.55 : 1)
    }
}

/// Zero-size probe so we can re-apply viewport padding after Mapbox's own
/// `viewDidAppear` / layout pass overwrites `navigationMapView.viewportPadding`.
private final class NavigationPaddingProbeView: UIView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
