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

    func connect()
    func disconnect()
    func togglePlayPause()
    func skipToNext()
    func skipToPrevious()
}
