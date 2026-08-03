import Foundation
import os

/// In-memory log for auth/network flows that fail with opaque third-party errors (Spotify,
/// Supabase) — TestFlight builds have no attached debugger, so this is readable from the app
/// itself via `DebugLogView`. Also mirrors to the unified logging system for Console.app.
///
/// Never log secrets here (tokens, passwords) — entries are copyable from the device.
@Observable
final class DebugLog {
    static let shared = DebugLog()

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let category: String
        let message: String
    }

    private(set) var entries: [Entry] = []
    private let maxEntries = 300
    private let osLogger = Logger(subsystem: "com.oaktreehouse.kaido", category: "diagnostics")

    private init() {}

    func log(_ message: String, category: String) {
        osLogger.log("[\(category, privacy: .public)] \(message, privacy: .public)")

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.entries.append(Entry(date: Date(), category: category, message: message))
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
    }

    func clear() {
        entries.removeAll()
    }
}
