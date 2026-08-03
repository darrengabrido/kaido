import CoreLocation
import Foundation

/// Throttled publisher that turns the existing navigation location stream into broadcast
/// envelopes. Owns no location hardware itself — `source` is whatever authoritative stream is
/// already running (see `NavigationMapViewLocationSource`), so starting this publisher never
/// spins up a second, competing `CLLocationManager`.
@MainActor
final class GroupRideLocationPublisher {
    private let source: GroupRideLocationSource
    private let realtimeClient: GroupRideRealtimeClient
    private let clock: GroupRideClock

    private var throttle = GroupRideLocationThrottlePolicy()
    private var sequence: UInt64 = 0
    private var rideId: UUID?
    private var memberId: UUID?
    private(set) var isPublishing = false

    init(
        source: GroupRideLocationSource,
        realtimeClient: GroupRideRealtimeClient,
        clock: GroupRideClock = SystemClock()
    ) {
        self.source = source
        self.realtimeClient = realtimeClient
        self.clock = clock
    }

    /// Starts publishing for the given ride/member. A no-op if already publishing — callers
    /// should `stop()` first to switch rides.
    func start(rideId: UUID, memberId: UUID) {
        guard !isPublishing else { return }
        self.rideId = rideId
        self.memberId = memberId
        throttle = GroupRideLocationThrottlePolicy()
        sequence = 0
        isPublishing = true
        // The closure's declared type (from `GroupRideLocationSource`) isn't itself
        // main-actor-isolated, even though this method is — hop explicitly rather than assume
        // whatever later calls `handler` is already on the main actor.
        source.start { [weak self] location in
            Task { @MainActor in
                self?.handle(location)
            }
        }
    }

    /// Idempotent — safe to call from every teardown path even if never started.
    func stop() {
        guard isPublishing else { return }
        isPublishing = false
        source.stop()
        rideId = nil
        memberId = nil
    }

    private func handle(_ location: CLLocation) {
        guard isPublishing, let rideId, let memberId else { return }
        guard GroupRideLocationValidation.isPlausible(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        ) else { return }
        guard GroupRideLocationValidation.isAcceptableForPublishing(
            accuracyMeters: location.horizontalAccuracy
        ) else { return }

        let now = clock.now()
        let sample = GroupRideLocationSample(
            coordinate: location.coordinate,
            horizontalAccuracyMeters: location.horizontalAccuracy,
            courseDegrees: location.course >= 0 ? location.course : nil,
            speedMetersPerSecond: location.speed >= 0 ? location.speed : nil,
            timestamp: now
        )

        guard throttle.shouldPublish(sample, now: now) else { return }
        throttle.recordPublished(sample)
        sequence += 1

        let envelope = GroupRideLocationEnvelope(
            schemaVersion: GroupRideLocationEnvelope.currentSchemaVersion,
            rideId: rideId,
            memberId: memberId,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracyMeters: location.horizontalAccuracy,
            courseDegrees: sample.courseDegrees,
            speedMetersPerSecond: sample.speedMetersPerSecond,
            sentAt: now,
            sequence: sequence
        )

        let client = realtimeClient
        Task {
            await client.publishLocation(envelope)
        }
    }
}
