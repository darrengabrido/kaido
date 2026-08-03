import Foundation
import CoreLocation

/// Lifecycle state of a group ride. Backed by the `group_rides.status` column
/// (`lobby` | `active` | `ended` | `cancelled`).
enum GroupRideStatus: String, Codable, Sendable, CaseIterable {
    case lobby
    case active
    case ended
    case cancelled

    /// Whether members may still be previewing/joining/updating the route.
    var isJoinable: Bool { self == .lobby }
    /// Whether the ride is currently expected to be publishing/receiving live locations.
    var isLive: Bool { self == .active }
    var isTerminal: Bool { self == .ended || self == .cancelled }
}

/// A rider's role within one group ride. Backed by `group_ride_members.role`.
enum GroupRideRole: String, Codable, Sendable {
    case host
    case rider

    var isHost: Bool { self == .host }
}

/// Membership state within a ride. Backed by `group_ride_members.status`.
enum GroupRideMemberStatus: String, Codable, Sendable {
    case joined
    case left
    case removed

    var isActive: Bool { self == .joined }
}

/// One participant in a group ride. `avatarSeed` drives a deterministic marker style/initials
/// so a rider's map identity stays stable without a photo-upload feature.
struct GroupRideMember: Identifiable, Codable, Sendable, Equatable {
    let rideId: UUID
    let userId: UUID
    var role: GroupRideRole
    var status: GroupRideMemberStatus
    var displayName: String
    var avatarSeed: String
    let joinedAt: Date
    var leftAt: Date?
    var lastSeenAt: Date?

    var id: UUID { userId }
    var isHost: Bool { role.isHost }
    var isActive: Bool { status.isActive }
}

/// The app-owned record of a group ride's lifecycle and shared route. Mirrors `group_rides`.
///
/// Invite tokens are never modeled here in raw form — only `inviteExpiresAt` and whether an
/// invite currently exists are client-visible. The raw token is returned exactly once, at
/// creation/rotation time, by the corresponding RPC response (see `GroupRideService`).
struct GroupRide: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let hostUserId: UUID
    var status: GroupRideStatus
    var title: String?
    var destinationName: String
    var destinationLatitude: Double
    var destinationLongitude: Double
    var routeSnapshot: GroupRideRouteSnapshot
    var maxMembers: Int
    var inviteExpiresAt: Date?
    let createdAt: Date
    var updatedAt: Date
    var startedAt: Date?
    var endedAt: Date?

    var destinationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: destinationLatitude, longitude: destinationLongitude)
    }

    var hasValidInvite: Bool {
        guard let inviteExpiresAt else { return false }
        return inviteExpiresAt > Date()
    }
}
