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

enum RidePurpose: String, CaseIterable, Identifiable, Sendable {
    case commute
    case fitness
    case leisure
    case social

    var id: String { rawValue }

    var title: String {
        switch self {
        case .commute: "Commuting"
        case .fitness: "Fitness"
        case .leisure: "Leisure riding"
        case .social: "Social rides"
        }
    }

    var systemImage: String {
        switch self {
        case .commute: "briefcase"
        case .fitness: "figure.outdoor.cycle"
        case .leisure: "leaf"
        case .social: "person.2"
        }
    }
}

enum InterestTag: String, CaseIterable, Identifiable, Sendable {
    case coffee
    case natureParks
    case food
    case landmarksScenery
    case nightlife
    case familyFriendly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coffee: "Coffee"
        case .natureParks: "Nature & parks"
        case .food: "Food"
        case .landmarksScenery: "Landmarks & scenery"
        case .nightlife: "Nightlife"
        case .familyFriendly: "Family-friendly"
        }
    }

    var systemImage: String {
        switch self {
        case .coffee: "cup.and.saucer"
        case .natureParks: "tree"
        case .food: "fork.knife"
        case .landmarksScenery: "camera"
        case .nightlife: "moon.stars"
        case .familyFriendly: "figure.2.and.child.holdinghands"
        }
    }

    /// Mapbox Search Box category slugs this tag pulls into discovery / biases toward.
    /// `familyFriendly` has none — it's a tone-only cue for the AI prompt, not a fetchable category.
    var poiCategories: [String] {
        switch self {
        case .coffee: ["coffee"]
        case .natureParks: ["park"]
        case .food: ["restaurant", "bakery"]
        case .landmarksScenery: ["tourist_attraction"]
        case .nightlife: ["bar"]
        case .familyFriendly: []
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
    /// Nil until the rider states a purpose — unlike `experienceLevel`, there's no neutral
    /// default that wouldn't silently bias AI stop curation for riders who never set this.
    var ridePurposeRaw: String?
    var interestTagsRaw: String = ""
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
        experienceLevel: RiderExperienceLevel = .recreational,
        ridePurpose: RidePurpose? = nil,
        interestTags: [InterestTag] = []
    ) {
        self.displayName = displayName
        self.homeCity = homeCity
        self.bio = bio
        experienceLevelRaw = experienceLevel.rawValue
        ridePurposeRaw = ridePurpose?.rawValue
        interestTagsRaw = interestTags.map(\.rawValue).joined(separator: ",")
    }

    var experienceLevel: RiderExperienceLevel {
        get { RiderExperienceLevel(rawValue: experienceLevelRaw) ?? .recreational }
        set { experienceLevelRaw = newValue.rawValue }
    }

    var ridePurpose: RidePurpose? {
        get { ridePurposeRaw.flatMap(RidePurpose.init(rawValue:)) }
        set { ridePurposeRaw = newValue?.rawValue }
    }

    var interestTags: [InterestTag] {
        get { interestTagsRaw.split(separator: ",").compactMap { InterestTag(rawValue: String($0)) } }
        set { interestTagsRaw = newValue.map(\.rawValue).joined(separator: ",") }
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
