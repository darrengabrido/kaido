import SwiftUI

/// The quiet / mixed / busy split of a route, drawn to width instead of spelled out.
///
/// Replaces a line like "42% quiet · 25% mixed · 33% busy". Three numbers in prose have to be
/// read and compared; the same three as proportions can be compared between two routes at a
/// glance, which is the only thing a rider actually does with them.
///
/// Mint is the app's bike-infrastructure colour, so quiet reading mint is consistent with the
/// lanes drawn on the map. Busy borrows the muted clay used for warnings — serious, not alarming.
struct RouteStressBar: View {
    let quiet: Double
    let mixed: Double
    let busy: Double

    private var total: Double { max(quiet + mixed + busy, 0.0001) }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 1.5) {
                segment(Color.routeTealOnMap, quiet, in: proxy.size.width)
                segment(Color.kaidoDim, mixed, in: proxy.size.width)
                segment(Color.statusCritical.opacity(0.85), busy, in: proxy.size.width)
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("Route makeup")
        .accessibilityValue(spokenSummary)
    }

    @ViewBuilder
    private func segment(_ color: Color, _ fraction: Double, in width: CGFloat) -> some View {
        let share = fraction / total
        // Spacing between three segments eats 3pt; take it off so the bar can't overflow.
        if share > 0 {
            Capsule().fill(color).frame(width: max((width - 3) * share, 2))
        }
    }

    private var spokenSummary: String {
        let percent = { (value: Double) in Int((value / total * 100).rounded()) }
        return "\(percent(quiet))% quiet, \(percent(mixed))% mixed, \(percent(busy))% busy"
    }
}
