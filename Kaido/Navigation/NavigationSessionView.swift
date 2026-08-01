import SwiftUI
import MapboxNavigationCore
import MapboxNavigationUIKit

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

        // Don't touch `viewController.view` here — loading it starts active guidance before
        // the fullScreenCover has presented (Mapbox documents this as a footgun). Install
        // the Now Playing bar on the next run loop once the VC is in the hierarchy.
        DispatchQueue.main.async {
            self.addMediaPlayerBar(to: viewController)
            if let groupRideSessionStore, groupRideSessionStore.hasActiveRide {
                // `attachGroupRide` is main-actor isolated (it touches `GroupRideSessionStore`);
                // wrapping unambiguously bridges into that isolation regardless of whether this
                // `DispatchQueue.main.async` closure itself is inferred `@MainActor`.
                Task { @MainActor in
                    context.coordinator.attachGroupRide(sessionStore: groupRideSessionStore, to: viewController)
                }
            }
        }
        return viewController
    }

    /// Docks the Now Playing bar just above Mapbox's own bottom banner. Anchoring to
    /// `bottomBannerContainerView` rather than the safe area keeps it clear of the ETA/End
    /// controls without hard-coding that banner's height.
    private func addMediaPlayerBar(to viewController: NavigationViewController) {
        let barController = UIHostingController(
            rootView: MediaPlayerBar(manager: MediaPlayerManager.shared)
        )
        barController.view.backgroundColor = .clear
        barController.view.translatesAutoresizingMaskIntoConstraints = false

        viewController.addChild(barController)
        viewController.view.addSubview(barController.view)
        barController.didMove(toParent: viewController)

        let bottomBanner = viewController.navigationView.bottomBannerContainerView
        NSLayoutConstraint.activate([
            barController.view.leadingAnchor.constraint(
                equalTo: viewController.view.leadingAnchor,
                constant: 16
            ),
            barController.view.trailingAnchor.constraint(
                equalTo: viewController.view.trailingAnchor,
                constant: -16
            ),
            barController.view.bottomAnchor.constraint(
                equalTo: bottomBanner.topAnchor,
                constant: -8
            )
        ])
    }

    func updateUIViewController(_ uiViewController: NavigationViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss, rideTimeProfile: rideTimeProfile)
    }

    final class Coordinator: NSObject, NavigationViewControllerDelegate {
        let onDismiss: (Bool) -> Void
        /// Owned here so it outlives `makeUIViewController` and stays shared by both banners.
        let bannerModel: NavigationBannerModel

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
            // Matches this codebase's existing pattern for bridging a delegate callback of
            // uncertain actor isolation into main-actor cleanup (see `BikeBLEManager`'s
            // CoreBluetooth delegate methods) rather than assuming this method already runs
            // on the main actor.
            Task { @MainActor [weak self] in
                self?.detachGroupRideIfNeeded()
            }
            onDismiss(canceled)
        }
    }
}
