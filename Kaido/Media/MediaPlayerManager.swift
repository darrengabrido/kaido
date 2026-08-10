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

    /// Seconds. App Remote only pushes a new player state on play/pause/seek/track-change, not
    /// every tick, so `positionTicker` interpolates between updates while playing.
    private(set) var playbackPosition: TimeInterval = 0
    private(set) var trackDuration: TimeInterval = 0
    private(set) var isShuffleEnabled = false
    private(set) var repeatMode: NowPlayingRepeatMode = .off

    var hasNowPlayingItem: Bool { trackTitle != nil }

    /// True when we have a stored token and can reconnect without a full first-time authorize.
    var hasSavedSession: Bool {
        appRemote.connectionParameters.accessToken != nil
    }

    @ObservationIgnored
    private lazy var appRemote: SPTAppRemote = {
        let configuration = SPTConfiguration(clientID: Self.clientID, redirectURL: Self.redirectURL)
        let remote = SPTAppRemote(configuration: configuration, logLevel: .debug)
        remote.delegate = self
        if let token = SpotifyAccessTokenStore.load() {
            remote.connectionParameters.accessToken = token
            DebugLog.shared.log("Restored access token from Keychain (\(token.count) chars).", category: "Spotify")
        }
        return remote
    }()

    /// Set before an intentional `disconnect()` so the delegate does not surface a transient
    /// error when we tear down for backgrounding or a manual Disconnect.
    @ObservationIgnored
    private var ignoreNextDisconnectError = false

    /// Fires once a second while playing to advance `playbackPosition` between real state
    /// updates from the Spotify app.
    @ObservationIgnored
    private var positionTicker: Timer?

    private override init() {
        super.init()
    }

    /// User-initiated connect. Always app-switches into Spotify so a suspended Spotify process
    /// is woken — silent `connect()` only works while Spotify is already alive.
    func connect() {
        guard !appRemote.isConnected else { return }
        connectionError = nil

        DebugLog.shared.log("connect() starting authorizeAndPlayURI.", category: "Spotify")
        appRemote.authorizeAndPlayURI("") { [weak self] success in
            DebugLog.shared.log("authorizeAndPlayURI callback: success=\(success)", category: "Spotify")
            guard !success else { return }
            DispatchQueue.main.async {
                self?.connectionError = "Install Spotify to control playback here."
            }
        }
    }

    /// Resumes an existing session without bouncing to Spotify — safe to call on every foreground.
    /// Fails quietly when Spotify is suspended; the user can tap Connect to wake it.
    func reconnectIfPossible() {
        guard !appRemote.isConnected else { return }
        guard appRemote.connectionParameters.accessToken != nil else {
            DebugLog.shared.log("reconnectIfPossible() skipped — no access token.", category: "Spotify")
            return
        }
        DebugLog.shared.log("reconnectIfPossible() calling appRemote.connect().", category: "Spotify")
        appRemote.connect()
    }

    /// Explicit Disconnect — drops the socket and forgets the token so the next Connect
    /// authorizes again.
    func disconnect() {
        tearDownConnection(clearSession: true)
    }

    /// Background / inactive lifecycle — drops the socket but keeps the token for reconnect.
    func suspendConnection() {
        tearDownConnection(clearSession: false)
    }

    private func tearDownConnection(clearSession: Bool) {
        if clearSession {
            clearSavedSession()
        }

        guard appRemote.isConnected else {
            if clearSession {
                applyDisconnectedState(clearNowPlaying: true)
            }
            return
        }

        ignoreNextDisconnectError = true
        appRemote.disconnect()
    }

    func handleAuthCallback(_ url: URL) {
        let parameters = appRemote.authorizationParameters(from: url)
        // Keys only — a param value can be the access token, which must never end up in a log.
        DebugLog.shared.log(
            "Callback received, parameter keys: \(parameters?.keys.sorted() ?? [])",
            category: "Spotify"
        )

        if let token = parameters?[SPTAppRemoteAccessTokenKey] {
            DebugLog.shared.log("Auth succeeded, access token received (\(token.count) chars).", category: "Spotify")
            persistAccessToken(token)
            appRemote.connect()
        } else if let message = parameters?[SPTAppRemoteErrorDescriptionKey] {
            DebugLog.shared.log("Auth failed: \(message)", category: "Spotify")
            onMain {
                self.connectionError = message
            }
        } else {
            DebugLog.shared.log("Callback had neither an access token nor an error description.", category: "Spotify")
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

    func seek(to position: TimeInterval) {
        let clamped = min(max(position, 0), trackDuration)
        playbackPosition = clamped
        appRemote.playerAPI?.seek(toPosition: Int(clamped * 1000), callback: nil)
    }

    func toggleShuffle() {
        let newValue = !isShuffleEnabled
        isShuffleEnabled = newValue
        appRemote.playerAPI?.setShuffle(newValue, callback: nil)
    }

    func cycleRepeatMode() {
        let next: NowPlayingRepeatMode
        switch repeatMode {
        case .off: next = .all
        case .all: next = .one
        case .one: next = .off
        }
        repeatMode = next
        appRemote.playerAPI?.setRepeatMode(Self.spotifyRepeatMode(from: next), callback: nil)
    }

    private func persistAccessToken(_ token: String) {
        appRemote.connectionParameters.accessToken = token
        SpotifyAccessTokenStore.save(token)
    }

    private func clearSavedSession() {
        appRemote.connectionParameters.accessToken = nil
        SpotifyAccessTokenStore.clear()
        DebugLog.shared.log("Cleared saved Spotify session.", category: "Spotify")
    }

    private func applyDisconnectedState(clearNowPlaying: Bool) {
        isConnected = false
        stopPositionTicker()
        if clearNowPlaying {
            isPlaying = false
            trackTitle = nil
            artistName = nil
            artwork = nil
            playbackPosition = 0
            trackDuration = 0
            isShuffleEnabled = false
            repeatMode = .off
        }
    }

    private func apply(_ playerState: any SPTAppRemotePlayerState) {
        isPlaying = !playerState.isPaused
        trackTitle = playerState.track.name
        artistName = playerState.track.artist.name
        trackDuration = TimeInterval(playerState.track.duration) / 1000
        playbackPosition = TimeInterval(playerState.playbackPosition) / 1000
        isShuffleEnabled = playerState.playbackOptions.isShuffling
        repeatMode = Self.repeatMode(from: playerState.playbackOptions.repeatMode)

        if isPlaying {
            startPositionTicker()
        } else {
            stopPositionTicker()
        }

        appRemote.imageAPI?.fetchImage(
            forItem: playerState.track,
            with: CGSize(width: 80, height: 80)
        ) { [weak self] image, _ in
            self?.onMain {
                self?.artwork = image as? UIImage
            }
        }
    }

    private func startPositionTicker() {
        guard positionTicker == nil else { return }
        positionTicker = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.onMain {
                guard self.isPlaying, self.trackDuration > 0 else { return }
                self.playbackPosition = min(self.trackDuration, self.playbackPosition + 1)
            }
        }
    }

    private func stopPositionTicker() {
        positionTicker?.invalidate()
        positionTicker = nil
    }

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private static func repeatMode(from spotifyMode: SPTAppRemotePlaybackOptionsRepeatMode) -> NowPlayingRepeatMode {
        switch spotifyMode {
        case .off: .off
        case .track: .one
        case .context: .all
        @unknown default: .off
        }
    }

    private static func spotifyRepeatMode(from mode: NowPlayingRepeatMode) -> SPTAppRemotePlaybackOptionsRepeatMode {
        switch mode {
        case .off: .off
        case .one: .track
        case .all: .context
        }
    }
}

