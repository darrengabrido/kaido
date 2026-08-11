import Foundation
import MediaPlayer
import UIKit

/// Mirrors and drives whatever is playing in the system Music app via `MPMusicPlayerController`.
/// Unlike Spotify's App Remote this needs no OAuth bounce out to another app — "connect" only
/// ever means requesting or re-checking Media Library authorization.
@Observable
@MainActor
final class AppleMusicManager {
    static let shared = AppleMusicManager()

    private let player = MPMusicPlayerController.systemMusicPlayer
    private var nowPlayingObserver: NSObjectProtocol?
    private var playbackStateObserver: NSObjectProtocol?
    private var isObserving = false

    private(set) var isConnected = false
    private(set) var isPlaying = false
    private(set) var trackTitle: String?
    private(set) var artistName: String?
    private(set) var artwork: UIImage?
    private(set) var connectionError: String?

    var hasNowPlayingItem: Bool { trackTitle != nil }

    private init() {
        if MPMediaLibrary.authorizationStatus() == .authorized {
            beginObserving()
        }
    }

    /// Prompts for Media Library access if not yet determined; if the user already denied it,
    /// this just re-surfaces the same error without a redundant system prompt.
    func connect() {
        MPMediaLibrary.requestAuthorization { [weak self] status in
            Task { @MainActor in self?.apply(status) }
        }
    }

    /// Re-checks authorization without prompting — safe to call on every foreground, mirroring
    /// `MediaPlayerManager.reconnectIfPossible()`.
    func refreshAuthorizationStatus() {
        apply(MPMediaLibrary.authorizationStatus())
    }

    func disconnect() {
        stopObserving()
    }

    func togglePlayPause() {
        if player.playbackState == .playing {
            player.pause()
        } else {
            player.play()
        }
    }

    func skipToNext() {
        player.skipToNextItem()
    }

    func skipToPrevious() {
        player.skipToPreviousItem()
    }

    // MARK: - Private

    private func apply(_ status: MPMediaLibraryAuthorizationStatus) {
        switch status {
        case .authorized:
            connectionError = nil
            beginObserving()
        case .denied, .restricted:
            stopObserving()
            connectionError = "Allow access to Apple Music in Settings to control playback here."
        case .notDetermined:
            stopObserving()
        @unknown default:
            stopObserving()
        }
    }

    private func beginObserving() {
        guard !isObserving else { return }
        isObserving = true
        isConnected = true

        player.beginGeneratingPlaybackNotifications()
        let center = NotificationCenter.default
        nowPlayingObserver = center.addObserver(
            forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: player,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        playbackStateObserver = center.addObserver(
            forName: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: player,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    private func stopObserving() {
        guard isObserving else { return }
        isObserving = false
        isConnected = false

        if let nowPlayingObserver { NotificationCenter.default.removeObserver(nowPlayingObserver) }
        if let playbackStateObserver { NotificationCenter.default.removeObserver(playbackStateObserver) }
        nowPlayingObserver = nil
        playbackStateObserver = nil
        player.endGeneratingPlaybackNotifications()

        isPlaying = false
        trackTitle = nil
        artistName = nil
        artwork = nil
    }

    private func refresh() {
        isPlaying = player.playbackState == .playing
        let item = player.nowPlayingItem
        trackTitle = item?.title
        artistName = item?.artist
        artwork = item?.artwork?.image(at: CGSize(width: 80, height: 80))
    }
}

extension AppleMusicManager: NowPlayingProviding {}
