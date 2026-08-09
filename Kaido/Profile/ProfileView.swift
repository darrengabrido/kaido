import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(AuthState.self) private var authState
    @Environment(\.modelContext) private var modelContext
    @Query private var riderProfiles: [RiderProfile]
    private let mediaPlayerManager = MediaPlayerManager.shared

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
                    spotifyCard
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

    /// Lets you authorize Spotify before setting off — the Now Playing bar itself only appears
    /// during turn-by-turn, and connecting there would bounce you out to Spotify mid-ride.
    private var spotifyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Spotify", systemImage: "waveform")
                .font(.headline)

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

            Text("Playback controls appear on screen during turn-by-turn navigation.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
