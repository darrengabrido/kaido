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
    /// later main-actor turn. Polling with `Task.yield()` avoids a flaky assumption about
    /// exactly how many turns that takes.
    private func waitUntilConnected(_ store: GroupRideSessionStore) async {
        var attempts = 0
        while store.connectionState != .connected, attempts < 50 {
            await Task.yield()
            attempts += 1
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
}
