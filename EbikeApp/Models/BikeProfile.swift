import Foundation
import SwiftData

@Model
final class BikeProfile {
    var name: String = ""
    var peripheralIdentifier: String = ""
    var lastConnectedAt: Date?

    init(name: String, peripheralIdentifier: String) {
        self.name = name
        self.peripheralIdentifier = peripheralIdentifier
    }
}
