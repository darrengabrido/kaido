@testable import Kaido
import XCTest

final class CommunityRouteTests: XCTestCase {
    func testOrderedWaypointsSortsRegardlessOfInputOrder() {
        let route = CommunityRoute(
            id: UUID(),
            name: "Test Loop",
            description: nil,
            areaName: nil,
            curatorName: "Kaido",
            distanceMeters: 1_000,
            elevationGainMeters: 10,
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
}

@MainActor
final class CommunityRoutesViewModelTests: XCTestCase {
    private final class FakeCommunityRouteService: CommunityRouteService, @unchecked Sendable {
        var result: Result<[CommunityRoute], Error> = .success([])
        private(set) var fetchCallCount = 0

        func fetchCuratedRoutes() async throws -> [CommunityRoute] {
            fetchCallCount += 1
            return try result.get()
        }
    }

    private struct DummyError: LocalizedError {
        var errorDescription: String? { "boom" }
    }

    func testLoadPopulatesRoutesAndFetchesOnlyOnce() async {
        let service = FakeCommunityRouteService()
        service.result = .success(CuratedCommunityRoutes.all)
        let viewModel = CommunityRoutesViewModel(service: service)

        await viewModel.load()
        XCTAssertEqual(viewModel.routes.count, CuratedCommunityRoutes.all.count)
        XCTAssertEqual(service.fetchCallCount, 1)

        await viewModel.load()
        XCTAssertEqual(service.fetchCallCount, 1, "load() should only fetch once; use refresh() to reload")
    }

    func testRefreshAlwaysRefetches() async {
        let service = FakeCommunityRouteService()
        let viewModel = CommunityRoutesViewModel(service: service)

        await viewModel.refresh()
        await viewModel.refresh()

        XCTAssertEqual(service.fetchCallCount, 2)
    }

    func testFailureSurfacesErrorMessageAndClearsOnRetry() async {
        let service = FakeCommunityRouteService()
        service.result = .failure(DummyError())
        let viewModel = CommunityRoutesViewModel(service: service)

        await viewModel.refresh()
        XCTAssertEqual(viewModel.errorMessage, "boom")
        XCTAssertTrue(viewModel.routes.isEmpty)

        service.result = .success(CuratedCommunityRoutes.all)
        await viewModel.refresh()
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.routes.count, CuratedCommunityRoutes.all.count)
    }
}
