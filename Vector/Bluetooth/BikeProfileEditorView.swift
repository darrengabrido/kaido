import SwiftUI

struct BikeProfileEditorView: View {
    let profile: BikeProfile
    let onSave: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDeletion = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Bike") {
                    TextField("Bike name", text: binding(\.name))

                    Picker("Bike type", selection: bikeTypeBinding) {
                        ForEach(BikeType.allCases) { type in
                            Label(type.title, systemImage: type.systemImage)
                                .tag(type)
                        }
                    }
                }

                if profile.bikeType == .electric {
                    Section {
                        Picker("Assist mode", selection: assistModeBinding) {
                            ForEach(BikeAssistMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                    } header: {
                        Text("E-bike")
                    } footer: {
                        Text("Assist mode appears with your ride time. Set the speed below to the pace you actually expect to maintain.")
                    }
                }

                Section {
                    HStack {
                        Text("Comfortable speed")
                        Spacer()
                        Text(speedText)
                            .foregroundStyle(Color.vectorViolet)
                            .monospacedDigit()
                    }

                    Slider(value: preferredSpeedMphBinding, in: 5...22, step: 0.5)
                        .tint(.vectorViolet)
                } header: {
                    Text("Your ride time")
                } footer: {
                    Text("Vector keeps Mapbox's cycling route and guidance, then adjusts the displayed time to this pace.")
                }

                Section {
                    HStack {
                        Text("Wheel circumference")
                        Spacer()
                        Text(String(format: "%.3f m", profile.wheelCircumferenceMeters))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(value: binding(\.wheelCircumferenceMeters), in: 1.5...2.6, step: 0.001)
                        .tint(.vectorViolet)
                } header: {
                    Text("Speed sensor")
                } footer: {
                    Text("Used when your bike reports standard Cycling Speed & Cadence data.")
                }

                Section {
                    Button("Remove bike", role: .destructive) {
                        isConfirmingDeletion = true
                    }
                } footer: {
                    Text("This removes the saved bike and its pairing details from Vector. A replacement active bike will be selected automatically.")
                }
            }
            .navigationTitle("Bike Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave()
                        dismiss()
                    }
                    .tint(.vectorViolet)
                }
            }
            .confirmationDialog(
                "Remove \(profile.name.isEmpty ? "this bike" : profile.name)?",
                isPresented: $isConfirmingDeletion,
                titleVisibility: .visible
            ) {
                Button("Remove Bike", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            } message: {
                Text("This cannot be undone from this device.")
            }
        }
    }

    private var speedText: String {
        "\(BikeSpeed.mphText(fromKph: profile.preferredCruisingSpeedKph)) mph"
    }

    private var bikeTypeBinding: Binding<BikeType> {
        Binding(
            get: { profile.bikeType },
            set: { type in
                profile.bikeType = type
                profile.preferredCruisingSpeedKph = type.defaultCruisingSpeedKph
            }
        )
    }

    private var assistModeBinding: Binding<BikeAssistMode> {
        Binding(
            get: { profile.assistMode },
            set: { profile.assistMode = $0 }
        )
    }

    private var preferredSpeedMphBinding: Binding<Double> {
        Binding(
            get: { BikeSpeed.milesPerHour(fromKph: profile.preferredCruisingSpeedKph) },
            set: { profile.preferredCruisingSpeedKph = BikeSpeed.kilometersPerHour(fromMph: $0) }
        )
    }

    private func binding<Value>(
        _ keyPath: ReferenceWritableKeyPath<BikeProfile, Value>
    ) -> Binding<Value> {
        Binding(
            get: { profile[keyPath: keyPath] },
            set: { profile[keyPath: keyPath] = $0 }
        )
    }
}
