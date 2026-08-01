import CoreLocation

/// A source of live location updates for Ride Together to publish. Exactly one consumer
/// (`GroupRideLocationPublisher`) uses this at a time, so `start` simply replaces any previous
/// handler rather than supporting multiple simultaneous subscribers.
@MainActor
protocol GroupRideLocationSource: AnyObject {
    func start(handler: @escaping (CLLocation) -> Void)
    func stop()
}
