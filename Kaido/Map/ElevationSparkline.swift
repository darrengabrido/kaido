import SwiftUI

/// Compact elevation profile sparkline for the place-card hills section.
struct ElevationSparkline: View {
    let elevationsMeters: [Double]

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)
            ZStack(alignment: .bottom) {
                if points.count >= 2 {
                    fillPath(points: points, size: proxy.size)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.kaidoViolet.opacity(0.28),
                                    Color.kaidoViolet.opacity(0.04),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    strokePath(points: points)
                        .stroke(Color.kaidoVioletOnMap, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                }
            }
        }
        .frame(height: 56)
        .accessibilityHidden(true)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard elevationsMeters.count >= 2, size.width > 0, size.height > 0 else { return [] }
        let minE = elevationsMeters.min() ?? 0
        let maxE = elevationsMeters.max() ?? 1
        let span = max(maxE - minE, 1)
        let stepX = size.width / CGFloat(elevationsMeters.count - 1)
        return elevationsMeters.enumerated().map { index, elevation in
            let x = CGFloat(index) * stepX
            let y = size.height - CGFloat((elevation - minE) / span) * size.height
            return CGPoint(x: x, y: y)
        }
    }

    private func strokePath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    private func fillPath(points: [CGPoint], size: CGSize) -> Path {
        var path = strokePath(points: points)
        guard let last = points.last, let first = points.first else { return path }
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.addLine(to: CGPoint(x: first.x, y: size.height))
        path.closeSubpath()
        return path
    }
}
