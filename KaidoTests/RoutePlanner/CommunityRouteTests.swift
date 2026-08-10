@testable import Kaido
import XCTest

final class CommunityRouteTests: XCTestCase {
    func testOrderedWaypointsSortsRegardlessOfInputOrder() {
        let route = CommunityRoute.fixture(
            waypoints: [
                .init(latitude: 2, longitude: 2, order: 1),
                .init(latitude: 1, longitude: 1, order: 0),
                .init(latitude: 3, longitude: 3, order: 2)
            ]
        )

        XCTAssertEqual(route.orderedWaypoints.map(\.order), [0, 1, 2])
        XCTAssertEqual(route.coordinates.map(\.latitude), [1, 2, 3])
    }

    func testCodableRoundTrip() throws {
        let original = try XCTUnwrap(CuratedCommunityRoutes.all.first)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CommunityRoute.self, from: data)

        XCTAssertEqual(decoded, original)
    }
}

final class CuratedCommunityRoutesTests: XCTestCase {
    func testEveryRouteHasAtLeastTwoWaypointsAndPositiveDistance() {
        for route in CuratedCommunityRoutes.all {
            XCTAssertGreaterThanOrEqual(
                route.waypoints.count, 2,
                "\(route.name) needs at least 2 waypoints to draw a line"
            )
            XCTAssertGreaterThan(route.distanceMeters, 0)
            XCTAssertFalse(route.name.isEmpty)
        }
    }

    func testIdsAreUnique() {
        let ids = CuratedCommunityRoutes.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testEveryRouteIsPublishedAndAttributedToTheCuratorSentinel() {
        for route in CuratedCommunityRoutes.all {
            XCTAssertEqual(route.status, .published)
            XCTAssertEqual(route.authorUserId, CuratedCommunityRoutes.curatorUserId)
        }
    }

    func testStartCoordinateMatchesFirstOrderedWaypoint() {
        for route in CuratedCommunityRoutes.all {
            guard let firstWaypoint = route.orderedWaypoints.first else {
                XCTFail("\(route.name) has no waypoints")
                continue
            }
            XCTAssertEqual(route.startLatitude, firstWaypoint.latitude)
            XCTAssertEqual(route.startLongitude, firstWaypoint.longitude)
        }
    }
}

final class CommunityRouteServiceErrorMappingTests: XCTestCase {
    func testRowLevelSecurityWordingMapsToNotOwner() {
        XCTAssertEqual(
            SupabaseCommunityRouteService.classifyServerMessage(
                "new row violates row-level security policy for table \"community_routes\""
            ),
            .notOwner
        )
    }

    func testPermissionDeniedWordingMapsToNotOwner() {
        XCTAssertEqual(
            SupabaseCommunityRouteService.classifyServerMessage("permission denied for table community_routes"),
            .notOwner
        )
    }

    func testUnrecognizedMessageMapsToServerWithOriginalText() {
        XCTAssertEqual(
            SupabaseCommunityRouteService.classifyServerMessage("connection timed out"),
            .server("connection timed out")
        )
    }

    func testMappingIsCaseInsensitive() {
        XCTAssertEqual(
            SupabaseCommunityRouteService.classifyServerMessage("ROW-LEVEL SECURITY violation"),
            .notOwner
        )
    }
}

final class CompositeCommunityRouteServiceTests: XCTestCase {
    private struct DummyError: LocalizedError {
        var errorDescription: String? { "boom" }
    }

    func testFetchPublishedAppendsBackendRoutesAfterCurated() async throws {
        let curated = FakeCommunityRouteService()
        let backend = FakeCommunityRouteService()
        let curatedRoute = CommunityRoute.fixture(name: "Curated")
        let backendRoute = CommunityRoute.fixture(name: "Published by a rider")
        curated.fetchResult = .success([curatedRoute])
        backend.fetchResult = .success([backendRoute])
        let service = CompositeCommunityRouteService(curated: curated, backend: backend)

        let routes = try await service.fetchPublished(limit: 10)

        XCTAssertEqual(routes.map(\.name), ["Curated", "Published by a rider"])
    }

    func testFetchPublishedSwallowsNotConfiguredFromBackend() async throws {
        let curated = FakeCommunityRouteService()
        let backend = FakeCommunityRouteService()
        curated.fetchResult = .success([CommunityRoute.fixture()])
        backend.fetchResult = .failure(CommunityRouteServiceError.notConfigured)
        let service = CompositeCommunityRouteService(curated: curated, backend: backend)

        let routes = try await service.fetchPublished(limit: 10)

        XCTAssertEqual(routes.count, 1)
    }

