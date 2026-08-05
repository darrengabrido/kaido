import MapboxMaps
import SwiftUI

/// The live Mapbox surface (puck, bike lanes, destination pin, route lines) as its own view.
///
/// Pulled out of `MapboxMapView` so the map — the most expensive thing on screen — isn't
/// reconstructed as part of the same body as the search drawer's drag gesture. `MapboxMapView`
/// still re-evaluates its body on every drag frame (unavoidable, since it owns the gesture
/// state), but as long as this view's own parameters are unchanged between two of those
/// evaluations, SwiftUI recognizes the reconstructed value as equivalent and skips re-rendering
/// this subtree — which is what makes the drawer track the finger instead of fighting the map
/// for a frame budget.
struct KaidoMapCanvas: View {
    @Binding var viewport: Viewport
    let showBikeLanes: Bool
    let selectedDestination: SearchResult?
    let routeOptions: [RouteOption]

    var body: some View {
        Map(viewport: $viewport) {
            // Course matches travel direction used by follow-puck; heading made the
            // puck spin when the phone was still or magnetically noisy on a mount.
            Puck2D(bearing: .course)
                .bearingImage(BikePuckImage.bearing)
                .pulsing(BikePuckImage.pulsing)

            if showBikeLanes {
                BikeLaneMapLayers()
            }

            if let selectedDestination {
                CircleAnnotationGroup([selectedDestination]) { result in
                    CircleAnnotation(centerCoordinate: result.coordinate)
                        // The destination pin is the one marker that must not recede into the
                        // neutrals — clay reads warm against the violet route and sage lanes.
                        .circleColor(UIColor(Color.statusCritical))
                        .circleRadius(8)
                        .circleStrokeColor(.white)
                        .circleStrokeWidth(2)
                }
                .circleEmissiveStrength(1)
            }

            // Draw alternates first. Their distinct colours keep choices legible, while a
            // narrow, translucent stroke makes the selected violet route the visual focus.
            PolylineAnnotationGroup(
                routeOptions.filter { !$0.isMain && $0.coordinates.count > 1 }
            ) { option in
                PolylineAnnotation(lineCoordinates: option.coordinates)
                    .lineColor(UIColor(MapboxMapView.routeColor(for: option, in: routeOptions)))
                    .lineWidth(2.5)
            }
            .lineOpacity(0.38)
            .lineEmissiveStrength(0.6)

            if let mainRoute = routeOptions.first(where: { $0.isMain && $0.coordinates.count > 1 }) {
                RouteGlowPolyline(coordinates: mainRoute.coordinates)
            }
        }
        .mapStyle(.kaidoNight)
        .ornamentOptions(OrnamentOptions(
            scaleBar: ScaleBarViewOptions(visibility: .hidden),
            // Search and saved places live in the bottom drawer, leaving the map's top edge
            // available for ornaments.
            compass: CompassViewOptions(
                position: .topLeading,
                margins: CGPoint(x: 16, y: 16)
            )
        ))
        .ignoresSafeArea()
    }
}
