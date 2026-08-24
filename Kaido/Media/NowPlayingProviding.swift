import UIKit

/// Common surface for anything that can drive the Now Playing bar, regardless of which
/// external player it mirrors. OAuth/callback lifecycle (Spotify's App Remote) isn't part of
/// this — that stays specific to `MediaPlayerManager`.
@MainActor
protocol NowPlayingProviding: AnyObject {
    var isConnected: Bool { get }
    var isPlaying: Bool { get }
    var trackTitle: String? { get }
    var artistName: String? { get }
    var artwork: UIImage? { get }
    var connectionError: String? { get }
    var hasNowPlayingItem: Bool { get }

    /// Elapsed playback time, in seconds. `0` before the first state update.
    var playbackPosition: TimeInterval { get }
    /// Total track length, in seconds. `0` when unknown.
    var trackDuration: TimeInterval { get }
    var isShuffleEnabled: Bool { get }
    var repeatMode: NowPlayingRepeatMode { get }

    func connect()
    func disconnect()
    func togglePlayPause()
    func skipToNext()
    func skipToPrevious()
    /// Jumps playback to `position` seconds into the current track.
    func seek(to position: TimeInterval)
    func toggleShuffle()
    /// Advances repeat through off → all → one → off.
    func cycleRepeatMode()
}

/// Normalizes Spotify's off/track/context and Apple Music's none/one/all repeat states into one
/// shared vocabulary for the UI.
enum NowPlayingRepeatMode: Equatable {
    case off
    case one
    case all

    var systemImage: String {
        switch self {
        case .off, .all: "repeat"
        case .one: "repeat.1"
        }
    }
}
