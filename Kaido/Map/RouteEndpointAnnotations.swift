import SwiftUI
import CoreLocation
import MapboxMaps

/// Start ("A") and end ("B") markers for a route overview — lets a rider orient a saved or
/// previewed route at a glance, the way Google Maps labels the two ends of a trip. Without these,
/// a route drawn on the map is just a line with no sense of direction or where it begins.
struct RouteEndpointAnnotations: MapContent {
    let coordinates: [CLLocationCoordinate2D]

    var body: some MapContent {
        if coordinates.count > 1, let start = coordinates.first, let end = coordinates.last {
            MapViewAnnotation(coordinate: start) {
                RouteEndpointMarker(label: "A", color: .statusGood)
            }
            .allowOverlap(true)

            MapViewAnnotation(coordinate: end) {
                RouteEndpointMarker(label: "B", color: .statusCritical)
            }
            .allowOverlap(true)
        }
    }
}

private struct RouteEndpointMarker: View {
    let label: String
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .overlay {
                    Circle().stroke(Color.white, lineWidth: 2)
                }
                .frame(width: 24, height: 24)
                .shadow(color: .black.opacity(0.32), radius: 3, y: 1)

            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.white)
        }
        .accessibilityLabel(label == "A" ? "Route start" : "Route end")
    }
}
