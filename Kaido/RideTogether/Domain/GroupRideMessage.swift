import Foundation

enum GroupRideMessageKind: String, Codable, Sendable {
    case preset
    case dictated
    case system
}

/// Safety-oriented preset quick messages. `presetKey` is the stable identifier stored in
/// `group_ride_messages.preset_key`; `body` is the display/spoken text sent with the message so
/// recipients on an older app version still see readable text even if presets are renamed later.
enum GroupRideQuickPreset: String, CaseIterable, Identifiable, Sendable {
    case slowDown = "slow_down"
    case imBehind = "im_behind"
    case stopping = "stopping"
    case mechanicalIssue = "mechanical_issue"
    case allGood = "all_good"
    case goAhead = "go_ahead"

    var id: String { rawValue }

    /// Deliberately avoids any language implying Kaido contacted emergency services —
    /// "mechanical issue" reads as a rider need, not a dispatched alert.
    var body: String {
        switch self {
        case .slowDown: return "Slow down"
        case .imBehind: return "I'm behind"
        case .stopping: return "Stopping"
        case .mechanicalIssue: return "Mechanical issue"
        case .allGood: return "All good"
        case .goAhead: return "Go ahead"
        }
    }

    var systemImage: String {
        switch self {
        case .slowDown: return "tortoise.fill"
        case .imBehind: return "arrow.left.circle.fill"
        case .stopping: return "pause.circle.fill"
        case .mechanicalIssue: return "wrench.and.screwdriver.fill"
        case .allGood: return "hand.thumbsup.fill"
        case .goAhead: return "arrow.right.circle.fill"
        }
    }
}

/// One durable message in a group ride's history. Mirrors `group_ride_messages`.
struct GroupRideMessage: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let rideId: UUID
    let senderUserId: UUID
    var senderDisplayName: String
    var kind: GroupRideMessageKind
    var body: String
    var presetKey: String?
    /// Client-generated idempotency key — retrying a send after a dropped response reuses the
    /// same value so the server can no-op a duplicate insert instead of double-delivering it.
    let clientMessageId: UUID
    let createdAt: Date
}
