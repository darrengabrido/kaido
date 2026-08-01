import Foundation

enum GroupRideMessageValidationError: LocalizedError, Equatable {
    case empty
    case tooLong(limit: Int)

    var errorDescription: String? {
        switch self {
        case .empty:
            return String(localized: "Message can't be empty.")
        case .tooLong(let limit):
            return String(localized: "Message must be \(limit) characters or fewer.")
        }
    }
}

enum GroupRideMessageValidator {
    static func validate(body: String) throws {
        guard !body.isEmpty else { throw GroupRideMessageValidationError.empty }
        guard body.count <= GroupRideConfig.maxMessageBodyLength else {
            throw GroupRideMessageValidationError.tooLong(limit: GroupRideConfig.maxMessageBodyLength)
        }
    }
}
