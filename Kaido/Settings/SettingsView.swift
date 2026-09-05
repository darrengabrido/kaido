import SwiftUI

/// Top-level Settings tab: Configuration for AI companion, ride settings, music, and diagnostics.
struct SettingsView: View {
    private let companion = Companion.shared
    private let sourceManager = MusicSourceManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    companionCard
                    rideTogetherCard
                    musicCard
                    debugLogRow
                    aboutCard
                }
                .padding()
            }
            .background(Color.kaidoMidnight)
            .navigationTitle("Settings")
        }
    }

    // MARK: - Cards

    private var companionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Companion", systemImage: "sparkles")
                .font(.headline)

            NavigationLink {
                CompanionSettingsView()
            } label: {
                HStack {
                    Text("AI provider & key")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(companion.settings.statusDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .settingsCard()
    }

    private var rideTogetherCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Ride Together", systemImage: "bubble.left.and.bubble.right")
                .font(.headline)

            NavigationLink {
                GroupRideCustomReplySettingsView()
            } label: {
                HStack {
                    Text("Quick Replies")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("Customize the quick-reply buttons shown to your group during a ride.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .settingsCard()
    }

    private var musicCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Music", systemImage: "waveform")
                .font(.headline)

            Picker("Source", selection: Binding(
                get: { sourceManager.selectedSource },
                set: { sourceManager.selectedSource = $0 }
            )) {
                ForEach(MusicSource.allCases) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)

            MusicConnectionRow(source: sourceManager.selectedSource, manager: sourceManager.activeProvider)
        }
        .settingsCard()
    }

    private var debugLogRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            NavigationLink {
                DebugLogView()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Debug Log")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("Sign-in and Spotify connection attempts are recorded here for troubleshooting.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .settingsCard()
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("About", systemImage: "info.circle")
                .font(.headline)

            HStack {
                Text("Version")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(appVersionString)
                    .foregroundStyle(.primary)
            }
            .font(.subheadline)
        }
        .settingsCard()
    }

    private var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

private extension View {
    func settingsCard() -> some View {
        padding(16)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct MusicConnectionRow: View {
    let source: MusicSource
    let manager: any NowPlayingProviding

    private var connectLabel: String {
        switch source {
        case .spotify: "Connect"
        case .appleMusic: "Enable"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: manager.isConnected ? "music.note.list" : "music.note")
                    .foregroundStyle(manager.isConnected ? Color.kaidoViolet : .secondary)
                Text(manager.isConnected ? "Connected" : "Not Connected")
                    .lineLimit(1)
                Spacer()
                if manager.isConnected {
                    Button("Disconnect", role: .destructive) {
                        manager.disconnect()
                    }
                } else {
                    Button(connectLabel) {
                        manager.connect()
                    }
                    .tint(.kaidoViolet)
                }
            }

            if let connectionError = manager.connectionError {
                Text(connectionError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Playback controls appear on screen during turn-by-turn navigation.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
