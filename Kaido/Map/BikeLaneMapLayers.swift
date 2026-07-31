import SwiftUI
import MapboxMaps

/// Bike infrastructure drawn above the route (`.top` slot) so lane markings stay visible
/// wherever they share the road with the violet glow. A dark casing + luminous mint core
/// keeps them readable on the night basemap *and* when they sit on top of the route.
struct BikeLaneMapLayers: MapContent {
    var body: some MapContent {
        VectorSource(id: "streets-v8")
            .url("mapbox://mapbox.mapbox-streets-v8")

        // MARK: On-street painted bike lane
        // Soft halo so dashes don't vanish against dark asphalt or the route glow.
        LineLayer(id: "bike-onstreet-halo", source: "streets-v8")
            .sourceLayer("road")
            .filter(Self.onStreetFilter)
            .lineColor(StyleColor(UIColor(Color.routeTealOnMap)))
            .lineWidth(7)
            .lineOpacity(0.28)
            .lineBlur(2.5)
            .lineEmissiveStrength(1)
            .lineCap(.butt)
            .lineJoin(.round)
            .lineDashArray([3, 2.5])
            .slot(.top)

        // Dark casing — silhouette against violet route segments.
        LineLayer(id: "bike-onstreet-casing", source: "streets-v8")
            .sourceLayer("road")
            .filter(Self.onStreetFilter)
            .lineColor(StyleColor(UIColor(Color.kaidoMidnight)))
            .lineWidth(5)
            .lineOpacity(0.55)
            .lineEmissiveStrength(0)
            .lineCap(.butt)
            .lineJoin(.round)
            .lineDashArray([3, 2.5])
            .slot(.top)

        LineLayer(id: "bike-onstreet-lane", source: "streets-v8")
            .sourceLayer("road")
            .filter(Self.onStreetFilter)
            .lineColor(StyleColor(UIColor(Color.routeTealOnMap)))
            .lineWidth(3.5)
            .lineOpacity(1)
            .lineEmissiveStrength(1)
            .lineCap(.butt)
            .lineJoin(.round)
            .lineDashArray([3, 2.5])
            .slot(.top)

        // MARK: Dedicated cycle path
        LineLayer(id: "bike-dedicated-halo", source: "streets-v8")
            .sourceLayer("road")
            .filter(Self.dedicatedFilter)
            .lineColor(StyleColor(UIColor(Color.routeTealOnMap)))
            .lineWidth(12)
            .lineOpacity(0.32)
            .lineBlur(4)
            .lineEmissiveStrength(1)
            .lineCap(.round)
            .lineJoin(.round)
            .slot(.top)

        LineLayer(id: "bike-dedicated-casing", source: "streets-v8")
            .sourceLayer("road")
            .filter(Self.dedicatedFilter)
            .lineColor(StyleColor(UIColor(Color.kaidoMidnight)))
            .lineWidth(7.5)
            .lineOpacity(0.6)
            .lineEmissiveStrength(0)
            .lineCap(.round)
            .lineJoin(.round)
            .slot(.top)

        LineLayer(id: "bike-dedicated-path", source: "streets-v8")
            .sourceLayer("road")
            .filter(Self.dedicatedFilter)
            .lineColor(StyleColor(UIColor(Color.routeTealOnMap)))
            .lineWidth(5)
            .lineOpacity(1)
            .lineEmissiveStrength(1)
            .lineCap(.round)
            .lineJoin(.round)
            .slot(.top)
    }

    private static var onStreetFilter: Exp {
        Exp(.any) {
            Exp(.eq) { Exp(.get) { "bike_lane" }; "yes" }
            Exp(.eq) { Exp(.get) { "bike_lane" }; "left" }
            Exp(.eq) { Exp(.get) { "bike_lane" }; "right" }
            Exp(.eq) { Exp(.get) { "bike_lane" }; "both" }
        }
    }

    private static var dedicatedFilter: Exp {
        Exp(.eq) { Exp(.get) { "type" }; "cycleway" }
    }
}
