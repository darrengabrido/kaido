import SwiftUI
import SwiftData

struct BikeConnectionView: View {
    @Environment(BikeBLEManager.self) private var bleManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BikeProfile.lastConnectedAt, order: .reverse) private var savedProfiles: [BikeProfile]
    @State private var profileToEdit: BikeProfile?
    @State private var profilePendingRemoval: BikeProfile?
    @State private var isShowingLiveData = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if let activeProfile {
                        BikeShowcaseCard(
                            profile: activeProfile,
                            telemetry: bleManager.telemetry,
                            status: bleManager.scanState,
                            onEdit: { profileToEdit = activeProfile },
                            onConnect: { connectActiveBike(activeProfile) },
                            onTelemetry: { isShowingLiveData = true }
                        )

                        if bleManager.telemetry.isConnected {
                            liveTelemetryCard
                        } else {
                            pairingCard
                        }

                        if savedProfiles.count > 1 {
                            bikePickerCard
                        }

                        if !bleManager.discoveredPeripherals.isEmpty {
                            nearbyDevicesCard
                        }

                        debugCard
                    } else {
                        ProgressView("Preparing your bike")
                            .frame(maxWidth: .infinity, minHeight: 240)
                    }
                }
                .padding()
            }
            .background(Color.vectorMidnight)
            .navigationTitle("Bike")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if let activeProfile {
                        Button {
                            profileToEdit = activeProfile
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .accessibilityLabel("Edit bike details")
                    }
                }
            }
            .task {
                bleManager.modelContext = modelContext
                BikeProfileStore.ensureActiveProfile(in: modelContext)
                if let activeProfile {
                    bleManager.apply(profile: activeProfile)
                }
            }
            .onChange(of: activeProfileSignature) { _, _ in
                if let activeProfile {
                    bleManager.apply(profile: activeProfile)
                }
            }
            .sheet(item: $profileToEdit) { profile in
                BikeProfileEditorView(
                    profile: profile,
                    onSave: {
                        BikeProfileStore.activate(profile, among: savedProfiles)
                        bleManager.apply(profile: profile)
                        try? modelContext.save()
                    },
                    onDelete: {
                        removeBike(profile)
                    }
                )
            }
            .sheet(isPresented: $isShowingLiveData) {
                LiveBikeDataSheet(
                    profile: activeProfile,
                    telemetry: bleManager.telemetry
                )
                .presentationDetents([.medium])
            }
            .confirmationDialog(
                "Remove \(profilePendingRemoval?.name ?? "this bike")?",
                isPresented: Binding(
                    get: { profilePendingRemoval != nil },
                    set: { if !$0 { profilePendingRemoval = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove Bike", role: .destructive) {
                    if let profilePendingRemoval {
                        removeBike(profilePendingRemoval)
                    }
                    profilePendingRemoval = nil
                }
            } message: {
                Text("Its saved pairing details will be removed from Vector.")
            }
        }
    }

    private var activeProfile: BikeProfile? {
        BikeProfileStore.activeProfile(in: savedProfiles)
    }

    private var activeProfileSignature: String {
        guard let activeProfile else { return "" }
        return [
            activeProfile.name,
            activeProfile.bikeTypeRaw,
            activeProfile.assistModeRaw,
            String(activeProfile.preferredCruisingSpeedKph),
            String(activeProfile.wheelCircumferenceMeters),
            activeProfile.peripheralIdentifier
        ]
        .joined(separator: "|")
    }

    private var liveTelemetryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Live telemetry", systemImage: "dot.radiowaves.left.and.right")
                    .font(.headline)
                Spacer()
                Text(bleManager.telemetry.connectedPeripheralName ?? "Connected bike")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                BikeMetricTile(
                    value: BikeSpeed.mphText(fromKph: bleManager.telemetry.speedKph),
                    unit: "mph",
                    label: "Speed",
                    tint: .vectorInk
                )
                BikeMetricTile(
                    value: String(format: "%.0f", bleManager.telemetry.cadenceRpm),
                    unit: "rpm",
                    label: "Cadence",
                    tint: .vectorDim
                )
                if let battery = bleManager.telemetry.batteryPercent {
                    BikeMetricTile(
                        value: "\(battery)",
                        unit: "%",
                        label: "Battery",
                        tint: batteryTint(battery)
                    )
                }
            }
        }
        .bikeCard()
    }

    private var pairingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Connection", systemImage: "bolt.horizontal.circle")
                    .font(.headline)
                Spacer()
                Text(bleManager.scanState.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(activeProfile?.isPaired == true
                 ? "Reconnect to this bike to use live speed, cadence, and battery data."
                 : "Pair a bike to add live speed, cadence, and battery data to your rides.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                if bleManager.scanState == .scanning {
                    bleManager.stopScanning()
                } else {
                    bleManager.startScanning()
                }
            } label: {
                Label(
                    bleManager.scanState == .scanning ? "Stop scanning" : "Scan for bikes",
                    systemImage: bleManager.scanState == .scanning ? "stop.circle" : "dot.radiowaves.left.and.right"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.vectorViolet)
            .disabled(bleManager.scanState == .connecting)
        }
        .bikeCard()
    }

    private var nearbyDevicesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Nearby bikes", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                Spacer()
                Button {
                    bleManager.dismissDiscoveredPeripherals()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close nearby bikes")
            }

            ForEach(bleManager.discoveredPeripherals) { peripheral in
                Button {
                    bleManager.connect(peripheral)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "bicycle")
                            .foregroundStyle(Color.vectorViolet)
                            .frame(width: 24)
                        Text(peripheral.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if bleManager.scanState == .connecting {
                            ProgressView()
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .bikeCard()
    }

    private var bikePickerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Your bikes", systemImage: "bicycle.circle")
                .font(.headline)

            ForEach(savedProfiles) { profile in
                HStack(spacing: 4) {
                    Button {
                        BikeProfileStore.activate(profile, among: savedProfiles)
                        bleManager.apply(profile: profile)
                        try? modelContext.save()
                    } label: {
                        HStack {
                            Image(systemName: profile.bikeType.systemImage)
                                .foregroundStyle(profile.isActive ? Color.vectorViolet : Color.vectorDim)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name)
                                    .foregroundStyle(.primary)
                                Text(profile.isPaired ? "Paired" : "Not paired")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if profile.isActive {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.vectorViolet)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        profilePendingRemoval = profile
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline)
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(profile.name)")
                }
            }
        }
        .bikeCard()
    }

    @ViewBuilder
    private var debugCard: some View {
        if !bleManager.discoveredCharacteristics.isEmpty {
            NavigationLink {
                BikeDebugView()
            } label: {
                HStack {
                    Label("Bike debug", systemImage: "wrench.and.screwdriver")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(bleManager.discoveredCharacteristics.count) characteristics")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .bikeCard()
        }
    }

    private func connectActiveBike(_ profile: BikeProfile) {
        if bleManager.telemetry.isConnected {
            bleManager.disconnect()
        } else if let identifier = UUID(uuidString: profile.peripheralIdentifier) {
            bleManager.reconnect(peripheralIdentifier: identifier)
        } else {
            bleManager.startScanning()
        }
    }

    private func removeBike(_ profile: BikeProfile) {
        if profile.isActive && bleManager.telemetry.isConnected {
            bleManager.disconnect()
        }

        let remainingProfiles = savedProfiles.filter { $0 !== profile }
        let replacement: BikeProfile

        if let existingProfile = BikeProfileStore.activeProfile(in: remainingProfiles) {
            replacement = existingProfile
            BikeProfileStore.activate(replacement, among: remainingProfiles)
        } else {
            replacement = BikeProfile()
            replacement.isActive = true
            modelContext.insert(replacement)
        }

        modelContext.delete(profile)
        try? modelContext.save()
        bleManager.apply(profile: replacement)
    }

    private func batteryTint(_ percent: Int) -> Color {
        switch percent {
        case ..<20: .statusCritical
        case ..<50: .statusCaution
        default: .statusGood
        }
    }
}

private extension View {
    func bikeCard() -> some View {
        padding(16)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct BikeMetricTile: View {
    let value: String
    let unit: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct LiveBikeDataSheet: View {
    let profile: BikeProfile?
    let telemetry: BikeTelemetry

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Bike") {
                    LabeledContent("Active bike", value: profile?.name ?? "My Bike")
                    LabeledContent("Ride mode", value: profile?.rideTimeProfile.paceDescription ?? "Your pace")
                }

                Section("Live telemetry") {
                    LabeledContent("Speed", value: "\(BikeSpeed.mphText(fromKph: telemetry.speedKph)) mph")
                    LabeledContent("Cadence", value: String(format: "%.0f rpm", telemetry.cadenceRpm))
                    if let battery = telemetry.batteryPercent {
                        LabeledContent("Battery", value: "\(battery)%")
                    }
                }
            }
            .navigationTitle("Live Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
