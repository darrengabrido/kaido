import CoreLocation
import Foundation
import MapboxMaps
import SwiftUI

/// Renders remote riders as markers on the *existing* navigation map — created once per
/// navigation session and diffed by stable member ID on every refresh tick, never rebuilding the
/// route line, maneuver UI, destination marker, or user puck Mapbox already owns.
///
/// Uses two small annotation managers (a colored circle per rider, a text label for their
/// initials) rather than one PointAnnotation with a composited image — this keeps the
/// implementation to Mapbox annotation APIs already exercised elsewhere in this codebase (see
/// `MapboxMapView`'s `CircleAnnotationGroup`/`PolylineAnnotationGroup` usage), just called
/// imperatively here since this overlay lives inside `NavigationSessionView`'s UIKit map rather
/// than the SwiftUI `Map` builder.
///
/// A rider's own marker is never drawn — Mapbox's own puck already represents the local user.
@MainActor
final class GroupRideMapOverlayController {
    private weak var mapView: MapView?
    private let sessionStore: GroupRideSessionStore
    private var circleManager: CircleAnnotationManager?
    private var labelManager: PointAnnotationManager?
    private var refreshTask: Task<Void, Never>?

    /// Set by the owner to present a rider card when a marker is tapped.
    var onSelectMember: ((UUID) -> Void)?

    init(mapView: MapView, sessionStore: GroupRideSessionStore) {
        self.mapView = mapView
        self.sessionStore = sessionStore

        let circles = mapView.annotations.makeCircleAnnotationManager(id: "ride-together-rider-circles")
        self.circleManager = circles
        let labels = mapView.annotations.makePointAnnotationManager(
            id: "ride-together-rider-labels",
            layerPosition: .above(circles.id)
        )
        self.labelManager = labels

        // These handlers are stored and later invoked by MapboxMaps, not necessarily from a
        // context the compiler already knows is main-actor — hop explicitly before touching
        // `self`, same as everywhere else this codebase bridges an SDK callback onto the actor.
        circles.tapHandler = { [weak self] annotations in
            let annotationId = annotations.first?.id
            Task { @MainActor in self?.handleTap(annotationId) }
            return true
        }
        labels.tapHandler = { [weak self] annotations in
            let annotationId = annotations.first?.id
            Task { @MainActor in self?.handleTap(annotationId) }
            return true
        }

        start()
    }

    func start() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Removes every marker and stops the refresh loop — call when navigation ends or the group
    /// session tears down, so stale riders never linger on a map that's about to be dismissed.
    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        circleManager?.annotations = []
        labelManager?.annotations = []
    }

    /// Frames the destination and every currently visible rider without permanently changing
    /// navigation-camera behavior — Mapbox's own active-guidance camera resumes following on the
    /// rider's next location update, since this only issues a one-shot `camera.ease(to:)`.
    func showGroup(destination: CLLocationCoordinate2D) {
        guard let mapView else { return }
        var coordinates = sessionStore.participantLocations.visibleLocations().map(\.coordinate)
        coordinates.append(destination)
        guard coordinates.count > 1 else { return }
        let cameraOptions = mapView.mapboxMap.camera(
            for: coordinates,
            padding: UIEdgeInsets(top: 100, left: 60, bottom: 260, right: 60),
            bearing: nil,
            pitch: nil
        )
        mapView.camera.ease(to: cameraOptions, duration: 0.6)
    }

    private func handleTap(_ annotationId: String?) {
        guard let annotationId, let memberId = UUID(uuidString: annotationId) else { return }
        onSelectMember?(memberId)
    }

    private func refresh() {
        let myUserId = sessionStore.currentUserId
        let members = Dictionary(uniqueKeysWithValues: sessionStore.members.map { ($0.userId, $0) })
        let now = Date()

        var circles: [CircleAnnotation] = []
        var labels: [PointAnnotation] = []

        for location in sessionStore.participantLocations.visibleLocations(now: now) {
            guard location.memberId != myUserId,
                  let member = members[location.memberId], member.isActive
            else { continue }

            let freshness = GroupRideMarkerFreshness.forAge(now.timeIntervalSince(location.lastUpdatedAt))
            let opacity: Double = freshness == .stale ? 0.5 : 1.0
            let idString = location.memberId.uuidString

            var circle = CircleAnnotation(id: idString, centerCoordinate: location.coordinate)
            circle.circleColor = StyleColor(UIColor(GroupRideAvatarStyle.color(for: member.avatarSeed)))
            circle.circleRadius = 13
            circle.circleStrokeColor = StyleColor(member.isHost ? .white : UIColor(white: 1, alpha: 0.85))
            circle.circleStrokeWidth = member.isHost ? 3 : 1.5
            circle.circleOpacity = opacity
            circle.circleEmissiveStrength = 1
            circles.append(circle)

            var label = PointAnnotation(id: idString, coordinate: location.coordinate)
            label.textField = GroupRideAvatarStyle.initials(for: member.displayName)
            label.textSize = 11
            label.textColor = StyleColor(.white)
            label.textOpacity = opacity
            label.textAllowOverlap = true
            labels.append(label)
        }

        circleManager?.annotations = circles
        labelManager?.annotations = labels
    }
}
