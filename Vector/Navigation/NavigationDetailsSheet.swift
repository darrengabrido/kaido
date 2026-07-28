import SwiftUI

/// Ride detail, reached by tapping the bottom banner. The banner itself stays glanceable at
/// riding speed; anything that needs more than a glance lives here.
struct NavigationDetailsSheet: View {
    let model: NavigationBannerModel
    let telemetry: BikeTelemetry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                routeSection
                bikeSection
            }
            .navigationTitle("Ride Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var routeSection: some View {
        Section {
            detailRow(
                "Time Remaining",
                NavigationBannerModel.durationText(model.durationRemaining),
                tint: .vectorInk
            )
            detailRow(
                "Distance Remaining",
                NavigationBannerModel.distanceText(model.distanceRemaining),
                tint: .vectorDim
            )
            detailRow(
                "Arrival",
                model.arrivalDate.formatted(date: .omitted, time: .shortened),
                tint: .primary
            )
            VStack(alignment: .leading, spacing: 6) {
                detailRow(
                    "Progress",
                    "\(Int((min(max(model.fractionTraveled, 0), 1) * 100).rounded()))%",
                    tint: .vectorViolet
                )
                ProgressView(value: min(max(model.fractionTraveled, 0), 1))
                    .tint(.vectorViolet)
            }
        } header: {
            Text("Route")
        }
    }

    @ViewBuilder
    private var bikeSection: some View {
        Section {
            if telemetry.isConnected {
                detailRow("Speed", String(format: "%.1f km/h", telemetry.speedKph), tint: .vectorInk)
                detailRow("Cadence", String(format: "%.0f rpm", telemetry.cadenceRpm), tint: .vectorDim)
                if let batteryPercent = telemetry.batteryPercent {
                    detailRow("Battery", "\(batteryPercent)%", tint: batteryTint(batteryPercent))
                }
            } else {
                Text("Bike not connected")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Bike")
        } footer: {
            if telemetry.isConnected, telemetry.batteryPercent != nil {
                Text("Battery is the bike's reported charge level, not a range estimate — Vector doesn't know your pack's capacity.")
            }
        }
    }

    private func detailRow(_ label: String, _ value: String, tint: Color) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
        }
    }

    private func batteryTint(_ percent: Int) -> Color {
        switch percent {
        case ..<20: return .statusCritical
        case ..<50: return .statusCaution
        default: return .statusGood
        }
    }
}
