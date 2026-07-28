import CoreBluetooth
import SwiftUI

/// Lists every BLE service and characteristic discovered on the connected bike, with live raw
/// values — built to reverse-engineer proprietary telemetry protocols (the Aventon Level 3 has no
/// standard cycling GATT services at all) without switching to a separate BLE scanner app.
struct BikeDebugView: View {
    @Environment(BikeBLEManager.self) private var bleManager

    private var groupedByService: [(service: CBUUID, items: [BikeBLEManager.DiscoveredCharacteristic])] {
        let groups = Dictionary(grouping: bleManager.discoveredCharacteristics) { $0.serviceUUID.uuidString }
        return groups.keys.sorted().compactMap { key in
            guard let items = groups[key], let service = items.first?.serviceUUID else { return nil }
            return (service: service, items: items.sorted { $0.characteristicUUID.uuidString < $1.characteristicUUID.uuidString })
        }
    }

    var body: some View {
        List {
            if bleManager.discoveredCharacteristics.isEmpty {
                Section {
                    Text(bleManager.telemetry.isConnected
                         ? "Connected, but no characteristics have been discovered yet."
                         : "Connect to a bike from the Status section to see its services and live characteristic values here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(groupedByService, id: \.service.uuidString) { group in
                Section {
                    ForEach(group.items) { item in
                        CharacteristicRow(item: item) {
                            bleManager.reReadCharacteristic(key: item.id)
                        }
                    }
                } header: {
                    Text("Service \(group.service.uuidString)")
                }
            }
        }
        .navigationTitle("Bike Debug")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Re-read All") {
                    bleManager.reReadAllCharacteristics()
                }
                .disabled(!bleManager.telemetry.isConnected)
            }
        }
    }
}

private struct CharacteristicRow: View {
    let item: BikeBLEManager.DiscoveredCharacteristic
    let onReRead: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.characteristicUUID.uuidString)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                Spacer()
                propertyBadges
            }

            if let value = item.lastValue {
                Text(hexString(value))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.vectorInk)
                    .textSelection(.enabled)
                if let ascii = asciiString(value) {
                    Text(ascii)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let updated = item.lastUpdatedAt {
                    Text(updated.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No value yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing) {
            if item.isReadable {
                Button("Read") { onReRead() }
                    .tint(.vectorViolet)
            }
        }
    }

    private var propertyBadges: some View {
        HStack(spacing: 5) {
            if item.properties.contains(.read)    { badge("R") }
            if item.properties.contains(.write)   { badge("W") }
            if item.properties.contains(.notify)  { badge("N") }
            if item.properties.contains(.indicate) { badge("I") }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.vectorDim)
            .frame(width: 18, height: 18)
            .background(Color.vectorDim.opacity(0.15), in: Circle())
    }

    private func hexString(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// Nil when the bytes contain no printable ASCII — most telemetry payloads won't.
    private func asciiString(_ data: Data) -> String? {
        guard data.contains(where: { (32...126).contains($0) }) else { return nil }
        let rendered = data.map { byte -> String in
            (32...126).contains(byte) ? String(UnicodeScalar(byte)) : "."
        }.joined()
        return "\"\(rendered)\""
    }
}
