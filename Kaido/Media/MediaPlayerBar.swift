import SwiftUI

/// Collapsed Now Playing bar shown during live navigation — docked just above Mapbox's bottom
/// banner. See `NavigationSessionView.addMediaPlayerBar`.
struct MediaPlayerBar: View {
    let manager: MediaPlayerManager

    /// Bumped on every transport tap to drive `.sensoryFeedback` below — a rider glancing at
    /// (or blindly tapping) a handlebar-mounted phone benefits from a tactile "that registered"
    /// cue more than from watching the icon change.
    @State private var hapticTick = 0

    /// Live horizontal offset while dragging, so the card visibly follows the swipe before
    /// springing back. Purely cosmetic — `skipGesture` decides whether the drag committed.
    @State private var dragOffset: CGFloat = 0

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
        // Matches the 20pt radius GlassTopBanner/GlassBottomBanner use, so the three docked
        // cards read as one family during navigation.
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTick)
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
                // The track info text conveys the same thing; avoid a redundant unlabeled stop.
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(manager.trackTitle ?? "Not Playing")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                if let artistName = manager.artistName {
                    Text(artistName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
            }
            .accessibilityElement(children: .combine)
            .animation(.easeInOut(duration: 0.2), value: manager.trackTitle)

            Spacer(minLength: 8)

            Button {
                perform { manager.skipToPrevious() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 17))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous track")

            Button {
                perform { manager.togglePlayPause() }
            } label: {
                Image(systemName: manager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(manager.isPlaying ? "Pause" : "Play")
            .animation(.default, value: manager.isPlaying)

            Button {
                perform { manager.skipToNext() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 17))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next track")
        }
        .offset(x: dragOffset)
        .gesture(skipGesture)
    }

    /// Swiping the card is a much bigger, more forgiving target than a 32pt transport icon —
    /// worth having on a handlebar mount where you're aiming by feel, not by looking. Purely
    /// additive: the three buttons above are untouched, so nothing changes for VoiceOver.
    /// `minimumDistance` keeps this from competing with them — an ordinary tap never moves far
    /// enough to engage it.
    private var skipGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                dragOffset = max(-120, min(120, value.translation.width))
            }
            .onEnded { value in
                let translation = value.translation.width
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    dragOffset = 0
                }
                if translation <= -60 {
                    perform { manager.skipToNext() }
                } else if translation >= 60 {
                    perform { manager.skipToPrevious() }
                }
            }
    }

    /// Routes every transport action through the shared haptic tick so each control gets the
    /// same tactile confirmation.
    private func perform(_ action: () -> Void) {
        hapticTick += 1
        action()
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

#Preview {
    MediaPlayerBar(manager: MediaPlayerManager.shared)
        .padding()
        .background(Color.kaidoMidnight)
}

