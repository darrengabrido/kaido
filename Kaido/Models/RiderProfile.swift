import Foundation
import SwiftData

enum RiderExperienceLevel: String, CaseIterable, Identifiable, Sendable {
    case newRider
    case recreational
    case experienced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newRider: "New rider"
        case .recreational: "Recreational"
        case .experienced: "Experienced"
        }
    }

    var systemImage: String {
        switch self {
        case .newRider: "leaf"
        case .recreational: "bicycle"
        case .experienced: "mountain.2"
        }
    }
}

/// The rider's personal identity, kept separate from authentication so guests can create a
/// profile too. SwiftData's CloudKit configuration carries it to the rider's other devices.
@Model
final class RiderProfile {
    var displayName: String = ""
    var homeCity: String = ""
    var bio: String = ""
    var experienceLevelRaw: String = RiderExperienceLevel.recreational.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// The rider's profile photo, downsampled to a small square JPEG before it's ever stored here
    /// (see `RiderProfileEditorView`). `.externalStorage` mirrors `Ride.recordedPathData` — SwiftData
    /// maps it to a `CKAsset` under CloudKit instead of inlining it into the record.
    ///
    /// Deliberately `Data`, not `UIImage`: every other file in Models/ stays free of UIKit, and both
    /// consuming views already need `UIImage` for display/encoding regardless, so the conversion lives
    /// there instead of here.
    @Attribute(.externalStorage)
    var photoData: Data?

    init(
        displayName: String = "",
        homeCity: String = "",
        bio: String = "",
        experienceLevel: RiderExperienceLevel = .recreational
    ) {
        self.displayName = displayName
        self.homeCity = homeCity
        self.bio = bio
        experienceLevelRaw = experienceLevel.rawValue
    }

    var experienceLevel: RiderExperienceLevel {
        get { RiderExperienceLevel(rawValue: experienceLevelRaw) ?? .recreational }
        set { experienceLevelRaw = newValue.rawValue }
    }
}

@MainActor
enum RiderProfileStore {
    private static let suggestedDisplayNameKey = "kaido.suggestedRiderDisplayName"

    /// Apple only supplies a person's name on the first authorization, so retain that one-time
    /// value until the SwiftData profile can be created after authentication completes.
    static func rememberSuggestedDisplayName(_ name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        UserDefaults.standard.set(trimmedName, forKey: suggestedDisplayNameKey)
    }

    static func discardSuggestedDisplayName() {
        UserDefaults.standard.removeObject(forKey: suggestedDisplayNameKey)
    }

    @discardableResult
    static func ensureProfile(in context: ModelContext) -> RiderProfile {
        let suggestedName = takeSuggestedDisplayName()
        let descriptor = FetchDescriptor<RiderProfile>()

        if let profile = try? context.fetch(descriptor).first {
            if profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let suggestedName {
                profile.displayName = suggestedName
                profile.updatedAt = Date()
            }
            return profile
        }

        let profile = RiderProfile(displayName: suggestedName ?? "")
        context.insert(profile)
        return profile
    }

    private static func takeSuggestedDisplayName() -> String? {
        let name = UserDefaults.standard.string(forKey: suggestedDisplayNameKey)
        discardSuggestedDisplayName()
        return name
    }
}
