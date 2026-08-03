import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(AuthState.self) private var authState
    @Environment(\.modelContext) private var modelContext
    @Query private var riderProfiles: [RiderProfile]
    private let mediaPlayerManager = MediaPlayerManager.shared

    var body: some View {
        NavigationStack {
            List {
                riderProfileSection
                accountSection
                spotifySection
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

    /// Lets you authorize Spotify before setting off — the Now Playing bar itself only appears
    /// during turn-by-turn, and connecting there would bounce you out to Spotify mid-ride.
    private var spotifySection: some View {
        Section {
            HStack {
                Image(systemName: mediaPlayerManager.isConnected ? "music.note.list" : "music.note")
                    .foregroundStyle(mediaPlayerManager.isConnected ? Color.kaidoViolet : .secondary)
                Text(mediaPlayerManager.isConnected ? "Connected" : "Not Connected")
                    .lineLimit(1)
                Spacer()
                if mediaPlayerManager.isConnected {
                    Button("Disconnect", role: .destructive) {
                        mediaPlayerManager.disconnect()
                    }
                } else {
                    Button("Connect") {
                        mediaPlayerManager.connect()
                    }
                    .tint(.kaidoViolet)
                }
            }
            if let connectionError = mediaPlayerManager.connectionError {
                Text(connectionError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Spotify")
        } footer: {
            Text("Playback controls appear on screen during turn-by-turn navigation.")
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
