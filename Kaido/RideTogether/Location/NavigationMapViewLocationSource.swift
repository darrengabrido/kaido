import CoreLocation
import MapboxMaps

/// Adapts the location stream already driving the active `NavigationViewController`'s puck
/// (map-matched while turn-by-turn guidance is running) into a `GroupRideLocationSource`, so
/// starting Ride Together's publisher never spins up a second, continuously-running
/// `CLLocationManager` — it reuses the same `MapView.location` feed Mapbox itself is already
/// driving during active guidance.
///
/// NOTE ON VERIFICATION: this is the one integration point in Ride Together that reaches into
/// Mapbox Navigation SDK internals (`NavigationViewController.navigationMapView`) rather than
/// only this app's own code. Verify the exact property/signal names on first build against the
/// installed SDK version — see docs/RideTogether.md.
@MainActor
final class NavigationMapViewLocationSource: GroupRideLocationSource {
    private weak var mapView: MapView?
    private var cancelable: AnyCancelable?
    private var handler: ((CLLocation) -> Void)?

    init(mapView: MapView) {
        self.mapView = mapView
    }

    func start(handler: @escaping (CLLocation) -> Void) {
        self.handler = handler
        // Deferring the actual handling into a `Task { @MainActor in }` (rather than assuming
        // this Signal always fires on the main thread) mirrors how this codebase already bridges
        // other SDK callbacks onto the main actor — see `BikeBLEManager`'s CoreBluetooth delegates.
        cancelable = mapView?.location.onLocationChange.observe { [weak self] locations in
            guard let latest = locations.last else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                // `Location`'s altitude/horizontalAccuracy/speed are optional (nil when Mapbox's
                // own fix doesn't have them yet), and it has no `course` member in the installed
                // SDK version — map course to CLLocation's own "unknown" sentinel (-1) rather than
                // guess at a different property name for a value only used for a cosmetic bearing
                // indicator in the rider card.
                let clLocation = CLLocation(
                    coordinate: latest.coordinate,
                    altitude: latest.altitude ?? 0,
                    horizontalAccuracy: latest.horizontalAccuracy ?? -1,
                    verticalAccuracy: -1,
                    course: -1,
                    speed: latest.speed ?? -1,
                    timestamp: latest.timestamp
                )
                self.handler?(clLocation)
            }
        }
    }

    func stop() {
        cancelable?.cancel()
        cancelable = nil
        handler = nil
    }
}
