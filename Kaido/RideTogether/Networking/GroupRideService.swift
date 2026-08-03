import Foundation
import CoreLocation

struct GroupRideCreationResult: Sendable, Equatable {
    let ride: GroupRide
    /// Returned exactly once — never persisted, never logged. Hand it straight to the invite
    /// link builder / share sheet.
    let rawInviteToken: String
}

struct GroupRideInvitePreview: Sendable, Equatable {
    let rideId: UUID
    let status: GroupRideStatus
    let destinationName: String
    let destinationCoordinate: CLLocationCoordinate2D
    let routeSnapshot: GroupRideRouteSnapshot
    let maxMembers: Int
    let activeMemberCount: Int
    let hostDisplayName: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rideId == rhs.rideId && lhs.status == rhs.status
            && lhs.destinationName == rhs.destinationName
            && lhs.routeSnapshot == rhs.routeSnapshot && lhs.maxMembers == rhs.maxMembers
            && lhs.activeMemberCount == rhs.activeMemberCount
            && lhs.hostDisplayName == rhs.hostDisplayName
    }
}

struct GroupRideJoinResult: Sendable, Equatable {
    let ride: GroupRide
    let membership: GroupRideMember
}

struct GroupRideInviteRotation: Sendable, Equatable {
    let rawInviteToken: String
    let inviteExpiresAt: Date
}

struct GroupRideLeaveResult: Sendable, Equatable {
    let hostLeft: Bool
}

enum GroupRideServiceError: LocalizedError, Equatable {
    case notConfigured
    case notAuthenticated
    case invalidInvite
    case rideEnded
    case rideCancelled
    case rideFull
    case notHost
    case server(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return String(localized: "Ride Together isn't configured yet.")
        case .notAuthenticated:
            return String(localized: "You need to be signed in (or continue as a guest) to use Ride Together.")
        case .invalidInvite:
            return String(localized: "This invite link is invalid or has expired.")
        case .rideEnded:
            return String(localized: "This group ride has ended.")
        case .rideCancelled:
            return String(localized: "This group ride was cancelled.")
        case .rideFull:
            return String(localized: "This group ride is full.")
        case .notHost:
            return String(localized: "Only the host can do that.")
        case .server(let message):
            return message
        case .decoding:
            return String(localized: "Couldn't read the server's response. Try again.")
        }
    }
}

/// Everything Ride Together needs from the backend: ride lifecycle, membership, and durable
/// message history. Live rider *locations* never go through this protocol — see
/// `GroupRideRealtimeClient` for the ephemeral broadcast/presence transport.
protocol GroupRideService: Sendable {
    func createRide(
        destinationName: String,
        destination: CLLocationCoordinate2D,
        routeSnapshot: GroupRideRouteSnapshot,
        maxMembers: Int,
        title: String?,
        displayName: String
    ) async throws -> GroupRideCreationResult

    func previewInvite(rideId: UUID, token: String) async throws -> GroupRideInvitePreview

    func joinRide(
        rideId: UUID,
        token: String,
        displayName: String
    ) async throws -> GroupRideJoinResult

    func rotateInvite(rideId: UUID) async throws -> GroupRideInviteRotation

    func updateRoute(
        rideId: UUID,
        routeSnapshot: GroupRideRouteSnapshot,
        destinationName: String?,
        destination: CLLocationCoordinate2D?
    ) async throws -> GroupRide

    func startRide(rideId: UUID) async throws -> GroupRide
    func endRide(rideId: UUID) async throws -> GroupRide
    func cancelRide(rideId: UUID) async throws -> GroupRide
    func leaveRide(rideId: UUID) async throws -> GroupRideLeaveResult
    func removeMember(rideId: UUID, userId: UUID) async throws
    func touchPresence(rideId: UUID) async throws

    func fetchRide(rideId: UUID) async throws -> GroupRide
    func fetchMembers(rideId: UUID) async throws -> [GroupRideMember]
    func fetchRecentMessages(rideId: UUID, limit: Int) async throws -> [GroupRideMessage]

    /// Idempotent insert keyed by `message.clientMessageId` — safe to retry after a dropped
    /// response without risking a duplicate delivery.
    func sendMessage(_ message: GroupRideMessage) async throws -> GroupRideMessage
}
