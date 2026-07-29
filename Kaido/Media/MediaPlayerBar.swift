import SwiftUI
import MediaPlayer

/// Collapsed Now Playing bar for the map screen — docked at the bottom, above the tab bar.
struct MediaPlayerBar: View {
    let manager: MediaPlayerManager

    var body: some View {
        HStack(spacing: 12) {
            artwork
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 1) {
                Text(manager.nowPlayingTitle ?? "Not Playing")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let artist = manager.nowPlayingArtist {
                    Text(artist)
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
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous track")

            Button {
                manager.togglePlayPause()
            } label: {
                Image(systemName: manager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(manager.isPlaying ? "Pause" : "Play")

            Button {
                manager.skipToNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 17))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next track")
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = manager.artwork?.image(at: CGSize(width: 80, height: 80)) {
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

#Preview {
    let manager = MediaPlayerManager()
    manager.nowPlayingTitle = "Ride Like The Wind"
    manager.nowPlayingArtist = "Christopher Cross"
    manager.isPlaying = true
    return MediaPlayerBar(manager: manager)
        .padding()
        .background(Color.kaidoMidnight)
}
