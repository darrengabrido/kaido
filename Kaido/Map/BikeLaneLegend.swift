import SwiftUI

struct BikeLaneLegend: View {
    var showsBackground = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LegendRow(dashed: false, label: "Bike Path")
            LegendRow(dashed: true, label: "Bike Lane")
        }
        .padding(showsBackground ? 10 : 0)
        .modifier(OptionalGlass(isActive: showsBackground))
    }
}

private struct OptionalGlass: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
        } else {
            content
        }
    }
}

private struct LegendRow: View {
    let dashed: Bool
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            LineSwatch(dashed: dashed)
                .frame(width: 26, height: 3)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LineSwatch: View {
    let dashed: Bool

    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
            }
            .stroke(
                Color.routeTealOnMap,
                style: StrokeStyle(
                    lineWidth: dashed ? 3 : 4,
                    lineCap: dashed ? .butt : .round,
                    dash: dashed ? [5, 3] : []
                )
            )
        }
    }
}
