import SwiftUI
import SwiftData

struct BikeConnectionView: View {
    @Environment(BikeBLEManager.self) private var bleManager
    @Environment(AuthState.self) private var authState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BikeProfile.lastConnectedAt, order: .reverse) private var savedProfiles: [BikeProfile]

    var body: some View {
        NavigationStack {
            List {
                accountSection
                statusSection
                if bleManager.telemetry.isConnected {
                    telemetrySection
                } else {
                    scanSection
                }
                if !savedProfiles.isEmpty && !bleManager.telemetry.isConnected {
                    savedSection
                }
            }
            .navigationTitle("Bike")
            .task { bleManager.modelContext = modelContext }
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section {
            HStack {
                Image(systemName: authState.isAuthenticated ? "person.crop.circle.fill" : "person.crop.circle")
                    .foregroundStyle(authState.isAuthenticated ? Color.routeTeal : .secondary)
                Text(authState.user?.email ?? "Browsing as Guest")
                    .lineLimit(1)
                Spacer()
                if authState.isAuthenticated {
                    Button("Sign Out", role: .destructive) {
                        Task { try? await authState.signOut() }
                    }
                } else {
                    Button("Sign In") {
                        authState.exitGuestMode()
                    }
                    .tint(.routeTeal)
                }
            }
        } header: {
            Text("Account")
        }
    }

    private var statusSection: some View {
        Section {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(bleManager.scanState.label)
                Spacer()
                if bleManager.telemetry.isConnected {
                    Button("Disconnect", role: .destructive) {
                        bleManager.disconnect()
                    }
                }
            }
        } header: {
            Text("Status")
        }
    }

    private var telemetrySection: some View {
        Section {
            TelemetryRow(label: "Speed",
                         value: String(format: "%.1f km/h", bleManager.telemetry.speedKph),
                         color: .paceBlue)
            TelemetryRow(label: "Cadence",
                         value: String(format: "%.0f RPM", bleManager.telemetry.cadenceRpm),
                         color: .effortCoral)
            if let pct = bleManager.telemetry.batteryPercent {
                TelemetryRow(label: "Battery",
                             value: "\(pct)%",
                             color: pct <= 20 ? .effortCoral : pct <= 40 ? .favoriteAmber : .routeTeal)
            }
        } header: {
            Text("Live Telemetry")
        }
    }

    @ViewBuilder
    private var scanSection: some View {
        Section {
            if bleManager.scanState == .scanning {
                Button("Stop Scanning", role: .destructive) {
                    bleManager.stopScanning()
                }
            } else if bleManager.scanState != .connecting {
                Button("Scan for Bikes") {
                    bleManager.startScanning()
                }
                .tint(.goGreen)
            }
        }

        if !bleManager.discoveredPeripherals.isEmpty {
            Section {
                ForEach(bleManager.discoveredPeripherals) { peripheral in
                    Button {
                        bleManager.connect(peripheral)
                    } label: {
                        HStack {
                            Image(systemName: "bicycle")
                                .foregroundStyle(Color.routeTeal)
                            Text(peripheral.name)
                            Spacer()
                            if bleManager.scanState == .connecting
                                && bleManager.discoveredPeripherals.first?.id == peripheral.id {
                                ProgressView()
                            }
                        }
                    }
                    .tint(.primary)
                }
            } header: {
                Text("Nearby Devices")
            }
        }
    }

    private var savedSection: some View {
        Section {
            ForEach(savedProfiles) { profile in
                Button {
                    if let uuid = UUID(uuidString: profile.peripheralIdentifier) {
                        bleManager.reconnect(peripheralIdentifier: uuid)
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise.circle")
                            .foregroundStyle(Color.paceBlue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name)
                            if let date = profile.lastConnectedAt {
                                Text("Last seen \(date.formatted(.relative(presentation: .named)))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .tint(.primary)
            }
        } header: {
            Text("Previously Paired")
        }
    }

    private var statusColor: Color {
        switch bleManager.scanState {
        case .connected:            return .goGreen
        case .connecting:           return .favoriteAmber
        case .scanning:             return .paceBlue
        case .idle:                 return .secondary
        case .bluetoothUnavailable: return .effortCoral
        }
    }
}

private struct TelemetryRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(color)
        }
    }
}
