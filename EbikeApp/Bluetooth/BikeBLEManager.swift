import CoreBluetooth
import SwiftData

private extension CBUUID {
    // Services
    static let battery             = CBUUID(string: "180F")
    static let cyclingSpeedCadence = CBUUID(string: "1816")
    static let cyclingPower        = CBUUID(string: "1818")
    // Characteristics
    static let batteryLevel        = CBUUID(string: "2A19")
    static let cscMeasurement      = CBUUID(string: "2A5B")
    static let powerMeasurement    = CBUUID(string: "2A63")
}

@Observable
@MainActor
final class BikeBLEManager: NSObject {
    let telemetry = BikeTelemetry()

    enum ScanState {
        case bluetoothUnavailable, idle, scanning, connecting, connected
        var label: String {
            switch self {
            case .bluetoothUnavailable: return "Bluetooth unavailable"
            case .idle:                 return "Not scanning"
            case .scanning:             return "Scanning…"
            case .connecting:           return "Connecting…"
            case .connected:            return "Connected"
            }
        }
    }

    struct DiscoveredPeripheral: Identifiable {
        let id: UUID
        let name: String
        let peripheral: CBPeripheral
    }

    var scanState: ScanState = .idle
    var discoveredPeripherals: [DiscoveredPeripheral] = []

    private var central: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    var modelContext: ModelContext?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        guard central.state == .poweredOn else { return }
        discoveredPeripherals = []
        scanState = .scanning
        central.scanForPeripherals(withServices: [.battery, .cyclingSpeedCadence, .cyclingPower])
    }

    func stopScanning() {
        central.stopScan()
        if scanState == .scanning { scanState = .idle }
    }

    func connect(_ discovered: DiscoveredPeripheral) {
        central.stopScan()
        scanState = .connecting
        connectedPeripheral = discovered.peripheral
        central.connect(discovered.peripheral)
    }

    func disconnect() {
        guard let p = connectedPeripheral else { return }
        central.cancelPeripheralConnection(p)
    }

    func reconnect(peripheralIdentifier: UUID) {
        let known = central.retrievePeripherals(withIdentifiers: [peripheralIdentifier])
        if let p = known.first {
            p.delegate = self
            connectedPeripheral = p
            scanState = .connecting
            central.connect(p)
        } else {
            startScanning()
        }
    }

    // MARK: - Private

    private func saveProfile(_ peripheral: CBPeripheral) {
        guard let context = modelContext else { return }
        let identifier = peripheral.identifier.uuidString
        let descriptor = FetchDescriptor<BikeProfile>(
            predicate: #Predicate { $0.peripheralIdentifier == identifier }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.lastConnectedAt = Date()
        } else {
            let profile = BikeProfile(name: peripheral.name ?? "Ebike", peripheralIdentifier: identifier)
            profile.lastConnectedAt = Date()
            context.insert(profile)
        }
    }

    @MainActor
    private func parseCSCMeasurement(_ data: Data) {
        guard data.count >= 1 else { return }
        let flags = data[0]
        let hasWheel = (flags & 0x01) != 0
        let hasCrank = (flags & 0x02) != 0
        var offset = 1

        if hasWheel && data.count >= offset + 6 {
            let revs = readU32LE(data, at: offset); offset += 4
            let time = readU16LE(data, at: offset); offset += 2
            let revDelta  = Int64(revs) - Int64(telemetry.lastWheelRevolutions)
            let timeDelta = Int32(bitPattern: UInt32(time) &- UInt32(telemetry.lastWheelEventTime))
            if timeDelta > 0 && revDelta > 0 {
                let revPerSec = Double(revDelta) / (Double(timeDelta) / 1024.0)
                telemetry.speedKph = revPerSec * telemetry.wheelCircumferenceMeters * 3.6
            } else if timeDelta > 512 {
                telemetry.speedKph = 0
            }
            telemetry.lastWheelRevolutions = revs
            telemetry.lastWheelEventTime   = time
        }

        if hasCrank && data.count >= offset + 4 {
            let revs = readU16LE(data, at: offset); offset += 2
            let time = readU16LE(data, at: offset)
            let revDelta  = Int32(revs) - Int32(telemetry.lastCrankRevolutions)
            let timeDelta = Int32(bitPattern: UInt32(time) &- UInt32(telemetry.lastCrankEventTime))
            if timeDelta > 0 && revDelta > 0 {
                telemetry.cadenceRpm = Double(revDelta) / (Double(timeDelta) / 1024.0) * 60.0
            } else if timeDelta > 512 {
                telemetry.cadenceRpm = 0
            }
            telemetry.lastCrankRevolutions = revs
            telemetry.lastCrankEventTime   = time
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BikeBLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            scanState = central.state == .poweredOn ? .idle : .bluetoothUnavailable
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "Unknown"
        let found = DiscoveredPeripheral(id: peripheral.identifier, name: name, peripheral: peripheral)
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !discoveredPeripherals.contains(where: { $0.id == found.id }) {
                discoveredPeripherals.append(found)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([.battery, .cyclingSpeedCadence, .cyclingPower])
        Task { @MainActor [weak self] in
            guard let self else { return }
            scanState = .connected
            telemetry.isConnected = true
            telemetry.connectedPeripheralName = peripheral.name
            saveProfile(peripheral)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            scanState = .idle
            telemetry.isConnected = false
            telemetry.connectedPeripheralName = nil
            telemetry.speedKph = 0
            telemetry.cadenceRpm = 0
            telemetry.batteryPercent = nil
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            self?.scanState = .idle
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BikeBLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let chars = service.characteristics else { return }
        for char in chars {
            if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: char)
            } else if char.properties.contains(.read) {
                peripheral.readValue(for: char)
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let data = characteristic.value, error == nil else { return }
        switch characteristic.uuid {
        case .batteryLevel:
            let pct = Int(data[0])
            Task { @MainActor [weak self] in self?.telemetry.batteryPercent = pct }
        case .cscMeasurement:
            let captured = data
            Task { @MainActor [weak self] in self?.parseCSCMeasurement(captured) }
        default:
            break
        }
    }
}

// MARK: - Byte helpers

private func readU16LE(_ data: Data, at offset: Int) -> UInt16 {
    UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
}

private func readU32LE(_ data: Data, at offset: Int) -> UInt32 {
    UInt32(data[offset])
        | (UInt32(data[offset + 1]) << 8)
        | (UInt32(data[offset + 2]) << 16)
        | (UInt32(data[offset + 3]) << 24)
}
