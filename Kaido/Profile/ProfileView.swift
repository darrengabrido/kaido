import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(AuthState.self) private var authState
    @Environment(\.modelContext) private var modelContext
    @Query private var riderProfiles: [RiderProfile]
    private let sourceManager = MusicSourceManager.shared
    private let companion = Companion.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if let profile = riderProfiles.first {
                        RiderShowcaseCard(profile: profile)
                    } else {
                        ProgressView("Preparing your profile…")
                            .frame(maxWidth: .infinity, minHeight: 140)
                    }

                    accountCard
                    companionCard
                    rideTogetherCard
                    musicCard
                    debugLogRow
                }
                .padding()
            }
            .background(Color.kaidoMidnight)
            .navigationTitle("Profile")
            .task {
                RiderProfileStore.ensureProfile(in: modelContext)
            }
        }
    }

    // MARK: - Cards

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Account", systemImage: "person.text.rectangle")
                .font(.headline)

            HStack {
                Image(systemName: authState.isAuthenticated ? "person.crop.circle.fill" : "person.crop.circle")
                    .foregroundStyle(authState.isAuthenticated ? Color.kaidoViolet : .secondary)
                Text(authState.user?.email ?? "Browsing as Guest")
                    .lineLimit(1)
                Spacer()
                if authState.isAuthenticated {
                    Button("Sign Out", role: .destructive) {
                        Task { try? await authState.signOut() }
                    }
                } else {
                    Button("Sign In") {
                        authState.exitGuestMode()
                    }
                    .tint(.kaidoViolet)
                }
            }
        }
        .profileCard()
    }

    /// The companion's brain lives here: which provider, which model, whose key. Kept out of
    /// the map so nobody is pasting API keys mid-ride.
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
        .profileCard()
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
        .profileCard()
    }

    /// Lets you authorize the chosen source before setting off — the Now Playing bar itself only
    /// appears during turn-by-turn, and connecting there would interrupt the ride.
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
        .profileCard()
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
        .profileCard()
    }
}

private extension View {
    func profileCard() -> some View {
        padding(16)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
    }
}

/// Connection status row shared by both music sources — status icon/text, connect/disconnect
/// button, and any error text.
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
