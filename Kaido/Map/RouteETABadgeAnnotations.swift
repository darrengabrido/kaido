import SwiftUI
import CoreLocation
import MapboxMaps

/// Floating ETA pills over each route option, positioned near the route's geometric midpoint —
/// tap one to make it the active route. Lets a rider compare alternatives without opening the
/// drawer, the way Google Maps labels alternate routes directly on the map. The in-drawer route
/// list stays too: duration alone on a map pill doesn't carry the quiet/mixed/busy read, so the
/// two views serve different comparisons rather than duplicating one.
struct RouteETABadgeAnnotations: MapContent {
    let routeOptions: [RouteOption]
    let onSelect: (RouteOption) -> Void

    var body: some MapContent {
        ForEvery(routeOptions.filter { $0.coordinates.count > 1 }, id: \.id) { option in
            if let midpoint = Self.midpoint(of: option.coordinates) {
                MapViewAnnotation(coordinate: midpoint) {
                    RouteETABadge(
                        text: MapboxMapView.formattedDuration(option.personalizedTravelTime),
                        isMain: option.isMain,
                        color: MapboxMapView.routeColor(for: option, in: routeOptions)
                    ) {
                        onSelect(option)
                    }
                }
                .allowOverlap(true)
            }
        }
    }

    /// A coordinate near the route's halfway point *by distance*, not by vertex count — routes
    /// have uneven vertex spacing, so the middle array index can sit well off-centre. Walks the
    /// coordinate pairs accumulating straight-line distance and interpolates once it crosses half
    /// the total.
    static func midpoint(of coordinates: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
        guard coordinates.count > 1 else { return coordinates.first }
        let locations = coordinates.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        let segmentLengths = zip(locations, locations.dropFirst()).map { $0.distance(from: $1) }
        let total = segmentLengths.reduce(0, +)
        guard total > 0 else { return coordinates.first }

        let half = total / 2
        var travelled: CLLocationDistance = 0
        for (index, length) in segmentLengths.enumerated() {
            if travelled + length >= half {
                let remaining = half - travelled
                let fraction = length > 0 ? remaining / length : 0
                let start = coordinates[index]
                let end = coordinates[index + 1]
                return CLLocationCoordinate2D(
                    latitude: start.latitude + (end.latitude - start.latitude) * fraction,
                    longitude: start.longitude + (end.longitude - start.longitude) * fraction
                )
            }
            travelled += length
        }
        return coordinates.last
    }
}

/// Violet for the selected route, its own route colour outlined for alternatives — same
/// language as `routeColor(for:in:)` everywhere else routes are compared in this app.
private struct RouteETABadge: View {
    let text: String
    let isMain: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isMain ? Color.kaidoInk : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isMain ? color : Color.kaidoMidnight.opacity(0.92), in: Capsule())
                .overlay {
                    Capsule().stroke(isMain ? Color.clear : color.opacity(0.6), lineWidth: 1.5)
                }
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(text) route\(isMain ? ", currently selected" : "")")
        .accessibilityHint(isMain ? "" : "Double tap to use this route")
    }
}
