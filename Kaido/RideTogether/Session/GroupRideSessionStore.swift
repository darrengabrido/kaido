import Foundation
import CoreLocation

enum GroupRideSessionError: LocalizedError, Equatable {
    case noActiveRide
    case notHost

    var errorDescription: String? {
        switch self {
        case .noActiveRide: return String(localized: "There's no active Ride Together session.")
        case .notHost: return String(localized: "Only the host can do that.")
        }
    }
}

/// Central coordinator for one Ride Together session: ride/membership state, the Realtime
/// connection lifecycle, live participant locations, and message history. Owns exactly one ride
/// at a time — starting a new one tears down any previous live state first.
///
/// Marked `@unchecked Sendable` because it is only ever mutated on the main actor (enforced by
/// the `@MainActor` isolation below); the escape hatch is needed solely so this instance can be
/// captured by `[weak self]` inside the `@Sendable` callback closures `GroupRideRealtimeClient`
/// invokes from its own (non-main) actor context — every closure body immediately hops back with
/// `Task { @MainActor in }` before touching any state.
@MainActor
@Observable
final class GroupRideSessionStore: @unchecked Sendable {
    private(set) var ride: GroupRide?
    private(set) var members: [GroupRideMember] = []
    private(set) var myMembership: GroupRideMember?
    private(set) var onlineMemberIds: Set<UUID> = []
    private(set) var connectionState: GroupRideConnectionState = .disconnected
    private(set) var isBusy = false
    private(set) var errorMessage: String?

    let participantLocations = GroupRideParticipantLocationStore()
    let messageCenter = GroupRideMessageCenter()

    private let service: GroupRideService
    private let realtimeClient: GroupRideRealtimeClient
    private let identityProvider: GroupRideIdentityProvider
    private var locationPublisher: GroupRideLocationPublisher?
    private var myUserId: UUID?

    var hasActiveRide: Bool { ride != nil && myMembership?.isActive == true }
    var isHost: Bool { myMembership?.isHost == true }
    var currentUserId: UUID? { myUserId }

    init(
        service: GroupRideService = SupabaseGroupRideService(),
        realtimeClient: GroupRideRealtimeClient = SupabaseGroupRideRealtimeClient(),
        identityProvider: GroupRideIdentityProvider = SupabaseGroupRideIdentityProvider()
    ) {
        self.service = service
        self.realtimeClient = realtimeClient
        self.identityProvider = identityProvider
    }

    // MARK: - Create / Join

