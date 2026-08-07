import CoreLocation
import MapboxMaps
import SwiftUI

enum MapViewportFollow {
    /// Browse / planner follow: course tracks travel direction (stable on a bike mount)
    /// instead of compass heading, which spins when the phone is still or magnetically noisy.
    ///
    /// - Parameter bottomPadding: Keep the puck in the visible map above bottom chrome
    ///   (search drawer, planner panel). Without this, follow centers under the overlay.
    static func live(
        zoom: CGFloat = 15.5,
        pitch: CGFloat = 0,
        bottomPadding: CGFloat = 24
    ) -> Viewport {
        .followPuck(zoom: zoom, bearing: .course, pitch: pitch)
            .padding(.bottom, bottomPadding)
    }

    static func recenter(_ viewport: Binding<Viewport>, bottomPadding: CGFloat = 24) {
        withViewportAnimation(.default(maxDuration: 1.2)) {
            viewport.wrappedValue = live(bottomPadding: bottomPadding)
        }
    }

    /// Centers and loosely zooms to frame a set of coordinates — used to bring every search
    /// result pin into view at once. The zoom is estimated from the coordinates' bounding-box
    /// span rather than an exact fit, which is precise enough for framing a handful of nearby
    /// POIs without depending on Turf geometry types.
    static func fit(_ coordinates: [CLLocationCoordinate2D], bottomPadding: CGFloat = 24) -> Viewport? {
        guard let first = coordinates.first else { return nil }
        guard coordinates.count > 1 else {
            return .camera(center: first, zoom: 15).padding(.bottom, bottomPadding)
        }

        var minLatitude = first.latitude, maxLatitude = first.latitude
        var minLongitude = first.longitude, maxLongitude = first.longitude
        for coordinate in coordinates.dropFirst() {
            minLatitude = min(minLatitude, coordinate.latitude)
            maxLatitude = max(maxLatitude, coordinate.latitude)
            minLongitude = min(minLongitude, coordinate.longitude)
            maxLongitude = max(maxLongitude, coordinate.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let span = max(maxLatitude - minLatitude, maxLongitude - minLongitude)

        let zoom: CGFloat
        switch span {
        case ..<0.003: zoom = 15
        case ..<0.01: zoom = 14
        case ..<0.03: zoom = 13
        case ..<0.08: zoom = 12
        case ..<0.2: zoom = 11
        default: zoom = 10
        }

        return .camera(center: center, zoom: zoom).padding(.bottom, bottomPadding)
    }
}