extension MediaPlayerManager: SPTAppRemoteDelegate {
    func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        DebugLog.shared.log("App Remote connection established.", category: "Spotify")
        onMain {
            self.isConnected = true
            self.connectionError = nil
        }

        appRemote.playerAPI?.delegate = self
        appRemote.playerAPI?.subscribe(toPlayerState: nil)
        appRemote.playerAPI?.getPlayerState { [weak self] state, _ in
            guard let playerState = state as? any SPTAppRemotePlayerState else { return }
            self?.onMain {
                self?.apply(playerState)
            }
        }
    }

    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        DebugLog.shared.log("App Remote connection failed: \(error?.localizedDescription ?? "nil")", category: "Spotify")
        onMain {
            self.isConnected = false
            // Keep the token — Spotify is often just suspended. User-initiated Connect wakes it.
            if self.hasSavedSession {
                self.connectionError = "Open Spotify, then tap Connect again."
            } else {
                self.connectionError = error?.localizedDescription
            }
        }
    }

    func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        DebugLog.shared.log("App Remote disconnected: \(error?.localizedDescription ?? "nil")", category: "Spotify")
        onMain {
            let ignoreError = self.ignoreNextDisconnectError
            self.ignoreNextDisconnectError = false
            self.applyDisconnectedState(clearNowPlaying: false)
            if !ignoreError {
                self.connectionError = error?.localizedDescription
            }
        }
    }
}

extension MediaPlayerManager: SPTAppRemotePlayerStateDelegate {
    func playerStateDidChange(_ playerState: any SPTAppRemotePlayerState) {
        onMain {
            self.apply(playerState)
        }
    }
}

extension MediaPlayerManager: NowPlayingProviding {}
