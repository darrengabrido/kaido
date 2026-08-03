import Foundation
import CoreLocation

/// The minimal, ephemeral payload broadcast over the private `group-ride:<id>` Realtime channel.
/// Deliberately excludes anything not needed to render a rider marker: no BLE telemetry, no
/// device identifiers, no auth tokens, no ride history. Never persisted server-side.
struct GroupRideLocationEnvelope: Codable, Sendable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var rideId: UUID
    var memberId: UUID
    var latitude: Double
    var longitude: Double
    var horizontalAccuracyMeters: Double
    /// Course/heading in degrees, `nil` when the source location had no valid course.
    var courseDegrees: Double?
    /// `nil` when the source location didn't report a speed.
    var speedMetersPerSecond: Double?
    var sentAt: Date
    /// Monotonically increasing per-member counter — lets receivers discard out-of-order or
    /// duplicate delivery independent of clock skew between devices.
    var sequence: UInt64

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum GroupRideLocationValidation {
    /// Coordinates that can't correspond to a real GPS fix — guards against decode garbage or a
    /// (0, 0) default slipping through as if it were a real location.
    static func isPlausible(latitude: Double, longitude: Double) -> Bool {
        guard latitude.isFinite, longitude.isFinite else { return false }
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return false }
        guard !(latitude == 0 && longitude == 0) else { return false }
        return true
    }

    /// Applied before publishing a *local* fix: rejects readings too inaccurate to be useful to
    /// other riders, independent of anything about the packet's age or ordering.
    static func isAcceptableForPublishing(accuracyMeters: Double) -> Bool {
        accuracyMeters.isFinite
            && accuracyMeters >= 0
            && accuracyMeters <= GroupRideConfig.Location.maximumAcceptableAccuracyMeters
    }

    /// Applied to an *inbound* envelope before it's allowed to update participant state.
    static func isAcceptableForReceiving(
        _ envelope: GroupRideLocationEnvelope,
        knownSchemaVersion: Int = GroupRideLocationEnvelope.currentSchemaVersion,
        receivedAt: Date,
        clock: GroupRideClock = SystemClock()
    ) -> Bool {
        guard envelope.schemaVersion <= knownSchemaVersion else { return false }
        guard isPlausible(latitude: envelope.latitude, longitude: envelope.longitude) else { return false }
        guard isAcceptableForPublishing(accuracyMeters: envelope.horizontalAccuracyMeters) else { return false }
        let age = receivedAt.timeIntervalSince(envelope.sentAt)
        guard age >= -5, age <= GroupRideConfig.Location.maximumAcceptablePacketAge else { return false }
        return true
    }
}
