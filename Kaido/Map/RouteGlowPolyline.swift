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
                .lineColor(UIColor(Color.kaidoVioletOnMap))
                .lineWidth(12)
                .lineBlur(8)
                .lineOpacity(0.4)
        }
        .lineEmissiveStrength(1)
        .slot(.middle)

        // Core — slightly translucent so teal lane markings above it still feel woven into
        // the route instead of pasted on top of a solid bar.
        PolylineAnnotationGroup {
            PolylineAnnotation(lineCoordinates: coordinates)
                .lineColor(UIColor(Color.kaidoVioletOnMap))
                .lineWidth(6)
                .lineOpacity(0.72)
        }
        .lineEmissiveStrength(1)
        .slot(.middle)
    }
}
