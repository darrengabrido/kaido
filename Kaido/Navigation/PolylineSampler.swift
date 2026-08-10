import CoreLocation
import Foundation

/// Evenly spaced samples along a polyline by ground distance — same walk as the ETA-badge
/// midpoint helper, generalized for elevation Tilequery.
enum PolylineSampler {
    /// Returns coordinates along `coordinates` every `spacingMeters`, always including the first
    /// and last point, capped at `maxSamples`.
    static func coordinates(
        along coordinates: [CLLocationCoordinate2D],
        everyMeters spacingMeters: CLLocationDistance = 100,
        maxSamples: Int = 40
    ) -> [CLLocationCoordinate2D] {
        guard maxSamples > 0 else { return [] }
        guard coordinates.count > 1 else { return Array(coordinates.prefix(maxSamples)) }
        guard spacingMeters > 0 else {
            return [coordinates.first, coordinates.last].compactMap { $0 }
        }

        let locations = coordinates.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        let segmentLengths = zip(locations, locations.dropFirst()).map { $0.distance(from: $1) }
        let total = segmentLengths.reduce(0, +)
        guard total > 0 else { return Array(coordinates.prefix(1)) }

        var samples: [CLLocationCoordinate2D] = [coordinates[0]]
        var nextTarget = spacingMeters

        var traveled: CLLocationDistance = 0
        for (index, segmentLength) in segmentLengths.enumerated() {
            guard segmentLength > 0 else { continue }
            let start = coordinates[index]
            let end = coordinates[index + 1]

            while nextTarget <= traveled + segmentLength, samples.count < maxSamples - 1 {
                let t = (nextTarget - traveled) / segmentLength
                samples.append(interpolate(from: start, to: end, fraction: min(max(t, 0), 1)))
                nextTarget += spacingMeters
            }
            traveled += segmentLength
        }

        if let last = coordinates.last {
            if let existing = samples.last,
               CLLocation(latitude: existing.latitude, longitude: existing.longitude)
                .distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude)) < 1 {
                samples[samples.count - 1] = last
            } else if samples.count < maxSamples {
                samples.append(last)
            } else {
                samples[samples.count - 1] = last
            }
        }

        return samples
    }

    private static func interpolate(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        fraction: Double
    ) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: start.latitude + (end.latitude - start.latitude) * fraction,
            longitude: start.longitude + (end.longitude - start.longitude) * fraction
        )
    }
}
