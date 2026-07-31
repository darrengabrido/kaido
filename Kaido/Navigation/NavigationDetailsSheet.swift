import Foundation
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
                "Your ride time",
                NavigationBannerModel.durationText(model.durationRemaining),
                tint: .kaidoViolet
            )
            detailRow(
                "Routing time",
                NavigationBannerModel.durationText(model.routingDurationRemaining),
                tint: .kaidoDim
            )
            detailRow(
                "Distance Remaining",
                NavigationBannerModel.distanceText(model.distanceRemaining),
                tint: .kaidoDim
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
                    tint: .kaidoViolet
                )
                ProgressView(value: min(max(model.fractionTraveled, 0), 1))
                    .tint(.kaidoViolet)
            }
        } header: {
            Text("Route")
        } footer: {
            Text("Your ride time is adjusted for \(model.rideTimeProfile.paceDescription) at \(BikeSpeed.mphText(fromKph: model.rideTimeProfile.cruisingSpeedKph)) mph. Routing time remains Mapbox's cycling duration.")
        }
    }

    @ViewBuilder
    private var bikeSection: some View {
        Section {
            if telemetry.isConnected {
                detailRow("Speed", "\(BikeSpeed.mphText(fromKph: telemetry.speedKph)) mph", tint: .kaidoInk)
                detailRow("Cadence", String(format: "%.0f rpm", telemetry.cadenceRpm), tint: .kaidoDim)
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
                Text("Battery is the bike's reported charge level, not a range estimate — Kaido doesn't know your pack's capacity.")
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
