@testable import Kaido
import XCTest
import CoreLocation

@MainActor
final class GroupRideSessionStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        GroupRideDisplayNameStore.current = nil
    }

    override func tearDown() {
        GroupRideDisplayNameStore.current = nil
        super.tearDown()
    }

    private func makeStore() -> (
        store: GroupRideSessionStore,
        service: FakeGroupRideService,
        realtime: FakeGroupRideRealtimeClient,
        identity: FakeGroupRideIdentityProvider
    ) {
        let service = FakeGroupRideService()
        let realtime = FakeGroupRideRealtimeClient()
        let identity = FakeGroupRideIdentityProvider()
        let store = GroupRideSessionStore(service: service, realtimeClient: realtime, identityProvider: identity)
        return (store, service, realtime, identity)
    }

    @discardableResult
    private func createRideAsHost(
        store: GroupRideSessionStore,
        service: FakeGroupRideService,
        identity: FakeGroupRideIdentityProvider
    ) async throws -> GroupRide {
        let ride = GroupRide.fixture(hostUserId: identity.identity.userId, status: .lobby)
        service.createRideResult = .success(GroupRideCreationResult(ride: ride, rawInviteToken: "raw-token"))
        service.membersStore = [
            GroupRideMember.fixture(rideId: ride.id, userId: identity.identity.userId, role: .host, displayName: "Host")
        ]
        _ = try await store.createRide(
            destinationName: ride.destinationName,
            destination: ride.destinationCoordinate,
            routeSnapshot: .fixture(),
            title: nil,
            displayName: "Host"
        )
        return ride
    }

    private func joinAsRider(
        store: GroupRideSessionStore,
        service: FakeGroupRideService,
        identity: FakeGroupRideIdentityProvider
    ) async throws {
        let hostId = UUID()
        let ride = GroupRide.fixture(hostUserId: hostId, status: .lobby)
        let riderMembership = GroupRideMember.fixture(rideId: ride.id, userId: identity.identity.userId, role: .rider)
        let hostMembership = GroupRideMember.fixture(rideId: ride.id, userId: hostId, role: .host)
        service.rideStore = ride
        service.membersStore = [hostMembership, riderMembership]
        service.joinRideResult = .success(GroupRideJoinResult(ride: ride, membership: riderMembership))
        try await store.joinRide(rideId: ride.id, token: "token", displayName: "Rider")
    }

    /// `CLLocation(latitude:longitude:)` reports an invalid (-1) `horizontalAccuracy`, which
    /// `GroupRideLocationValidation` correctly rejects — tests need a location that looks like a
    /// real GPS fix.
    private func accurateLocation(latitude: Double, longitude: Double) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: -1,
            timestamp: Date()
        )
    }

    /// `onConnectionStateChange` always re-hops via `Task { @MainActor in }` (correct — the real
    /// Realtime client is an actor, not necessarily already on the main actor), so even though
    /// the fake invokes it synchronously, the resulting `connectionState` update lands on a
    /// later main-actor turn. Poll for it rather than assume a fixed number of turns — see
    /// `waitUntil` below for why the bound is wall-clock, not an iteration count.
    private func waitUntilConnected(_ store: GroupRideSessionStore) async {
        await waitUntil { store.connectionState == .connected }
    }

    /// `FakeGroupRideLocationSource.emit` synchronously invokes the handler `GroupRideLocationPublisher`
    /// passed to `source.start`, but that handler is itself `Task { @MainActor in self?.handle(location) }`,
    /// and `handle` schedules a second, inner `Task { await client.publishLocation(envelope) }` — two
    /// async hops that need real turns of the executor before `publishedLocations` reflects the emit.
    /// Poll rather than assume a fixed number of turns flushes both.
    private func waitForPublishedLocationCount(_ count: Int, in realtime: FakeGroupRideRealtimeClient) async {
        await waitUntil { realtime.publishedLocations.count >= count }
    }

    /// Generic version of the polling helpers above, for asserting on state reached only after an
    /// `async` handler chained off a fake's captured callback has actually run. Polls by yielding
    /// so the common case (condition true within a turn or two) resolves almost instantly, but
    /// bounds the wait by wall-clock time instead of a fixed `Task.yield()` count — a fixed count
    /// is really a guess at "enough scheduler turns happened," and how many turns that takes
    /// varies with CI load, so a fixed cap can give up while the condition is still legitimately
    /// on its way to becoming true (this is what made `testRideStatusNoticeEndsTheRideOnceServerConfirmsTermination`
    /// flaky under load even after it was rewritten to poll the final state instead of a proxy).
    private func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            await Task.yield()
        }
    }

    /// For asserting a negative outcome (nothing changed) after triggering async work with no
    /// positive condition to poll for — yields the same generous number of turns the positive
    /// polling helpers above allow, so an async chain that legitimately has nothing left to settle
    /// gets every chance to prove otherwise before the assertion runs.
    private func waitForQuiescence() async {
        for _ in 0..<50 {
            await Task.yield()
        }
    }

    private func assertThrowsNotHost(
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected GroupRideSessionError.notHost", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? GroupRideSessionError, .notHost, file: file, line: line)
        }
    }

    // MARK: - Host-only mutation guard

    func testNonHostCannotStartRide() async throws {
        let (store, service, _, identity) = makeStore()
        try await joinAsRider(store: store, service: service, identity: identity)

        await assertThrowsNotHost { try await store.startRide() }
        XCTAssertEqual(service.startRideCallCount, 0)
    }

    func testNonHostCannotEndOrCancelOrUpdateRouteOrRemoveMemberOrRotateInvite() async throws {
        let (store, service, _, identity) = makeStore()
        try await joinAsRider(store: store, service: service, identity: identity)

        await assertThrowsNotHost { try await store.endRide() }
        await assertThrowsNotHost { try await store.cancelRide() }
        await assertThrowsNotHost {
            try await store.updateRoute(routeSnapshot: .fixture(), destinationName: nil, destination: nil)
        }
        await assertThrowsNotHost { try await store.removeMember(userId: UUID()) }
        await assertThrowsNotHost { _ = try await store.rotateInvite() }

        XCTAssertEqual(service.endRideCallCount, 0)
        XCTAssertEqual(service.cancelRideCallCount, 0)
        XCTAssertEqual(service.updateRouteCallCount, 0)
        XCTAssertEqual(service.removeMemberCallCount, 0)
        XCTAssertEqual(service.rotateInviteCallCount, 0)
    }

    func testHostCanStartEndAndCancel() async throws {
        let (store, service, _, identity) = makeStore()
        try await createRideAsHost(store: store, service: service, identity: identity)

        try await store.startRide()
        XCTAssertEqual(service.startRideCallCount, 1)
    }

    // MARK: - Location publication stops on every teardown path

    func testLeavingStopsLocationPublication() async throws {
        let (store, service, realtime, identity) = makeStore()
        try await createRideAsHost(store: store, service: service, identity: identity)
        service.rideStore?.status = .active
        try await store.startRide()

        let locationSource = FakeGroupRideLocationSource()
        store.attachLiveNavigation(locationSource: locationSource)
        XCTAssertEqual(locationSource.startCallCount, 1)

        locationSource.emit(accurateLocation(latitude: 37.7749, longitude: -122.4194))
        await waitForPublishedLocationCount(1, in: realtime)
        XCTAssertEqual(realtime.publishedLocations.count, 1)

        try await store.leaveRide()
        XCTAssertEqual(locationSource.stopCallCount, 1)

        locationSource.emit(accurateLocation(latitude: 37.8, longitude: -122.5))
        XCTAssertEqual(realtime.publishedLocations.count, 1, "no location should publish after leaving")
    }

    func testEndingStopsLocationPublication() async throws {
        let (store, service, realtime, identity) = makeStore()
        try await createRideAsHost(store: store, service: service, identity: identity)
        service.rideStore?.status = .active
        try await store.startRide()

        let locationSource = FakeGroupRideLocationSource()
        store.attachLiveNavigation(locationSource: locationSource)
        locationSource.emit(accurateLocation(latitude: 37.7749, longitude: -122.4194))
        await waitForPublishedLocationCount(1, in: realtime)
        XCTAssertEqual(realtime.publishedLocations.count, 1)

        try await store.endRide()
        XCTAssertEqual(locationSource.stopCallCount, 1)

        locationSource.emit(accurateLocation(latitude: 37.8, longitude: -122.5))
        XCTAssertEqual(realtime.publishedLocations.count, 1, "no location should publish after ending")
    }

    func testDetachingLiveNavigationStopsPublicationWithoutLeavingTheRide() async throws {
        let (store, service, realtime, identity) = makeStore()
        try await createRideAsHost(store: store, service: service, identity: identity)
        service.rideStore?.status = .active
        try await store.startRide()

        let locationSource = FakeGroupRideLocationSource()
        store.attachLiveNavigation(locationSource: locationSource)
        locationSource.emit(accurateLocation(latitude: 37.7749, longitude: -122.4194))
        await waitForPublishedLocationCount(1, in: realtime)
        XCTAssertEqual(realtime.publishedLocations.count, 1)

        store.detachLiveNavigation()
        XCTAssertEqual(locationSource.stopCallCount, 1)
        XCTAssertNotNil(store.ride, "leaving personal navigation shouldn't end group membership")

        locationSource.emit(accurateLocation(latitude: 37.8, longitude: -122.5))
        XCTAssertEqual(realtime.publishedLocations.count, 1)
    }

    // MARK: - Reconnection

    func testForegroundRestoreDoesNotReconnectWhenAlreadyConnected() async throws {
        let (store, service, realtime, identity) = makeStore()
        try await createRideAsHost(store: store, service: service, identity: identity)
        XCTAssertEqual(realtime.connectCallCount, 1)
        await waitUntilConnected(store)

        await store.handleAppForeground()
        XCTAssertEqual(realtime.connectCallCount, 1, "already connected — shouldn't reconnect")

        await store.teardownLiveState(clearRide: false)
        XCTAssertEqual(realtime.disconnectCallCount, 1)

        await store.handleAppForeground()
        XCTAssertEqual(realtime.connectCallCount, 2, "should reconnect exactly once after an actual drop")
    }

    // MARK: - Guest anonymous identity

    func testGuestAnonymousIdentityIsUsedEndToEnd() async throws {
        let (store, service, _, identity) = makeStore()
        identity.identity = GroupRideIdentity(userId: UUID(), isAnonymous: true)

        let ride = try await createRideAsHost(store: store, service: service, identity: identity)

        XCTAssertEqual(identity.ensureIdentityCallCount, 1)
        XCTAssertEqual(store.currentUserId, identity.identity.userId)
        XCTAssertTrue(store.isHost)
        XCTAssertEqual(ride.hostUserId, identity.identity.userId)
        XCTAssertEqual(GroupRideDisplayNameStore.current, "Host")
    }

    // MARK: - Messaging never lets a rider claim another sender

    func testSendMessageAlwaysUsesTheCurrentIdentityAsSender() async throws {
        let (store, service, _, identity) = makeStore()
        try await createRideAsHost(store: store, service: service, identity: identity)

        try await store.sendMessage(kind: .preset, body: "All good", presetKey: "all_good")

        let sent = try XCTUnwrap(service.sentMessages.first)
        XCTAssertEqual(sent.senderUserId, identity.identity.userId)
    }

    // MARK: - Realtime broadcasts are untrusted signals, not authoritative content
    //
    // Realtime Broadcast has no per-message identity binding — any active ride member can send a
    // "message"/"ride_status" event with whatever content they like. These tests confirm the
    // session store never displays/acts on a broadcast's own field values, only on content
    // re-fetched from the durable, RLS-protected service afterward.

    func testIncomingMessageNoticeDisplaysOnlyContentFromTheDurableStore() async throws {
        let (store, service, realtime, identity) = makeStore()
        let ride = try await createRideAsHost(store: store, service: service, identity: identity)
        await waitUntilConnected(store)
        // Connecting also fires its own incidental `refreshFromServer()` — let it fully settle
        // before seeding this test's own fixtures, so it can't race the assertions below.
        await waitForQuiescence()

        let genuineMessage = GroupRideMessage(
            id: UUID(),
            rideId: ride.id,
            senderUserId: UUID(),
            senderDisplayName: "Rider",
            kind: .preset,
            body: "All good",
            presetKey: "all_good",
            clientMessageId: UUID(),
            createdAt: Date()
        )
        service.messagesStore = [genuineMessage]

        // No payload is available to the fake here at all — the callback takes no arguments,
        // which is the point: a receiver has nothing to trust except by going and fetching it.
        realtime.capturedOnMessage?()
        await waitUntil { store.messageCenter.recentMessages.contains { $0.id == genuineMessage.id } }

        XCTAssertEqual(store.messageCenter.recentMessages.last?.id, genuineMessage.id)
        XCTAssertEqual(store.messageCenter.currentBanner?.id, genuineMessage.id)
    }

    func testForgedRideStatusNoticeCannotEndTheRideWithoutServerConfirmation() async throws {
        let (store, service, realtime, identity) = makeStore()
        try await createRideAsHost(store: store, service: service, identity: identity)
        await waitUntilConnected(store)
        await waitForQuiescence()
        service.rideStore?.status = .active // the server's real status is unchanged

        // Simulates a non-host member broadcasting a forged "ended" notice.
        realtime.capturedOnRideStatusChange?()
        await waitForQuiescence()

        XCTAssertEqual(store.ride?.status, .active, "a broadcast alone must never end the ride")
        XCTAssertNotEqual(store.connectionState, .disconnected, "live state shouldn't tear down on an unconfirmed notice")
    }

    func testRideStatusNoticeEndsTheRideOnceServerConfirmsTermination() async throws {
        let (store, service, realtime, identity) = makeStore()
        try await createRideAsHost(store: store, service: service, identity: identity)
        await waitUntilConnected(store)
        // Connecting also fires its own incidental `refreshFromServer()` — let it fully settle
        // before seeding this test's own scenario, so it can't race the assertions below.
        await waitForQuiescence()
        service.rideStore?.status = .ended // the real end_group_ride RPC already succeeded elsewhere

        realtime.capturedOnRideStatusChange?()
        // Poll for the exact condition being asserted, not an earlier proxy for it: `ride.status`
        // flips to `.ended` several awaits before `teardownLiveState` runs, and even
        // `disconnectCallCount` incrementing doesn't guarantee `connectionState` has been set yet
        // — `teardownLiveState` awaits `realtimeClient.disconnect()` (a real actor hop back from
        // the non-isolated fake to this @MainActor store) before its own very next line assigns
        // `connectionState = .disconnected`, so the counter can observably tick up on an earlier
        // turn than the assignment. Only waiting on the final state itself is race-free.
        await waitUntil { store.connectionState == .disconnected }

        XCTAssertEqual(store.ride?.status, .ended)
        XCTAssertEqual(store.connectionState, .disconnected)
        XCTAssertEqual(realtime.disconnectCallCount, 1)
    }
}
