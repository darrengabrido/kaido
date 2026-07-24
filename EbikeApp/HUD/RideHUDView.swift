import SwiftUI

struct RideHUDView: View {
    let telemetry: BikeTelemetry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Connection status row
            HStack(spacing: 5) {
                Circle()
                    .fill(telemetry.isConnected ? Color.goGreen : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(telemetry.isConnected
                     ? (telemetry.connectedPeripheralName ?? "Bike")
                     : "No Bike")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let pct = telemetry.batteryPercent {
                    batteryView(pct)
                }
            }

            if telemetry.isConnected {
                Divider()

                // Speed
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(speedString)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.paceBlue)
                    Text("km/h")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Cadence
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(cadenceString)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.effortCoral)
                    Text("rpm")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 120)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
    }

    private var speedString: String {
        String(format: "%.1f", telemetry.speedKph)
    }

    private var cadenceString: String {
        String(format: "%.0f", telemetry.cadenceRpm)
    }

    @ViewBuilder
    private func batteryView(_ pct: Int) -> some View {
        let color: Color = pct <= 20 ? Color.effortCoral : pct <= 40 ? Color.favoriteAmber : Color.routeTeal
        HStack(spacing: 3) {
            Image(systemName: batteryIcon(pct))
                .imageScale(.small)
                .foregroundStyle(color)
            Text("\(pct)%")
                .font(.caption2)
                .foregroundStyle(color)
        }
    }

    private func batteryIcon(_ pct: Int) -> String {
        switch pct {
        case 0...12:  return "battery.0percent"
        case 13...37: return "battery.25percent"
        case 38...62: return "battery.50percent"
        case 63...87: return "battery.75percent"
        default:      return "battery.100percent"
        }
    }
}
