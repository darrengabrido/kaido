import SwiftUI

/// Shared across both music sources — a plain `let` outside the generic `MediaPlayerBarContent`
/// since generic types can't hold static stored properties.
private let expandAnimation: Animation = .spring(response: 0.35, dampingFraction: 0.85)

/// Collapsed Now Playing bar shown during live navigation — docked just above Mapbox's bottom
/// banner. See `NavigationSessionView.addMediaPlayerBar`.
///
/// Observes `MusicSourceManager` and the concrete provider for the selected source. Passing an
/// `any NowPlayingProviding` existential breaks Observation, so connection updates never reached
/// the UI.
struct MediaPlayerBar: View {
    private let sourceManager = MusicSourceManager.shared

    var body: some View {
        switch sourceManager.selectedSource {
        case .spotify:
            MediaPlayerBarContent(source: .spotify, manager: MediaPlayerManager.shared)
        case .appleMusic:
            MediaPlayerBarContent(source: .appleMusic, manager: AppleMusicManager.shared)
        }
    }
}

private struct MediaPlayerBarContent<Manager: NowPlayingProviding>: View {
    let source: MusicSource
    let manager: Manager

    /// Bumped on every transport tap to drive `.sensoryFeedback` below — a rider glancing at
    /// (or blindly tapping) a handlebar-mounted phone benefits from a tactile "that registered"
    /// cue more than from watching the icon change.
    @State private var hapticTick = 0

    /// Live horizontal offset while dragging, so the card visibly follows the swipe before
    /// springing back. Purely cosmetic — `skipGesture` decides whether the drag committed.
    @State private var dragOffset: CGFloat = 0

    /// Dropdown state — the bar has no fixed height (see `NavigationSessionView`, which docks it
    /// with only leading/trailing/bottom constraints), so growing this view's content simply
    /// grows the card in place and pushes the map's viewport padding up to match.
    @State private var isExpanded = false

    /// While the user is dragging the scrubber, it shows this instead of the live
    /// `manager.playbackPosition` so their thumb position doesn't jump underneath them.
    @State private var isScrubbing = false
    @State private var scrubPosition: TimeInterval = 0

