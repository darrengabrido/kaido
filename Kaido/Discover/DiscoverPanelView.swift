import SwiftUI

/// Nearby POI suggestions shown only during free ride mode.
struct DiscoverPanelView: View {
    let viewModel: DiscoverViewModel
    let onSelect: (POIRecommendation) -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if viewModel.isPanelExpanded {
                content
            }
        }
        .padding()
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.isAIEnabled ? "sparkles" : "binoculars.fill")
                .foregroundStyle(Color.kaidoViolet)

            VStack(alignment: .leading, spacing: 2) {
                Text("Discover nearby")
                    .font(.headline)
                if let area = viewModel.areaDescription {
                    Text(area)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Free ride · explore as you go")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
            .accessibilityLabel("Refresh suggestions")

            Button {
                withAnimation(.snappy) {
                    viewModel.isPanelExpanded.toggle()
                }
            } label: {
                Image(systemName: viewModel.isPanelExpanded ? "chevron.down" : "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.isPanelExpanded ? "Collapse suggestions" : "Expand suggestions")
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.recommendations.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                Text("Finding places worth a stop…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        } else if let error = viewModel.error, viewModel.recommendations.isEmpty {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        } else {
            VStack(spacing: 0) {
                ForEach(viewModel.recommendations) { recommendation in
                    Button {
                        onSelect(recommendation)
                    } label: {
                        recommendationRow(recommendation)
                    }
                    .buttonStyle(.plain)

                    if recommendation.id != viewModel.recommendations.last?.id {
                        Divider()
                            .padding(.leading, 40)
                    }
                }
            }

            if let error = viewModel.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !viewModel.isAIEnabled {
                fallbackFooter
            }
        }
    }

    /// Says plainly which brain picked these, so an empty key never reads as a broken feature.
    private var fallbackFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "key")
            Text("Using built-in picks. Add an AI key in Settings for smarter ones.")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 6)
    }

    private func recommendationRow(_ recommendation: POIRecommendation) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: recommendation.iconName)
                .font(.system(size: 15))
                .foregroundStyle(Color.routeTeal)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(recommendation.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(formattedDistance(recommendation.distanceMeters))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(recommendation.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func formattedDistance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}
