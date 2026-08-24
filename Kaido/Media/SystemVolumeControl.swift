import MediaPlayer
import UIKit

/// Nudges the system output volume. Spotify's App Remote and `MPMusicPlayerController` both
/// play through the shared iOS audio session — neither SDK exposes a volume API of its own —
/// so this drives the slider embedded in an off-screen `MPVolumeView`, the standard (if
/// unofficial) way to adjust volume in-app since `AVAudioSession.outputVolume` is read-only.
@MainActor
enum SystemVolumeControl {
    /// One step, matching the ~1/16 increment of a single hardware volume button press.
    static let step: Float = 1.0 / 16.0

    private static let volumeView: MPVolumeView = {
        let view = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        view.alpha = 0.001
        view.isUserInteractionEnabled = false
        return view
    }()

    private static var isInstalled = false

    /// Call ahead of time (e.g. at launch) so the hidden slider exists before the first nudge —
    /// `UISlider` subviews of `MPVolumeView` aren't populated until it's actually in a window.
    static func warmUp() {
        install()
    }

    static func adjust(by delta: Float) {
        install()
        guard let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.value = min(1, max(0, slider.value + delta))
        slider.sendActions(for: .valueChanged)
    }

    private static func install() {
        guard !isInstalled else { return }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.windows.first(where: \.isKeyWindow) })
            .first
        else { return }
        window.addSubview(volumeView)
        isInstalled = true
    }
}
