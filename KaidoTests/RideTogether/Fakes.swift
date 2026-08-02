@testable import Kaido
import Foundation
import CoreLocation

enum TestError: Error, Equatable {
    case unconfigured
    case forced
}

/// Records every call so tests can assert on both the returned value and how many times (and
/// with what arguments) each method was invoked — used to verify things like "starting a ride
/// twice never double-subscribes" without a live Supabase project.
final class FakeGroupRideService: GroupRideService, @unchecked Sendable {
    var rideStore: GroupRide?
    var membersStore: [GroupRideMember] = []
    var messagesStore: [GroupRideMessage] = []

    var createRideResult: Result<GroupRideCreationResult, Error>?
    var joinRideResult: Result<GroupRideJoinResult, Error>?
    var previewResult: Result<GroupRideInvitePreview, Error>?
    var leaveRideResult: GroupRideLeaveResult = GroupRideLeaveResult(hostLeft: false)

    private(set) var startRideCallCount = 0
    private(set) var endRideCallCount = 0
    private(set) var cancelRideCallCount = 0
    private(set) var updateRouteCallCount = 0
    private(set) var removeMemberCallCount = 0
    private(set) var rotateInviteCallCount = 0
    private(set) var leaveRideCallCount = 0
    private(set) var sentMessages: [GroupRideMessage] = []

    func createRide(
        destinationName: String,
        destination: CLLocationCoordinate2D,
        routeSnapshot: GroupRideRouteSnapshot,
        maxMembers: Int,
        title: String?,
        displayName: String
    ) async throws -> GroupRideCreationResult {
        guard let createRideResult else { throw TestError.unconfigured }
        let value = try createRideResult.get()
        rideStore = value.ride
        return value
    }

    func previewInvite(rideId: UUID, token: String) async throws -> GroupRideInvitePreview {
        guard let previewResult else { throw TestError.unconfigured }
        return try previewResult.get()
    }

    func joinRide(rideId: UUID, token: String, displayName: String) async throws -> GroupRideJoinResult {
        guard let joinRideResult else { throw TestError.unconfigured }
        let value = try joinRideResult.get()
        rideStore = value.ride
        return value
    }

    func rotateInvite(rideId: UUID) async throws -> GroupRideInviteRotation {
        rotateInviteCallCount += 1
        return GroupRideInviteRotation(rawInviteToken: "rotated-token", inviteExpiresAt: Date().addingTimeInterval(3600))
    }

    func updateRoute(
        rideId: UUID,
        routeSnapshot: GroupRideRouteSnapshot,
        destinationName: String?,
        destination: CLLocationCoordinate2D?
    ) async throws -> GroupRide {
        updateRouteCallCount += 1
        guard var ride = rideStore else { throw TestError.unconfigured }
        ride.routeSnapshot = routeSnapshot
        rideStore = ride
        return ride
    }

    func startRide(rideId: UUID) async throws -> GroupRide {
        startRideCallCount += 1
        guard var ride = rideStore else { throw TestError.unconfigured }
        ride.status = .active
        rideStore = ride
        return ride
    }

    func endRide(rideId: UUID) async throws -> GroupRide {
        endRideCallCount += 1
        guard var ride = rideStore else { throw TestError.unconfigured }
        ride.status = .ended
        rideStore = ride
        return ride
    }

    func cancelRide(rideId: UUID) async throws -> GroupRide {
        cancelRideCallCount += 1
        guard var ride = rideStore else { throw TestError.unconfigured }
        ride.status = .cancelled
        rideStore = ride
        return ride
    }

    func leaveRide(rideId: UUID) async throws -> GroupRideLeaveResult {
        leaveRideCallCount += 1
        return leaveRideResult
    }

    func removeMember(rideId: UUID, userId: UUID) async throws {
        removeMemberCallCount += 1
        membersStore.removeAll { $0.userId == userId }
    }

    func touchPresence(rideId: UUID) async throws {}

    func fetchRide(rideId: UUID) async throws -> GroupRide {
        guard let rideStore else { throw TestError.unconfigured }
        return rideStore
    }

    func fetchMembers(rideId: UUID) async throws -> [GroupRideMember] {
        membersStore
    }

    func fetchRecentMessages(rideId: UUID, limit: Int) async throws -> [GroupRideMessage] {
        messagesStore
    }

    func sendMessage(_ message: GroupRideMessage) async throws -> GroupRideMessage {
        sentMessages.append(message)
        return message
    }
}

