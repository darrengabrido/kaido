import Foundation

enum BikeSpeed {
    private static let kilometersPerMile = 1.609_344

    static func milesPerHour(fromKph speedKph: Double) -> Double {
        speedKph / kilometersPerMile
    }

    static func kilometersPerHour(fromMph speedMph: Double) -> Double {
        speedMph * kilometersPerMile
    }

    static func mphText(fromKph speedKph: Double, precision: Int = 1) -> String {
        String(format: "%.\(precision)f", milesPerHour(fromKph: speedKph))
    }
}

@Observable
final class BikeTelemetry {
    var speedKph: Double = 0
    var cadenceRpm: Double = 0
    var batteryPercent: Int? = nil
    var isConnected: Bool = false
    var connectedPeripheralName: String? = nil

    // CSC parsing state — written only by BikeBLEManager
    var lastWheelRevolutions: UInt32 = 0
    var lastWheelEventTime: UInt16 = 0
    var lastCrankRevolutions: UInt16 = 0
    var lastCrankEventTime: UInt16 = 0
    /// Default: 700c × 28mm ≈ 2.136 m
    var wheelCircumferenceMeters: Double = 2.136
}
