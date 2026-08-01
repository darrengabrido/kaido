import SwiftUI

struct ProfileView: View {
    @Environment(AuthState.self) private var authState
    private let mediaPlayerManager = MediaPlayerManager.shared

    var body: some View {
        NavigationStack {
            List {
                accountSection
                rideTogetherSection
                spotifySection
            }
            .navigationTitle("Profile")
        }
    }

    // MARK: - Sections

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
}
