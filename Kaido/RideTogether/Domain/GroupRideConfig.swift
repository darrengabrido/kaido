import Foundation

/// Centralized tunables for Ride Together so limits and thresholds live in one place instead of
/// scattered through UI and networking code. Mirrors the "make the limit configurable in the
/// domain/backend" requirement — the server enforces `maxMembers` independently (see the
/// `create_group_ride` migration), this is the client-side mirror used for UI state and tests.
enum GroupRideConfig {
    /// Default participant cap including the host. The backend's `group_rides.max_members`
    /// column is the source of truth at runtime; this is only the client default offered when
    /// creating a ride.
    static let defaultMaxMembers = 8
    static let maxMembersRange = 2...12

    /// Maximum characters for any message body (preset, dictated, or custom-reply-derived).
    static let maxMessageBodyLength = 160
    /// Maximum characters for a one-off dictated message (same ceiling as any message body).
    static let maxDictatedMessageLength = 160

    static let maxCustomQuickReplies = 6
    static let maxCustomQuickReplyLength = 40

    /// Default lifetime of a freshly created or rotated invite.
    static let defaultInviteLifetime: TimeInterval = 24 * 60 * 60

    enum Location {
        /// Floor between two ordinary location broadcasts while moving.
        static let minimumPublishInterval: TimeInterval = 2
        /// Meters of movement that justify publishing sooner than `minimumPublishInterval`.
        static let meaningfulDisplacementMeters: Double = 9
        /// Degrees of heading change that justify publishing sooner than `minimumPublishInterval`.
        static let meaningfulHeadingChangeDegrees: Double = 15
        /// Interval between heartbeats while stationary (no meaningful displacement/heading change).
        static let stationaryHeartbeatInterval: TimeInterval = 10
        /// Locations reporting worse accuracy than this (meters) are rejected outright.
        static let maximumAcceptableAccuracyMeters: Double = 65

        /// A marker renders normally below this age.
        static let freshWindow: TimeInterval = 8
        /// A marker is dimmed/marked stale between `freshWindow` and this age.
        static let staleWindow: TimeInterval = 20
        /// Beyond this age a rider is dropped from the map overlay (participant list retains
        /// a "last seen" indication instead).
        static let removalWindow: TimeInterval = 30

        /// Inbound packets older than this are ignored outright as too stale to be useful,
        /// independent of per-rider staleness bucketing above.
        static let maximumAcceptablePacketAge: TimeInterval = 45
    }

    enum Messaging {
        /// How long an incoming message banner stays on screen before auto-dismissing.
        static let bannerDisplayDuration: TimeInterval = 5
        /// How many recent messages the group sheet keeps in memory for display.
        static let recentMessageHistoryLimit = 50
    }
}
