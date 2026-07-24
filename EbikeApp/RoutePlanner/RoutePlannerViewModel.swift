import Foundation
import CoreLocation

@Observable
final class RoutePlannerViewModel {
    var waypoints: [PlannerWaypoint] = []
    var isSnapEnabled = false
    var snappedCoordinates: [CLLocationCoordinate2D]?
    var snappedDistanceMeters: Double?
    var isMatching = false
    var matchingError: String?

    private let mapMatchingService = MapMatchingService()

    var rawDistanceMeters: Double {
        guard waypoints.count > 1 else { return 0 }
        var total = 0.0
        for index in 1..<waypoints.count {
            let previous = CLLocation(
                latitude: waypoints[index - 1].coordinate.latitude,
                longitude: waypoints[index - 1].coordinate.longitude
            )
            let current = CLLocation(
                latitude: waypoints[index].coordinate.latitude,
                longitude: waypoints[index].coordinate.longitude
            )
            total += previous.distance(from: current)
        }
        return total
    }

    var displayDistanceMeters: Double {
        if isSnapEnabled, let snappedDistanceMeters {
            return snappedDistanceMeters
        }
        return rawDistanceMeters
    }

    var lineCoordinates: [CLLocationCoordinate2D] {
        if isSnapEnabled, let snappedCoordinates {
            return snappedCoordinates
        }
        return waypoints.map(\.coordinate)
    }

    func addWaypoint(at coordinate: CLLocationCoordinate2D) {
        waypoints.append(PlannerWaypoint(coordinate: coordinate))
        invalidateSnap()
    }

    func removeWaypoint(id: PlannerWaypoint.ID) {
        waypoints.removeAll { $0.id == id }
        invalidateSnap()
    }

    func removeLast() {
        _ = waypoints.popLast()
        invalidateSnap()
    }

    func clear() {
        waypoints.removeAll()
        invalidateSnap()
    }

    private func invalidateSnap() {
        snappedCoordinates = nil
        snappedDistanceMeters = nil
        matchingError = nil
    }

    @MainActor
    func snapToRoads() async {
        guard waypoints.count > 1 else { return }
        isMatching = true
        matchingError = nil
        defer { isMatching = false }
        do {
            let result = try await mapMatchingService.match(coordinates: waypoints.map(\.coordinate))
            snappedCoordinates = result.coordinates
            snappedDistanceMeters = result.distanceMeters
        } catch {
            matchingError = error.localizedDescription
        }
    }
}
