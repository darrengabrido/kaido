import Foundation
import CoreLocation

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    var authorizationStatus: CLAuthorizationStatus
    var currentLocation: CLLocation?

    /// Reject fixes looser than this — they cause the puck and route origin to jump.
    private static let maximumHorizontalAccuracy: CLLocationAccuracy = 65
    /// Ignore tiny GPS jitter between consecutive good fixes.
    private static let minimumMovementMeters: CLLocationDistance = 2.5

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Smooth live tracking: report when the rider actually moves, not every noisy sample.
        manager.distanceFilter = 3
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation() {
        manager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= Self.maximumHorizontalAccuracy
        else { return }

        if let previous = currentLocation,
           location.distance(from: previous) < Self.minimumMovementMeters,
           location.timestamp.timeIntervalSince(previous.timestamp) < 2
        {
            // Keep a fresher timestamp on a near-identical fix without moving the coordinate.
            if location.horizontalAccuracy <= previous.horizontalAccuracy {
                currentLocation = location
            }
            return
        }

        currentLocation = location
    }
}