    var body: some View {
        Group {
            if manager.isConnected {
                connectedContent
            } else {
                connectPrompt
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .foregroundStyle(Color.primary)
        // Without this the bar's taps fall straight through to the Mapbox map's gesture
        // recognizers underneath, leaving the transport buttons dead — same bug the route
        // planner's control panel hit.
        .contentShape(Rectangle())
        // Matches the 20pt radius GlassTopBanner/GlassBottomBanner use, so the three docked
        // cards read as one family during navigation.
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTick)
    }

    // MARK: - Connected: collapsed row + dropdown

    private var connectedContent: some View {
        VStack(spacing: 0) {
            nowPlayingRow
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            if isExpanded {
                expandedControls
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            disclosureHandle
        }
        .animation(expandAnimation, value: isExpanded)
    }

    private var nowPlayingRow: some View {
        HStack(spacing: 12) {
            artwork
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                // The track info text conveys the same thing; avoid a redundant unlabeled stop.
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(manager.trackTitle ?? "Not Playing")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                HStack(spacing: 4) {
                    Image(systemName: source.systemImage)
                        .font(.caption2)
                    Text(manager.artistName ?? source.title)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)

                // The dropdown below already shows a full scrubber — no need for both at once.
                if !isExpanded, manager.trackDuration > 0 {
                    ThinProgressLine(progress: manager.playbackPosition / manager.trackDuration)
                        .padding(.top, 1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityNowPlayingLabel)
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

    /// Thin chevron strip spanning the card's full width — tap to drop the panel open or closed.
    /// A persistent, obvious affordance beats hiding this behind a tap on the artwork or track
    /// info, which read as informational rather than interactive.
    private var disclosureHandle: some View {
        Button {
            withAnimation(expandAnimation) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Collapse player controls" : "Expand player controls")
    }

    // MARK: - Expanded: scrubber + shuffle/repeat/volume

    private var expandedControls: some View {
        VStack(spacing: 14) {
            scrubber
            optionsRow
        }
    }

    private var scrubber: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubPosition : manager.playbackPosition },
                    set: { scrubPosition = $0 }
                ),
                in: 0...max(manager.trackDuration, 1),
                onEditingChanged: { editing in
                    if editing {
                        scrubPosition = manager.playbackPosition
                        isScrubbing = true
                    } else {
                        manager.seek(to: scrubPosition)
                        isScrubbing = false
                    }
                }
            )
            .tint(Color.kaidoViolet)
            .disabled(manager.trackDuration <= 0)

            HStack {
                Text(Self.formatted(isScrubbing ? scrubPosition : manager.playbackPosition))
                Spacer()
                Text(Self.formatted(manager.trackDuration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var optionsRow: some View {
        HStack {
            Button {
                manager.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 16))
                    .frame(width: 36, height: 36)
            }
            .foregroundStyle(manager.isShuffleEnabled ? Color.kaidoViolet : .secondary)
            .accessibilityLabel("Shuffle")
            .accessibilityValue(manager.isShuffleEnabled ? "On" : "Off")

            Spacer()

            volumeControl

            Spacer()

            Button {
                manager.cycleRepeatMode()
            } label: {
                Image(systemName: manager.repeatMode.systemImage)
                    .font(.system(size: 16))
                    .frame(width: 36, height: 36)
            }
            .foregroundStyle(manager.repeatMode == .off ? .secondary : Color.kaidoViolet)
            .accessibilityLabel("Repeat")
            .accessibilityValue(repeatAccessibilityValue)
        }
        .buttonStyle(.plain)
    }

    private var repeatAccessibilityValue: String {
        switch manager.repeatMode {
        case .off: "Off"
        case .one: "One"
        case .all: "All"
        }
    }

    private var volumeControl: some View {
        HStack(spacing: 14) {
            Image(systemName: "speaker.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button {
                SystemVolumeControl.adjust(by: -SystemVolumeControl.step)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20))
            }
            .accessibilityLabel("Volume down")

            Button {
                SystemVolumeControl.adjust(by: SystemVolumeControl.step)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
            }
            .accessibilityLabel("Volume up")

            Image(systemName: "speaker.wave.3.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
    }

    // MARK: - Disconnected

    private var connectTitle: String {
        switch source {
        case .spotify: "Connect Spotify"
        case .appleMusic: "Enable Apple Music"
        }
    }

    private var connectPrompt: some View {
        Button {
            manager.connect()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: source.systemImage)
                    .font(.system(size: 17))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(Color.kaidoViolet)

                VStack(alignment: .leading, spacing: 1) {
                    Text(connectTitle)
                        .font(.subheadline.weight(.medium))
                    if let connectionError = manager.connectionError {
                        Text(connectionError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(source.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(connectTitle)
    }

    // MARK: - Shared helpers

    private var accessibilityNowPlayingLabel: String {
        let track = manager.trackTitle ?? "Not Playing"
        if let artist = manager.artistName {
            return "\(source.title): \(track), \(artist)"
        }
        return "\(source.title): \(track)"
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
                Image(systemName: source.systemImage)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static func formatted(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let total = Int(time.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// A slim, read-only playback progress indicator shown only while collapsed — the dropdown's
/// scrubber takes over once expanded.
private struct ThinProgressLine: View {
    /// 0...1. Values outside that range are clamped.
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25))
                Capsule()
                    .fill(Color.kaidoViolet)
                    .frame(width: geometry.size.width * max(0, min(1, progress)))
            }
        }
        .frame(height: 2.5)
    }
}

#Preview {
    MediaPlayerBar()
        .padding()
        .background(Color.kaidoMidnight)
}
