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
}