    func testFetchPublishedPropagatesOtherBackendErrors() async {
        let curated = FakeCommunityRouteService()
        let backend = FakeCommunityRouteService()
        curated.fetchResult = .success([])
        backend.fetchResult = .failure(DummyError())
        let service = CompositeCommunityRouteService(curated: curated, backend: backend)

        await XCTAssertThrowsErrorAsync { try await service.fetchPublished(limit: 10) }
    }

    func testPublishAndRemoveDelegateToBackendOnly() async throws {
        let curated = FakeCommunityRouteService()
        let backend = FakeCommunityRouteService()
        let published = CommunityRoute.fixture(name: "New Route")
        backend.publishResult = .success(published)
        let service = CompositeCommunityRouteService(curated: curated, backend: backend)

        let result = try await service.publish(
            name: "New Route",
            description: nil,
            distanceMeters: 100,
            elevationGainMeters: 5,
            waypoints: [.init(latitude: 1, longitude: 1, order: 0)],
            displayName: "Rider"
        )
        XCTAssertEqual(result, published)
        XCTAssertEqual(backend.publishedName, "New Route")
        XCTAssertEqual(curated.publishedName, nil, "curated seed content is never published to")

        try await service.remove(routeId: published.id)
        XCTAssertEqual(backend.removedRouteId, published.id)
        XCTAssertNil(curated.removedRouteId, "curated seed content is never removed")
    }
}

@MainActor
final class CommunityRoutesViewModelTests: XCTestCase {
    private struct DummyError: LocalizedError {
        var errorDescription: String? { "boom" }
    }

    func testLoadPopulatesRoutesAndFetchesOnlyOnce() async {
        let service = FakeCommunityRouteService()
        service.fetchResult = .success(CuratedCommunityRoutes.all)
        let viewModel = CommunityRoutesViewModel(service: service, identityProvider: FakeGroupRideIdentityProvider())

        await viewModel.load()
        XCTAssertEqual(viewModel.routes.count, CuratedCommunityRoutes.all.count)
        XCTAssertEqual(service.fetchCallCount, 1)

        await viewModel.load()
        XCTAssertEqual(service.fetchCallCount, 1, "load() should only fetch once; use refresh() to reload")
    }

    func testRefreshAlwaysRefetches() async {
        let service = FakeCommunityRouteService()
        let viewModel = CommunityRoutesViewModel(service: service, identityProvider: FakeGroupRideIdentityProvider())

        await viewModel.refresh()
        await viewModel.refresh()

        XCTAssertEqual(service.fetchCallCount, 2)
    }

    func testFailureSurfacesErrorMessageAndClearsOnRetry() async {
        let service = FakeCommunityRouteService()
        service.fetchResult = .failure(DummyError())
        let viewModel = CommunityRoutesViewModel(service: service, identityProvider: FakeGroupRideIdentityProvider())

        await viewModel.refresh()
        XCTAssertEqual(viewModel.errorMessage, "boom")
        XCTAssertTrue(viewModel.routes.isEmpty)

        service.fetchResult = .success(CuratedCommunityRoutes.all)
        await viewModel.refresh()
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.routes.count, CuratedCommunityRoutes.all.count)
    }

    func testIsMineComparesAgainstResolvedCurrentUserId() async {
        let identity = FakeGroupRideIdentityProvider()
        let myRoute = CommunityRoute.fixture(authorUserId: identity.identity.userId)
        let someoneElsesRoute = CommunityRoute.fixture(authorUserId: UUID())
        let service = FakeCommunityRouteService()
        service.fetchResult = .success([myRoute, someoneElsesRoute])
        let viewModel = CommunityRoutesViewModel(service: service, identityProvider: identity)

        XCTAssertFalse(viewModel.isMine(myRoute), "before the first refresh, currentUserId hasn't resolved yet")

        await viewModel.load()

        XCTAssertTrue(viewModel.isMine(myRoute))
        XCTAssertFalse(viewModel.isMine(someoneElsesRoute))
    }

