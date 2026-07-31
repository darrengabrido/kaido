import Foundation
import SpotifyiOS
import UIKit

/// Mirrors and drives the Spotify app's playback so the map screen can show a Now Playing bar
/// without owning any audio itself. Connection is via Spotify's App Remote, which requires the
/// Spotify app to be installed and a Premium account to accept transport commands.
@Observable
final class MediaPlayerManager: NSObject {
    /// Shared because the OAuth redirect arrives app-wide via `onOpenURL`, which has no way to
    /// reach a view-owned instance.
    static let shared = MediaPlayerManager()

    private static let redirectURL = URL(string: "kaido://spotify-callback")!

    private static var clientID: String {
        Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String ?? ""
    }

    private(set) var isConnected = false
    private(set) var isPlaying = false
    private(set) var trackTitle: String?
    private(set) var artistName: String?
    private(set) var artwork: UIImage?
    private(set) var connectionError: String?

    var hasNowPlayingItem: Bool { trackTitle != nil }

    @ObservationIgnored
    private lazy var appRemote: SPTAppRemote = {
        let configuration = SPTConfiguration(clientID: Self.clientID, redirectURL: Self.redirectURL)
        let remote = SPTAppRemote(configuration: configuration, logLevel: .none)
        remote.delegate = self
        return remote
    }()

    private override init() {
        super.init()
    }

    /// Bounces out to the Spotify app to authorize; control returns via `handleAuthCallback`.
    func connect() {
        guard !appRemote.isConnected else { return }
        connectionError = nil

        guard appRemote.connectionParameters.accessToken == nil else {
            appRemote.connect()
            return
        }

        appRemote.authorizeAndPlayURI("") { [weak self] success in
            guard !success else { return }
            DispatchQueue.main.async {
                self?.connectionError = "Install Spotify to control playback here."
            }
        }
    }

    /// Resumes an existing session without bouncing to Spotify — safe to call on every foreground.
    func reconnectIfPossible() {
        guard !appRemote.isConnected, appRemote.connectionParameters.accessToken != nil else { return }
        appRemote.connect()
    }

    func disconnect() {
        guard appRemote.isConnected else { return }
        appRemote.disconnect()
    }

    func handleAuthCallback(_ url: URL) {
        let parameters = appRemote.authorizationParameters(from: url)

        if let token = parameters?[SPTAppRemoteAccessTokenKey] {
            appRemote.connectionParameters.accessToken = token
            appRemote.connect()
        } else if let message = parameters?[SPTAppRemoteErrorDescriptionKey] {
            connectionError = message
        }
    }

    func togglePlayPause() {
        guard let playerAPI = appRemote.playerAPI else { return }
        if isPlaying {
            playerAPI.pause(nil)
        } else {
            playerAPI.resume(nil)
        }
    }

    func skipToNext() {
        appRemote.playerAPI?.skip(toNext: nil)
    }

    func skipToPrevious() {
        appRemote.playerAPI?.skip(toPrevious: nil)
    }

    private func apply(_ playerState: any SPTAppRemotePlayerState) {
        isPlaying = !playerState.isPaused
        trackTitle = playerState.track.name
        artistName = playerState.track.artist.name

        appRemote.imageAPI?.fetchImage(
            forItem: playerState.track,
            with: CGSize(width: 80, height: 80)
        ) { [weak self] image, _ in
            self?.artwork = image as? UIImage
        }
    }
}

extension MediaPlayerManager: SPTAppRemoteDelegate {
    func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        isConnected = true
        connectionError = nil

        appRemote.playerAPI?.delegate = self
        appRemote.playerAPI?.subscribe(toPlayerState: nil)
        appRemote.playerAPI?.getPlayerState { [weak self] state, _ in
            guard let playerState = state as? any SPTAppRemotePlayerState else { return }
            self?.apply(playerState)
        }
    }

    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        isConnected = false
        connectionError = error?.localizedDescription
    }

    func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        isConnected = false
        connectionError = error?.localizedDescription
    }
}

extension MediaPlayerManager: SPTAppRemotePlayerStateDelegate {
    func playerStateDidChange(_ playerState: any SPTAppRemotePlayerState) {
        apply(playerState)
    }
}
