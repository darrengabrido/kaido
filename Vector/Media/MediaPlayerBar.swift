import SwiftUI

/// Collapsed Now Playing bar for the map screen — docked at the bottom, above the tab bar.
struct MediaPlayerBar: View {
    let manager: MediaPlayerManager

    var body: some View {
        Group {
            if manager.isConnected {
                nowPlaying
            } else {
                connectPrompt
            }
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Without this the bar's taps fall straight through to the Mapbox map's gesture
        // recognizers underneath, leaving the transport buttons dead — same bug the route
        // planner's control panel hit.
        .contentShape(Rectangle())
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    private var connectPrompt: some View {
        Button {
            manager.connect()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "music.note")
                    .font(.system(size: 17))
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Connect Spotify")
                        .font(.subheadline.weight(.medium))
                    if let connectionError = manager.connectionError {
                        Text(connectionError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var nowPlaying: some View {
        HStack(spacing: 12) {
            artwork
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 1) {
                Text(manager.trackTitle ?? "Not Playing")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if let artistName = manager.artistName {
                    Text(artistName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button {
                manager.skipToPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 17))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous track")

            Button {
                manager.togglePlayPause()
            } label: {
                Image(systemName: manager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(manager.isPlaying ? "Pause" : "Play")

            Button {
                manager.skipToNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 17))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next track")
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = manager.artwork {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