    func testPublishInsertsReturnedRouteAtFrontAndForwardsWaypoints() async throws {
        let route = Route(name: "My Loop", distanceMeters: 500, elevationGainMeters: 25)
        route.waypoints = [
            Waypoint(latitude: 2, longitude: 2, order: 1),
            Waypoint(latitude: 1, longitude: 1, order: 0)
        ]
        let service = FakeCommunityRouteService()
        service.fetchResult = .success([CommunityRoute.fixture(name: "Existing")])
        let published = CommunityRoute.fixture(name: "My Loop")
        service.publishResult = .success(published)
        let viewModel = CommunityRoutesViewModel(service: service, identityProvider: FakeGroupRideIdentityProvider())
        await viewModel.load()

        let result = try await viewModel.publish(from: route, description: "Fun ride", displayName: "Alex")

        XCTAssertEqual(result, published)
        XCTAssertEqual(viewModel.routes.first, published)
        XCTAssertEqual(service.publishedName, "My Loop")
        XCTAssertEqual(service.publishedDescription, "Fun ride")
        XCTAssertEqual(service.publishedDisplayName, "Alex")
        XCTAssertEqual(service.publishedWaypoints?.map(\.order), [0, 1])
        XCTAssertEqual(service.publishedWaypoints?.map(\.latitude), [1, 2])
    }

    func testRemoveDropsRouteFromListOnSuccess() async throws {
        let route = CommunityRoute.fixture(name: "Mine")
        let service = FakeCommunityRouteService()
        service.fetchResult = .success([route])
        let viewModel = CommunityRoutesViewModel(service: service, identityProvider: FakeGroupRideIdentityProvider())
        await viewModel.load()

        try await viewModel.remove(route)

        XCTAssertEqual(service.removedRouteId, route.id)
        XCTAssertTrue(viewModel.routes.isEmpty)
    }

    func testRemoveLeavesListUnchangedOnFailure() async {
        let route = CommunityRoute.fixture(name: "Mine")
        let service = FakeCommunityRouteService()
        service.fetchResult = .success([route])
        service.removeResult = .failure(DummyError())
        let viewModel = CommunityRoutesViewModel(service: service, identityProvider: FakeGroupRideIdentityProvider())
        await viewModel.load()

        await XCTAssertThrowsErrorAsync { try await viewModel.remove(route) }

        XCTAssertEqual(viewModel.routes.count, 1)
    }
}

// MARK: - Test doubles

private final class FakeCommunityRouteService: CommunityRouteService, @unchecked Sendable {
    var fetchResult: Result<[CommunityRoute], Error> = .success([])
    var publishResult: Result<CommunityRoute, Error> = .failure(CancellationError())
    var removeResult: Result<Void, Error> = .success(())

    private(set) var fetchCallCount = 0
    private(set) var publishedName: String?
    private(set) var publishedDescription: String?
    private(set) var publishedDisplayName: String?
    private(set) var publishedWaypoints: [CommunityRoute.Waypoint]?
    private(set) var removedRouteId: UUID?

    func fetchPublished(limit: Int) async throws -> [CommunityRoute] {
        fetchCallCount += 1
        return try fetchResult.get()
    }

    func publish(
        name: String,
        description: String?,
        distanceMeters: Double,
        elevationGainMeters: Double,
        waypoints: [CommunityRoute.Waypoint],
        displayName: String
    ) async throws -> CommunityRoute {
        publishedName = name
        publishedDescription = description
        publishedDisplayName = displayName
        publishedWaypoints = waypoints
        return try publishResult.get()
    }

    func remove(routeId: UUID) async throws {
        removedRouteId = routeId
        try removeResult.get()
    }
}

extension CommunityRoute {
    static func fixture(
        id: UUID = UUID(),
        authorUserId: UUID = UUID(),
        authorDisplayName: String = "Rider",
        name: String = "Test Route",
        description: String? = nil,
        distanceMeters: Double = 1_000,
        elevationGainMeters: Double = 10,
        waypoints: [CommunityRoute.Waypoint] = [
            .init(latitude: 1, longitude: 1, order: 0),
            .init(latitude: 2, longitude: 2, order: 1)
        ],
        status: CommunityRouteStatus = .published,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> CommunityRoute {
        let ordered = waypoints.sorted { $0.order < $1.order }
        return CommunityRoute(
            id: id,
            authorUserId: authorUserId,
            authorDisplayName: authorDisplayName,
            name: name,
            description: description,
            distanceMeters: distanceMeters,
            elevationGainMeters: elevationGainMeters,
            waypoints: waypoints,
            startLatitude: ordered.first?.latitude ?? 0,
            startLongitude: ordered.first?.longitude ?? 0,
            status: status,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }
}

/// XCTest doesn't ship an async `XCTAssertThrowsError` — this fills that gap for the
/// `async throws` service/view-model methods under test here.
private func XCTAssertThrowsErrorAsync<T>(
    file: StaticString = #filePath,
    line: UInt = #line,
    _ expression: () async throws -> T
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error to be thrown", file: file, line: line)
    } catch {
        // Expected.
    }
}
