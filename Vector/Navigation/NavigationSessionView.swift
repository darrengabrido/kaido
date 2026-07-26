import SwiftUI
import MapboxNavigationCore
import MapboxNavigationUIKit

struct NavigationSessionView: UIViewControllerRepresentable {
    let navigationRoutes: NavigationRoutes
    let onDismiss: (Bool) -> Void

    func makeUIViewController(context: Context) -> NavigationViewController {
        let provider = VectorNavigationProvider.shared
        let nightStyle = StandardNightStyle()
        nightStyle.tintColor = UIColor(Color.vectorViolet)
        let navigationOptions = NavigationOptions(
            mapboxNavigation: provider.mapboxNavigation,
            voiceController: provider.routeVoiceController,
            eventsManager: provider.eventsManager(),
            styles: [nightStyle]
        )
        let viewController = NavigationViewController(
            navigationRoutes: navigationRoutes,
            navigationOptions: navigationOptions
        )
        viewController.delegate = context.coordinator
        return viewController
    }

    func updateUIViewController(_ uiViewController: NavigationViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    final class Coordinator: NSObject, NavigationViewControllerDelegate {
        let onDismiss: (Bool) -> Void

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
