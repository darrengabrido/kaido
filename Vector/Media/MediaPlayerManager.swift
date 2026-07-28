import Foundation
import MediaPlayer

/// Controls Apple Music's system player so the map screen can show a Now Playing bar without
/// owning any playback itself — this mirrors and drives whatever the Music app is already doing.
@Observable
@MainActor
final class MediaPlayerManager {
    private let player = MPMusicPlayerController.systemMusicPlayer
    private var nowPlayingObserver: NSObjectProtocol?
    private var playbackStateObserver: NSObjectProtocol?

    var isPlaying = false
    var nowPlayingTitle: String?
    var nowPlayingArtist: String?
    var artwork: MPMediaItemArtwork?

    var hasNowPlayingItem: Bool { nowPlayingTitle != nil }

    init() {
        player.beginGeneratingPlaybackNotifications()
        let center = NotificationCenter.default
        nowPlayingObserver = center.addObserver(
            forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: player,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        playbackStateObserver = center.addObserver(
            forName: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: player,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        refresh()
    }

    func togglePlayPause() {
        if player.playbackState == .playing {
            player.pause()
        } else {
            player.play()
        }
        refresh()
    }

    func skipToPrevious() {
        player.skipToPreviousItem()
    }

    func skipToNext() {
        player.skipToNextItem()
    }

    private func refresh() {
        isPlaying = player.playbackState == .playing
        let item = player.nowPlayingItem
        nowPlayingTitle = item?.title
        nowPlayingArtist = item?.artist
        artwork = item?.artwork
    }
}
