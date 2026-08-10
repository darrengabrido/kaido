import Foundation

/// Climb/descent summary for a sampled route polyline, including heights for a sparkline.
struct ElevationProfile: Sendable, Equatable {
    let gainMeters: Double
    let lossMeters: Double
    let sampleCount: Int
    /// Ordered Terrain samples along the route (meters). Used for the place-card hill chart.
    let elevationsMeters: [Double]

    /// Apple/Google-style hill label derived from total climb.
    var hillLabel: String {
        switch gainMeters {
        case ..<15: "Flat"
        case ..<50: "Gentle hill"
        case ..<150: "Moderate hill"
        default: "Steep hill"
        }
    }
}

/// Pure elevation math — no network. Sums positive/negative height deltas with a noise floor so
/// Tilequery contour quantization (10 m steps) doesn't invent fake rollers.
enum ElevationMath {
    static func profile(
        from elevationsMeters: [Double],
        noiseFloorMeters: Double = 1.0
    ) -> ElevationProfile? {
        guard elevationsMeters.count >= 3 else { return nil }

        var gain = 0.0
        var loss = 0.0
        for (previous, next) in zip(elevationsMeters, elevationsMeters.dropFirst()) {
            let delta = next - previous
            guard abs(delta) >= noiseFloorMeters else { continue }
            if delta > 0 {
                gain += delta
            } else {
                loss += -delta
            }
        }

        return ElevationProfile(
            gainMeters: gain,
            lossMeters: loss,
            sampleCount: elevationsMeters.count,
            elevationsMeters: elevationsMeters
        )
    }
}
