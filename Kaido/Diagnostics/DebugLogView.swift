import SwiftUI
import UIKit

struct DebugLogView: View {
    private let log = DebugLog.shared

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        List {
            if log.entries.isEmpty {
                Text("No log entries yet. Try connecting Spotify or signing in.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(log.entries.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Self.timeFormatter.string(from: entry.date))  ·  \(entry.category)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(entry.message)
                            .font(.system(.footnote, design: .monospaced))
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Debug Log")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Copy All") {
                        UIPasteboard.general.string = log.entries
                            .map { "\(Self.timeFormatter.string(from: $0.date)) [\($0.category)] \($0.message)" }
                            .joined(separator: "\n")
                    }
                    Button("Clear", role: .destructive) {
                        log.clear()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
}
