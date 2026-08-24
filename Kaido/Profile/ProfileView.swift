import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(AuthState.self) private var authState
    @Environment(\.modelContext) private var modelContext
    @Query private var riderProfiles: [RiderProfile]
    @Bindable private var sourceManager = MusicSourceManager.shared

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
            .accessibilityLabel("Music source")

            switch sourceManager.selectedSource {
            case .spotify:
                MusicConnectionRow(source: .spotify, manager: MediaPlayerManager.shared)
            case .appleMusic:
                MusicConnectionRow(source: .appleMusic, manager: AppleMusicManager.shared)
            }
        }
        .profileCard()
        .animation(.easeInOut(duration: 0.2), value: sourceManager.selectedSource)
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
/// button, and any error text. Generic over the concrete manager so Observation tracks
/// `isConnected` (existentials erase that).
private struct MusicConnectionRow<Manager: NowPlayingProviding>: View {
    let source: MusicSource
    let manager: Manager

    private var connectLabel: String {
        switch source {
        case .spotify: "Connect"
        case .appleMusic: "Enable"
        }
    }

    private var statusText: String {
        source.statusLabel(isConnected: manager.isConnected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: source.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(manager.isConnected ? Color.kaidoViolet : .secondary)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.title)
                        .font(.subheadline.weight(.semibold))
                    Text(manager.isConnected ? "Connected" : "Not Connected")
                        .font(.caption)
                        .foregroundStyle(manager.isConnected ? Color.kaidoViolet : .secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(statusText)

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
