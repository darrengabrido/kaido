import Foundation
import SwiftData

enum BikeType: String, CaseIterable, Identifiable, Sendable {
    case standard
    case electric
    case cargo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Bike"
        case .electric: "E-bike"
        case .cargo: "Cargo bike"
        }
    }

    var systemImage: String {
        switch self {
        case .standard: "bicycle"
        case .electric: "bolt.circle"
        case .cargo: "box.truck"
        }
    }

    var defaultCruisingSpeedKph: Double {
        switch self {
        case .standard: 16
        case .electric: 22
        case .cargo: 18
        }
    }
}

enum BikeAssistMode: String, CaseIterable, Identifiable, Sendable {
    case eco
    case tour
    case sport

    var id: String { rawValue }

    var title: String {
        switch self {
        case .eco: "Eco"
        case .tour: "Tour"
        case .sport: "Sport"
        }
    }
}

/// A stable, value-type snapshot of the active bike's pace settings. Mapbox still owns route
/// geometry, rerouting, and turn guidance; this only personalizes the time shown to the rider.
struct RideTimeProfile: Equatable, Sendable {
    let bikeName: String
    let bikeType: BikeType
    let assistMode: BikeAssistMode
    let cruisingSpeedKph: Double

    static let defaultProfile = RideTimeProfile(
        bikeName: "My Bike",
        bikeType: .standard,
        assistMode: .tour,
        cruisingSpeedKph: BikeType.standard.defaultCruisingSpeedKph
    )

    var paceDescription: String {
        switch bikeType {
        case .electric: "\(bikeName) · \(assistMode.title) mode"
        case .standard, .cargo: bikeName
        }
    }

    /// Scales Mapbox's segment-aware cycling duration to the rider's configured pace, while
    /// deliberately capping the adjustment so a setting never produces implausible ETAs.
    func personalizedDuration(
        mapboxDuration: TimeInterval,
        distanceMeters: Double
    ) -> TimeInterval {
        guard mapboxDuration > 0, distanceMeters > 0, cruisingSpeedKph > 0 else {
            return mapboxDuration
        }

        let mapboxSpeedKph = distanceMeters / mapboxDuration * 3.6
        let multiplier = min(max(mapboxSpeedKph / cruisingSpeedKph, 0.6), 1.5)
        return mapboxDuration * multiplier
    }
}

@Model
final class BikeProfile {
    var name: String = ""
    var peripheralIdentifier: String = ""
    var lastConnectedAt: Date?

    // Default-backed additions keep existing CloudKit-synced profiles compatible.
    var bikeTypeRaw: String = BikeType.electric.rawValue
    var assistModeRaw: String = BikeAssistMode.tour.rawValue
    var preferredCruisingSpeedKph: Double = BikeType.electric.defaultCruisingSpeedKph
    var wheelCircumferenceMeters: Double = 2.136
    var isActive: Bool = false

    init(
        name: String = "My E-bike",
        peripheralIdentifier: String = "",
        bikeType: BikeType = .electric
    ) {
        self.name = name
        self.peripheralIdentifier = peripheralIdentifier
        bikeTypeRaw = bikeType.rawValue
        preferredCruisingSpeedKph = bikeType.defaultCruisingSpeedKph
    }

    var bikeType: BikeType {
        get { BikeType(rawValue: bikeTypeRaw) ?? .electric }
        set { bikeTypeRaw = newValue.rawValue }
    }

    var assistMode: BikeAssistMode {
        get { BikeAssistMode(rawValue: assistModeRaw) ?? .tour }
        set { assistModeRaw = newValue.rawValue }
    }

    var isPaired: Bool {
        !peripheralIdentifier.isEmpty
    }

    var rideTimeProfile: RideTimeProfile {
        RideTimeProfile(
            bikeName: name.isEmpty ? "My Bike" : name,
            bikeType: bikeType,
            assistMode: assistMode,
            cruisingSpeedKph: preferredCruisingSpeedKph
        )
    }
}

@MainActor
enum BikeProfileStore {
    static func ensureActiveProfile(in context: ModelContext) {
        let descriptor = FetchDescriptor<BikeProfile>()
        guard let profiles = try? context.fetch(descriptor) else { return }

        guard !profiles.isEmpty else {
            let profile = BikeProfile()
            profile.isActive = true
            context.insert(profile)
            return
        }

        guard !profiles.contains(where: \.isActive) else { return }
        mostRecent(in: profiles)?.isActive = true
    }

    static func activeProfile(in profiles: [BikeProfile]) -> BikeProfile? {
        profiles.first(where: \.isActive) ?? mostRecent(in: profiles)
    }

    static func activate(_ profile: BikeProfile, among profiles: [BikeProfile]) {
        for candidate in profiles {
            candidate.isActive = candidate === profile
        }
    }

    private static func mostRecent(in profiles: [BikeProfile]) -> BikeProfile? {
        profiles.max {
            ($0.lastConnectedAt ?? .distantPast) < ($1.lastConnectedAt ?? .distantPast)
        }
    }
}
