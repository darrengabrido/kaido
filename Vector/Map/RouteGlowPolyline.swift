import SwiftUI
import CoreLocation
import MapboxMaps

/// The user's route drawn with a soft violet glow: a wide, blurred halo underneath a thicker
/// core line. Both are placed in the `.middle` slot so the bike-lane layers (which live in the
/// `.top` slot) render crisply over the route wherever they share the road — the lane markings
/// stay visible along the route instead of being washed out beneath it.
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
        .slot(.middle)

        // Core — bold; the lane layers draw above it, so it doesn't need to be see-through.
        PolylineAnnotationGroup {
            PolylineAnnotation(lineCoordinates: coordinates)
                .lineColor(UIColor(Color.vectorVioletOnMap))
                .lineWidth(6)
                .lineOpacity(0.8)
        }
        .lineEmissiveStrength(1)
        .slot(.middle)
    }
}
