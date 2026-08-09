import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(AuthState.self) private var authState
    @Environment(\.modelContext) private var modelContext
    @Query private var riderProfiles: [RiderProfile]
    private let sourceManager = MusicSourceManager.shared

    var body: some View {
        NavigationStack {
            List {
                riderProfileSection
                accountSection
                rideTogetherSection
                musicSourceSection
                musicConnectionSection
                diagnosticsSection
            }
            .navigationTitle("Profile")
            .task {
                RiderProfileStore.ensureProfile(in: modelContext)
            }
        }
    }

    // MARK: - Sections

    private var riderProfileSection: some View {
        Section {
            if let profile = riderProfiles.first {
                NavigationLink {
                    RiderProfileEditorView(profile: profile)
                } label: {
                    HStack(spacing: 14) {
                        RiderAvatarView(displayName: profile.displayName)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.displayName.isEmpty ? "Add your profile" : profile.displayName)
                                .font(.headline)

                            if profile.displayName.isEmpty {
                                Text("Tell Kaido a little about you")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Label(
                                    profile.homeCity.isEmpty
                                        ? profile.experienceLevel.title
                                        : "\(profile.homeCity) · \(profile.experienceLevel.title)",
                                    systemImage: profile.experienceLevel.systemImage
                                )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                ProgressView("Preparing your profile…")
            }
        } header: {
            Text("Rider Profile")
        } footer: {
            Text("Your profile works whether you sign in or continue as a guest.")
        }
    }

    private var accountSection: some View {
        Section {
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
        } header: {
            Text("Account")
        }
    }

    private var rideTogetherSection: some View {
        Section {
            NavigationLink {
                GroupRideCustomReplySettingsView()
            } label: {
                Label("Ride Together Quick Replies", systemImage: "bubble.left.and.bubble.right")
            }
        } header: {
            Text("Ride Together")
        } footer: {
            Text("Customize the quick-reply buttons shown to your group during a ride.")
        }
    }

    private var musicSourceSection: some View {
        Section {
            Picker("Source", selection: Binding(
                get: { sourceManager.selectedSource },
                set: { sourceManager.selectedSource = $0 }
            )) {
                ForEach(MusicSource.allCases) { source in
                    Label(source.title, systemImage: source.systemImage).tag(source)
                }
            }
            .pickerStyle(.inline)
        } header: {
            Text("Music")
        }
    }

    /// Lets you authorize the chosen source before setting off — the Now Playing bar itself only
    /// appears during turn-by-turn, and connecting there would interrupt the ride.
    @ViewBuilder
    private var musicConnectionSection: some View {
        switch sourceManager.selectedSource {
        case .spotify: MusicConnectionRow(source: .spotify, manager: MediaPlayerManager.shared)
        case .appleMusic: MusicConnectionRow(source: .appleMusic, manager: AppleMusicManager.shared)
        }
    }

    private var diagnosticsSection: some View {
        Section {
            NavigationLink("Debug Log") {
                DebugLogView()
            }
        } footer: {
            Text("Sign-in and Spotify connection attempts are recorded here for troubleshooting.")
        }
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
        Section {
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
        } header: {
            Text(source.title)
        } footer: {
            Text("Playback controls appear on screen during turn-by-turn navigation.")
        }
    }
}