/// Counts connect/disconnect calls so tests can assert that reconnecting never stacks a second
/// live subscription on top of an old one.
final class FakeGroupRideRealtimeClient: GroupRideRealtimeClient, @unchecked Sendable {
    private(set) var connectCallCount = 0
    private(set) var disconnectCallCount = 0
    private(set) var publishedLocations: [GroupRideLocationEnvelope] = []
    private(set) var publishedMessages: [GroupRideMessage] = []
    private(set) var publishedStatuses: [GroupRideStatus] = []
    /// Captured so tests can simulate a server-pushed "something changed" broadcast arriving on
    /// an already-connected session — see the tests proving neither notice is trusted at face
    /// value (`GroupRideSessionStore.handleIncomingMessageNotice`/`handleRemoteStatusChangeNotice`).
    private(set) var capturedOnMessage: (@Sendable () -> Void)?
    private(set) var capturedOnRideStatusChange: (@Sendable () -> Void)?

    func connect(
        rideId: UUID,
        memberId: UUID,
        onLocation: @escaping @Sendable (GroupRideLocationEnvelope) -> Void,
        onMessage: @escaping @Sendable () -> Void,
        onRideStatusChange: @escaping @Sendable () -> Void,
        onPresenceChange: @escaping @Sendable (Set<UUID>) -> Void,
        onConnectionStateChange: @escaping @Sendable (GroupRideConnectionState) -> Void
    ) async {
        connectCallCount += 1
        capturedOnMessage = onMessage
        capturedOnRideStatusChange = onRideStatusChange
        onConnectionStateChange(.connected)
    }

    func disconnect() async {
        disconnectCallCount += 1
    }

    func publishLocation(_ envelope: GroupRideLocationEnvelope) async {
        publishedLocations.append(envelope)
    }

    func publishMessageNotice(_ message: GroupRideMessage) async {
        publishedMessages.append(message)
    }

    func publishRideStatusNotice(_ status: GroupRideStatus) async {
        publishedStatuses.append(status)
    }
}

final class FakeGroupRideIdentityProvider: GroupRideIdentityProvider, @unchecked Sendable {
    var identity = GroupRideIdentity(userId: UUID(), isAnonymous: true)
    private(set) var ensureIdentityCallCount = 0

    func ensureIdentity() async throws -> GroupRideIdentity {
        ensureIdentityCallCount += 1
        return identity
    }

    func currentUserId() async -> UUID? {
        identity.userId
    }
}

/// Lets a test manually push locations through as if they came from the navigation map, and
/// records start/stop calls to verify publication always stops on every teardown path.
final class FakeGroupRideLocationSource: GroupRideLocationSource, @unchecked Sendable {
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private var handler: ((CLLocation) -> Void)?

    func start(handler: @escaping (CLLocation) -> Void) {
        startCallCount += 1
        self.handler = handler
    }

    func stop() {
        stopCallCount += 1
        handler = nil
    }

    func emit(_ location: CLLocation) {
        handler?(location)
    }
}

extension GroupRide {
    static func fixture(
        id: UUID = UUID(),
        hostUserId: UUID = UUID(),
        status: GroupRideStatus = .lobby,
        maxMembers: Int = 8
    ) -> GroupRide {
        GroupRide(
            id: id,
            hostUserId: hostUserId,
            status: status,
            title: nil,
            destinationName: "Golden Gate Park",
            destinationLatitude: 37.7694,
            destinationLongitude: -122.4862,
            routeSnapshot: .fixture(),
            maxMembers: maxMembers,
            inviteExpiresAt: Date().addingTimeInterval(3600),
            createdAt: Date(),
            updatedAt: Date(),
            startedAt: nil,
            endedAt: nil
        )
    }
}

extension GroupRideRouteSnapshot {
    static func fixture() -> GroupRideRouteSnapshot {
        GroupRideRouteSnapshot(
            schemaVersion: GroupRideRouteSnapshot.currentSchemaVersion,
            destinationName: "Golden Gate Park",
            destinationLatitude: 37.7694,
            destinationLongitude: -122.4862,
            waypoints: [
                .init(latitude: 37.7749, longitude: -122.4194, order: 0),
                .init(latitude: 37.7694, longitude: -122.4862, order: 1)
            ],
            routingProfile: "cycling",
            selectedAlternativeIndex: nil,
            encodedPolyline: GroupRidePolylineCodec.encode([
                CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                CLLocationCoordinate2D(latitude: 37.7694, longitude: -122.4862)
            ]),
            distanceMeters: 5000,
            expectedDurationSeconds: 1200,
            capturedAt: Date()
        )
    }
}

extension GroupRideMember {
    static func fixture(
        rideId: UUID,
        userId: UUID = UUID(),
        role: GroupRideRole = .rider,
        status: GroupRideMemberStatus = .joined,
        displayName: String = "Rider"
    ) -> GroupRideMember {
        GroupRideMember(
            rideId: rideId,
            userId: userId,
            role: role,
            status: status,
            displayName: displayName,
            avatarSeed: userId.uuidString,
            joinedAt: Date(),
            leftAt: nil,
            lastSeenAt: nil
        )
    }
}