    func createRide(
        destinationName: String,
        destination: CLLocationCoordinate2D,
        routeSnapshot: GroupRideRouteSnapshot,
        maxMembers: Int = GroupRideConfig.defaultMaxMembers,
        title: String?,
        displayName: String
    ) async throws -> GroupRideCreationResult {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let identity = try await identityProvider.ensureIdentity()
            myUserId = identity.userId
            let result = try await service.createRide(
                destinationName: destinationName,
                destination: destination,
                routeSnapshot: routeSnapshot,
                maxMembers: maxMembers,
                title: title,
                displayName: displayName
            )
            GroupRideDisplayNameStore.current = displayName
            try await applyJoinedState(ride: result.ride)
            return result
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func previewInvite(rideId: UUID, token: String) async throws -> GroupRideInvitePreview {
        try await service.previewInvite(rideId: rideId, token: token)
    }

    func joinRide(rideId: UUID, token: String, displayName: String) async throws {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let identity = try await identityProvider.ensureIdentity()
            myUserId = identity.userId
            let result = try await service.joinRide(rideId: rideId, token: token, displayName: displayName)
            GroupRideDisplayNameStore.current = displayName
            try await applyJoinedState(ride: result.ride)
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func applyJoinedState(ride: GroupRide) async throws {
        self.ride = ride
        try await refreshMembersAndMessages()
        await connectRealtime()
    }

    private func refreshMembersAndMessages() async throws {
        guard let ride else { return }
        let fetchedMembers = try await service.fetchMembers(rideId: ride.id)
        members = fetchedMembers
        myMembership = fetchedMembers.first { $0.userId == myUserId }
        let history = try await service.fetchRecentMessages(
            rideId: ride.id,
            limit: GroupRideConfig.Messaging.recentMessageHistoryLimit
        )
        messageCenter.loadHistory(history)
    }

    // MARK: - Realtime

    private func connectRealtime() async {
        guard let ride, let myUserId else { return }
        await realtimeClient.connect(
            rideId: ride.id,
            memberId: myUserId,
            onLocation: { [weak self] envelope in
                Task { @MainActor in self?.participantLocations.apply(envelope) }
            },
            onMessage: { [weak self] message in
                Task { @MainActor in self?.handleIncoming(message: message) }
            },
            onRideStatusChange: { [weak self] status in
                Task { @MainActor in await self?.handleRemoteStatusChange(status) }
            },
            onPresenceChange: { [weak self] online in
                Task { @MainActor in self?.onlineMemberIds = online }
            },
            onConnectionStateChange: { [weak self] state in
                Task { @MainActor in self?.handleConnectionStateChange(state) }
            }
        )
    }

    private func handleIncoming(message: GroupRideMessage) {
        messageCenter.ingest(message, isIncoming: message.senderUserId != myUserId)
    }

    private func handleConnectionStateChange(_ state: GroupRideConnectionState) {
        let previous = connectionState
        connectionState = state
        // Any transition into `.connected` from something else reconciles authoritative state —
        // cheap on a fresh connect, and exactly what's needed after a drop-and-recover.
        if state == .connected, previous != .connected {
            Task { await self.refreshFromServer() }
        }
    }

    private func handleRemoteStatusChange(_ status: GroupRideStatus) async {
        guard var updatedRide = ride else { return }
        updatedRide.status = status
        ride = updatedRide
        if status.isTerminal {
            await teardownLiveState(clearRide: false)
        }
    }

    // MARK: - Lifecycle actions

    func rotateInvite() async throws -> GroupRideInviteRotation {
        guard let ride else { throw GroupRideSessionError.noActiveRide }
        guard isHost else { throw GroupRideSessionError.notHost }
        return try await service.rotateInvite(rideId: ride.id)
    }

    func updateRoute(
        routeSnapshot: GroupRideRouteSnapshot,
        destinationName: String?,
        destination: CLLocationCoordinate2D?
    ) async throws {
        guard let ride else { throw GroupRideSessionError.noActiveRide }
        guard isHost else { throw GroupRideSessionError.notHost }
        self.ride = try await service.updateRoute(
            rideId: ride.id,
            routeSnapshot: routeSnapshot,
            destinationName: destinationName,
            destination: destination
        )
    }

    func startRide() async throws {
        guard let ride else { throw GroupRideSessionError.noActiveRide }
        guard isHost else { throw GroupRideSessionError.notHost }
        let updated = try await service.startRide(rideId: ride.id)
        self.ride = updated
        await realtimeClient.publishRideStatusNotice(updated.status)
    }

    func endRide() async throws {
        guard let ride else { throw GroupRideSessionError.noActiveRide }
        guard isHost else { throw GroupRideSessionError.notHost }
        let updated = try await service.endRide(rideId: ride.id)
        await realtimeClient.publishRideStatusNotice(updated.status)
        await teardownLiveState(clearRide: true)
    }

    func cancelRide() async throws {
        guard let ride else { throw GroupRideSessionError.noActiveRide }
        guard isHost else { throw GroupRideSessionError.notHost }
        let updated = try await service.cancelRide(rideId: ride.id)
        await realtimeClient.publishRideStatusNotice(updated.status)
        await teardownLiveState(clearRide: true)
    }

    /// Leaving stops this rider's own group participation — and, per the MVP's no-leader-transfer
    /// rule, ends the ride for everyone if the leaving rider was the host — but never touches
    /// their personal navigation session.
    func leaveRide() async throws {
        guard let ride else { throw GroupRideSessionError.noActiveRide }
        let result = try await service.leaveRide(rideId: ride.id)
        if result.hostLeft {
            let newStatus = GroupRideStateMachine.statusAfterHostLeaving(currentStatus: ride.status)
            await realtimeClient.publishRideStatusNotice(newStatus)
        }
        await teardownLiveState(clearRide: true)
    }

    func removeMember(userId: UUID) async throws {
        guard let ride else { throw GroupRideSessionError.noActiveRide }
        guard isHost else { throw GroupRideSessionError.notHost }
        try await service.removeMember(rideId: ride.id, userId: userId)
        try await refreshMembersAndMessages()
    }

    // MARK: - Messaging

    func sendMessage(kind: GroupRideMessageKind, body: String, presetKey: String?) async throws {
        guard let ride, let myUserId, let myMembership else { throw GroupRideSessionError.noActiveRide }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        try GroupRideMessageValidator.validate(body: trimmed)

        let message = GroupRideMessage(
            id: UUID(),
            rideId: ride.id,
            senderUserId: myUserId,
            senderDisplayName: myMembership.displayName,
            kind: kind,
            body: trimmed,
            presetKey: presetKey,
            clientMessageId: UUID(),
            createdAt: Date()
        )
        let sent = try await service.sendMessage(message)
        messageCenter.ingest(sent, isIncoming: false)
        await realtimeClient.publishMessageNotice(sent)
    }

    // MARK: - Live navigation attach/detach
    //
    // Location publishing is gated on three things at once: the ride being active, this rider's
    // own membership still being joined, and an actual navigation session being attached. There
    // is deliberately no path that starts publishing without all three.

    func attachLiveNavigation(locationSource: GroupRideLocationSource) {
        guard let ride, let myUserId,
              GroupRideStateMachine.locationPublishingAllowed(
                rideStatus: ride.status,
                memberStatus: myMembership?.status ?? .left
              )
        else { return }
        let publisher = GroupRideLocationPublisher(source: locationSource, realtimeClient: realtimeClient)
        publisher.start(rideId: ride.id, memberId: myUserId)
        locationPublisher = publisher
    }

    /// Idempotent — safe to call whenever a navigation session ends, even if never attached.
    func detachLiveNavigation() {
        locationPublisher?.stop()
        locationPublisher = nil
    }

    // MARK: - Reconnection / foreground restoration

    func refreshFromServer() async {
        guard let ride else { return }
        do {
            let fresh = try await service.fetchRide(rideId: ride.id)
            self.ride = fresh
            try await refreshMembersAndMessages()
            if fresh.status.isTerminal {
                await teardownLiveState(clearRide: false)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handleAppForeground() async {
        guard ride != nil else { return }
        await refreshFromServer()
        // `connectRealtime()` tears down any existing channel before creating a new one, so this
        // never stacks a duplicate subscription even if the old one was actually still alive.
        guard let ride, !ride.status.isTerminal, myMembership?.isActive == true,
              connectionState != .connected
        else { return }
        await connectRealtime()
    }

    // MARK: - Teardown
    //
    // Every path that can end this rider's participation — leaving, the host ending/cancelling,
    // a remote status change arriving over Realtime, or reconnect discovering the ride already
    // ended — funnels through here, so location publication and the Realtime connection are
    // guaranteed to stop no matter which path triggered it.

    func teardownLiveState(clearRide: Bool) async {
        detachLiveNavigation()
        await realtimeClient.disconnect()
        participantLocations.removeAll()
        messageCenter.reset()
        onlineMemberIds = []
        connectionState = .disconnected
        if clearRide {
            ride = nil
            members = []
            myMembership = nil
        }
    }

    /// Clears a terminal ride from local state once the UI has finished showing its "ended"
    /// state — prevents a stale session from lingering after the server says it's over.
    func clearSession() {
        ride = nil
        members = []
        myMembership = nil
        errorMessage = nil
    }
}
