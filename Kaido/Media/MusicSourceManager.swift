import Foundation

enum MusicSource: String, CaseIterable, Identifiable {
    case spotify
    case appleMusic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spotify: "Spotify"
        case .appleMusic: "Apple Music"
        }
    }

    var systemImage: String {
        switch self {
        case .spotify: "music.note"
        case .appleMusic: "applelogo"
        }
    }
}

/// Tracks which music source drives the Now Playing bar. A plain singleton (not
/// `.environment`-injected) so it's reachable from `NavigationSessionView`'s
/// `UIViewControllerRepresentable`, which has no SwiftUI environment access at
/// `makeUIViewController` time.
@Observable
@MainActor
final class MusicSourceManager {
    static let shared = MusicSourceManager()

    private static let defaultsKey = "kaido.musicSource"

    var selectedSource: MusicSource {
        didSet {
            guard oldValue != selectedSource else { return }
            UserDefaults.standard.set(selectedSource.rawValue, forKey: Self.defaultsKey)
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey)
        selectedSource = raw.flatMap(MusicSource.init(rawValue:)) ?? .spotify
    }

    var activeProvider: any NowPlayingProviding {
        switch selectedSource {
        case .spotify: MediaPlayerManager.shared
        case .appleMusic: AppleMusicManager.shared
        }
    }
}
