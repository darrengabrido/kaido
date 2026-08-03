import CoreLocation
import Foundation

/// One rider's last-known location, kept only in memory — never written to disk or a database.
struct GroupRideParticipantLocation: Sendable, Equatable {
    var memberId: UUID
    var coordinate: CLLocationCoordinate2D
    var courseDegrees: Double?
    var speedMetersPerSecond: Double?
    var horizontalAccuracyMeters: Double
    var lastUpdatedAt: Date
    var sequence: UInt64

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.memberId == rhs.memberId
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.courseDegrees == rhs.courseDegrees
            && lhs.speedMetersPerSecond == rhs.speedMetersPerSecond
            && lhs.horizontalAccuracyMeters == rhs.horizontalAccuracyMeters
            && lhs.lastUpdatedAt == rhs.lastUpdatedAt
            && lhs.sequence == rhs.sequence
    }
}

enum GroupRideMarkerFreshness: Sendable, Equatable {
    /// Normal appearance.
    case fresh
    /// Dimmed/marked stale but still shown on the map.
    case stale
    /// Old enough to remove from the map overlay entirely — the participant list still shows a
    /// "last seen" indication from the member row's own state.
    case expired

    static func forAge(_ age: TimeInterval) -> GroupRideMarkerFreshness {
        switch age {
        case ..<GroupRideConfig.Location.freshWindow: return .fresh
        case ..<GroupRideConfig.Location.removalWindow: return .stale
        default: return .expired
        }
    }
}

/// In-memory-only per-rider location state for one active group ride. Deliberately has no
/// persistence: it's rebuilt from scratch on every ride join/reconnect and dropped entirely on
/// leave/end (see `GroupRideSessionStore.teardownLiveState`).
@MainActor
@Observable
final class GroupRideParticipantLocationStore {
    private(set) var locationsByMemberId: [UUID: GroupRideParticipantLocation] = [:]
    private let clock: GroupRideClock

    init(clock: GroupRideClock = SystemClock()) {
        self.clock = clock
    }

    /// Applies an inbound envelope. Returns `false` (and does nothing) if the envelope fails
    /// plausibility/accuracy/freshness checks, or if it's an out-of-order/duplicate delivery for
    /// a rider we already have a newer sample from — this is what keeps a delayed packet from
    /// ever moving a rider's marker backward.
    @discardableResult
    func apply(_ envelope: GroupRideLocationEnvelope, receivedAt: Date? = nil) -> Bool {
        let now = receivedAt ?? clock.now()
        guard GroupRideLocationValidation.isAcceptableForReceiving(envelope, receivedAt: now, clock: clock)
        else { return false }

        if let existing = locationsByMemberId[envelope.memberId], envelope.sequence <= existing.sequence {
            return false
        }

        locationsByMemberId[envelope.memberId] = GroupRideParticipantLocation(
            memberId: envelope.memberId,
            coordinate: envelope.coordinate,
            courseDegrees: envelope.courseDegrees,
            speedMetersPerSecond: envelope.speedMetersPerSecond,
            horizontalAccuracyMeters: envelope.horizontalAccuracyMeters,
            lastUpdatedAt: envelope.sentAt,
            sequence: envelope.sequence
        )
        return true
    }

    func remove(memberId: UUID) {
        locationsByMemberId.removeValue(forKey: memberId)
    }

    func removeAll() {
        locationsByMemberId.removeAll()
    }

    func freshness(for memberId: UUID, now: Date? = nil) -> GroupRideMarkerFreshness? {
        guard let location = locationsByMemberId[memberId] else { return nil }
        let age = (now ?? clock.now()).timeIntervalSince(location.lastUpdatedAt)
        return .forAge(age)
    }

    /// Locations that should currently render on the map — expired riders are dropped here, and
    /// only reappear (fresh) on their next accepted update.
    func visibleLocations(now: Date? = nil) -> [GroupRideParticipantLocation] {
        let referenceNow = now ?? clock.now()
        return locationsByMemberId.values.filter {
            GroupRideMarkerFreshness.forAge(referenceNow.timeIntervalSince($0.lastUpdatedAt)) != .expired
        }
    }
}
