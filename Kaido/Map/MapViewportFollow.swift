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

    /// Follow framing for a Free Ride camera mode. Same follow-puck behaviour, different
    /// zoom and pitch.
    static func live(camera: FreeRideCameraMode, bottomPadding: CGFloat = 24) -> Viewport {
        live(zoom: camera.zoom, pitch: camera.pitch, bottomPadding: bottomPadding)
    }

    static func recenter(
        _ viewport: Binding<Viewport>,
        camera: FreeRideCameraMode = .overhead,
        bottomPadding: CGFloat = 24
    ) {
        withViewportAnimation(.default(maxDuration: 1.2)) {
            viewport.wrappedValue = live(camera: camera, bottomPadding: bottomPadding)
        }
    }
}
