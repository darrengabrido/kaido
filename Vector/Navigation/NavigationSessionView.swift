import SwiftUI
import MapboxNavigationCore
import MapboxNavigationUIKit

struct NavigationSessionView: UIViewControllerRepresentable {
    let navigationRoutes: NavigationRoutes
    let telemetry: BikeTelemetry
    let onDismiss: (Bool) -> Void

    func makeUIViewController(context: Context) -> NavigationViewController {
        let provider = VectorNavigationProvider.shared
        let nightStyle = StandardNightStyle()
        nightStyle.tintColor = UIColor(Color.vectorViolet)

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

        addMediaPlayerBar(to: viewController)
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
        Coordinator(onDismiss: onDismiss)
    }

    final class Coordinator: NSObject, NavigationViewControllerDelegate {
        let onDismiss: (Bool) -> Void
        /// Owned here so it outlives `makeUIViewController` and stays shared by both banners.
        let bannerModel = NavigationBannerModel()

        init(onDismiss: @escaping (Bool) -> Void) {
            self.onDismiss = onDismiss
        }

        func navigationViewControllerDidDismiss(
            _ navigationViewController: NavigationViewController,
            byCanceling canceled: Bool
        ) {
            onDismiss(canceled)
        }
    }
}
