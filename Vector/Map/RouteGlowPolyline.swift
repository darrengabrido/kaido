import SwiftUI
import CoreLocation
import MapboxMaps

/// The user's route drawn with a soft violet glow: a wide, blurred halo underneath a thicker,
/// semi-transparent core line. The core's transparency lets the teal bike-lane layers stay
/// readable wherever the route runs along one, and the halo keeps the route eye-catching
/// against the dimmed night map.
struct RouteGlowPolyline: MapContent {
    let coordinates: [CLLocationCoordinate2D]

    var body: some MapContent {
        // Halo — wide and heavily blurred so it reads as a glow, not a border.
        PolylineAnnotationGroup {
            PolylineAnnotation(lineCoordinates: coordinates)
                .lineColor(UIColor(Color.vectorVioletOnMap))
                .lineWidth(12)
                .lineBlur(8)
                .lineOpacity(0.4)
        }
        .lineEmissiveStrength(1)

        // Core — thick enough to dominate, transparent enough that lanes show through.
        PolylineAnnotationGroup {
            PolylineAnnotation(lineCoordinates: coordinates)
                .lineColor(UIColor(Color.vectorVioletOnMap))
                .lineWidth(6)
                .lineOpacity(0.65)
        }
        .lineEmissiveStrength(1)
    }
}
