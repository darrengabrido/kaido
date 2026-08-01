import Foundation

enum GroupRideCustomReplyError: LocalizedError, Equatable {
    case empty
    case tooLong(limit: Int)
    case tooMany(limit: Int)

    var errorDescription: String? {
        switch self {
        case .empty:
            return String(localized: "Quick reply can't be empty.")
        case .tooLong(let limit):
            return String(localized: "Quick replies must be \(limit) characters or fewer.")
        case .tooMany(let limit):
            return String(localized: "You can save up to \(limit) custom quick replies.")
        }
    }
}

/// Locally configured custom quick replies — up to `GroupRideConfig.maxCustomQuickReplies`,
/// `GroupRideConfig.maxCustomQuickReplyLength` characters each. Stored with Kaido's existing
/// settings persistence (`UserDefaults`), never synced as ride state, and edited outside of
/// active navigation (see `GroupRideCustomReplySettingsView`) — never via freeform typing while
/// riding.
enum GroupRideCustomReplyStore {
    private static let key = "kaido.rideTogether.customReplies"

    static var replies: [String] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            let clamped = Array(newValue.prefix(GroupRideConfig.maxCustomQuickReplies))
            guard let data = try? JSONEncoder().encode(clamped) else { return }
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func validate(_ reply: String) throws {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GroupRideCustomReplyError.empty }
        guard trimmed.count <= GroupRideConfig.maxCustomQuickReplyLength else {
            throw GroupRideCustomReplyError.tooLong(limit: GroupRideConfig.maxCustomQuickReplyLength)
        }
    }

    @discardableResult
    static func add(_ reply: String) throws -> [String] {
        try validate(reply)
        var current = replies
        guard current.count < GroupRideConfig.maxCustomQuickReplies else {
            throw GroupRideCustomReplyError.tooMany(limit: GroupRideConfig.maxCustomQuickReplies)
        }
        current.append(reply.trimmingCharacters(in: .whitespacesAndNewlines))
        replies = current
        return current
    }

    static func remove(at index: Int) {
        var current = replies
        guard current.indices.contains(index) else { return }
        current.remove(at: index)
        replies = current
    }
}
