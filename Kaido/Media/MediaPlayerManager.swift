import Foundation
import SpotifyiOS
import UIKit

/// Mirrors and drives the Spotify app's playback so the map screen can show a Now Playing bar
/// without owning any audio itself. Connection is via Spotify's App Remote, which requires the
/// Spotify app to be installed and a Premium account to accept transport commands.
///
/// App Remote's implicit `authorizeAndPlayURI` grant hands back a short-lived access token and
/// no refresh token, so there is no way to renew silently from the device — a genuinely expired
/// token always needs one more bounce through the Spotify app. What this class *can* do is stop
/// treating every dropped socket as an expired token: App Remote also disconnects whenever iOS
/// suspends the Spotify app (paused playback, memory pressure), and in that case the token is
/// still perfectly good and a plain `connect()` brings the session back without any bounce.
@Observable
final class MediaPlayerManager: NSObject {
    /// Shared because the OAuth redirect arrives app-wide via `onOpenURL`, which has no way to
    /// reach a view-owned instance.
    static let shared = MediaPlayerManager()

    private static let redirectURL = URL(string: "kaido://spotify-callback")!

    /// How long to wait after an unexpected disconnect before quietly trying to reconnect.
    private static let reconnectDelay: TimeInterval = 2

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

    /// Set when a `connect()` using the stored token was refused. The token might be expired,
    /// or Spotify might simply have been asleep — App Remote reports both the same way — so the
    /// token is kept, but the next *user-initiated* connect goes through `authorizeAndPlayURI`
    /// (which wakes Spotify and re-issues a token) instead of retrying `connect()` forever.
    @ObservationIgnored
    private var storedTokenWasRefused = false

    /// True while we asked App Remote to disconnect ourselves (app going to background), so the
    /// resulting delegate callback isn't mistaken for a dropped session.
    @ObservationIgnored
    private var isDisconnectingIntentionally = false

    @ObservationIgnored
    private var pendingReconnect: DispatchWorkItem?

    @ObservationIgnored
    private lazy var appRemote: SPTAppRemote = {
        let configuration = SPTConfiguration(clientID: Self.clientID, redirectURL: Self.redirectURL)
        let remote = SPTAppRemote(configuration: configuration, logLevel: .debug)
        remote.delegate = self
        // Restores a token saved before the app was last killed, so a relaunch doesn't force
        // the user back through Spotify's OAuth screen.
        remote.connectionParameters.accessToken = SpotifyTokenStore.loadValidToken()
        return remote
    }()

    private override init() {
        super.init()
    }

    /// User-initiated connect. Reuses the stored token when we have one that hasn't been
    /// refused; otherwise bounces out to the Spotify app to authorize, and control returns via
    /// `handleAuthCallback`.
    func connect() {
        guard !appRemote.isConnected else { return }
        pendingReconnect?.cancel()
        connectionError = nil

        if appRemote.connectionParameters.accessToken != nil, !storedTokenWasRefused {
            DebugLog.shared.log("connect() reusing existing access token.", category: "Spotify")
            appRemote.connect()
            return
        }

        DebugLog.shared.log(
            storedTokenWasRefused
                ? "connect() stored token was refused earlier; re-authorizing."
                : "connect() starting authorizeAndPlayURI.",
            category: "Spotify"
        )
        appRemote.authorizeAndPlayURI("") { [weak self] success in
            DebugLog.shared.log("authorizeAndPlayURI callback: success=\(success)", category: "Spotify")
            guard !success else { return }
            DispatchQueue.main.async {
                self?.connectionError = "Install Spotify to control playback here."
            }
        }
    }

    /// Resumes an existing session without bouncing to Spotify — safe to call on every
    /// foreground. Silent by design: if it fails, the media bar just shows "Not Connected" and
    /// the user's next tap on Connect takes the re-authorize path.
    func reconnectIfPossible() {
        guard !appRemote.isConnected, appRemote.connectionParameters.accessToken != nil else { return }
        pendingReconnect?.cancel()
        DebugLog.shared.log("reconnectIfPossible() trying stored token.", category: "Spotify")
        appRemote.connect()
    }

    func disconnect() {
        pendingReconnect?.cancel()
        guard appRemote.isConnected else { return }
        isDisconnectingIntentionally = true
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
            appRemote.connectionParameters.accessToken = token
            SpotifyTokenStore.save(token: token)
            storedTokenWasRefused = false
            appRemote.connect()
        } else if let message = parameters?[SPTAppRemoteErrorDescriptionKey] {
            DebugLog.shared.log("Auth failed: \(message)", category: "Spotify")
            connectionError = message
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

    /// One quiet retry after an unexpected drop. Spotify usually just got suspended; if it's
    /// still reachable this restores the session with no UI at all, and if not, the failure
    /// path leaves things in the same "Not Connected" state the user would have seen anyway.
    private func scheduleReconnect() {
        pendingReconnect?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.appRemote.isConnected,
                  self.appRemote.connectionParameters.accessToken != nil,
                  UIApplication.shared.applicationState == .active
            else { return }
            DebugLog.shared.log("Retrying connection after unexpected disconnect.", category: "Spotify")
            self.appRemote.connect()
        }
        pendingReconnect = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reconnectDelay, execute: work)
    }
}

extension MediaPlayerManager: SPTAppRemoteDelegate {
    func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        DebugLog.shared.log("App Remote connection established.", category: "Spotify")
        pendingReconnect?.cancel()
        isConnected = true
        connectionError = nil
        storedTokenWasRefused = false

        appRemote.playerAPI?.delegate = self
        appRemote.playerAPI?.subscribe(toPlayerState: nil)
        appRemote.playerAPI?.getPlayerState { [weak self] state, _ in
            guard let playerState = state as? any SPTAppRemotePlayerState else { return }
            self?.apply(playerState)
        }
    }

    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        DebugLog.shared.log("App Remote connection failed: \(error?.localizedDescription ?? "nil")", category: "Spotify")
        isConnected = false
        connectionError = error?.localizedDescription
        // Previously this threw the stored token away on any failure, which turned every
        // "Spotify is asleep" into a forced OAuth bounce. Keep the token; just remember it was
        // refused so the next user-initiated connect re-authorizes instead of retrying it.
        if error != nil, appRemote.connectionParameters.accessToken != nil {
            storedTokenWasRefused = true
        }
    }

    func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        DebugLog.shared.log(
            "App Remote disconnected: \(error?.localizedDescription ?? "nil")"
                + (isDisconnectingIntentionally ? " (intentional)" : ""),
            category: "Spotify"
        )
        isConnected = false

        let wasIntentional = isDisconnectingIntentionally
        isDisconnectingIntentionally = false
        guard !wasIntentional, error != nil else { return }

        // An unexpected drop mid-use: almost always Spotify being suspended by iOS rather than
        // the token dying, so try once to pick the session back up before showing anything.
        scheduleReconnect()
    }
}

extension MediaPlayerManager: SPTAppRemotePlayerStateDelegate {
    func playerStateDidChange(_ playerState: any SPTAppRemotePlayerState) {
        apply(playerState)
    }
}

extension MediaPlayerManager: NowPlayingProviding {}
