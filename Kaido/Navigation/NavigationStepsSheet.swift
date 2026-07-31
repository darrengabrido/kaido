import MapboxDirections
import SwiftUI

/// The remaining turn list, reached by tapping the top instruction banner — this restores the
/// step list that Mapbox's stock `TopBannerViewController` offered before it was replaced.
struct NavigationStepsSheet: View {
    let steps: [RouteStep]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if steps.isEmpty {
                    Text("No remaining steps.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                        stepRow(step)
                    }
                }
            }
            .navigationTitle("Remaining Steps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func stepRow(_ step: RouteStep) -> some View {
        HStack(spacing: 14) {
            Image(systemName: NavigationBannerModel.maneuverSymbol(
                type: step.maneuverType,
                direction: step.maneuverDirection
            ))
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.kaidoViolet)
            .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.instructions)
                    .font(.subheadline)
                Text(NavigationBannerModel.distanceText(step.distance))
                    .font(.caption)
                    .foregroundStyle(Color.kaidoDim)
            }
        }
        .padding(.vertical, 2)
    }
}
