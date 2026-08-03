import AVFoundation

/// Coordinates `AVAudioSession` ownership between Ride Together's speech-to-text capture and
/// message readout so neither permanently overwrites whatever configuration was active before
/// (Mapbox's own turn-by-turn voice guidance, most likely).
///
/// Message readout uses `.duckOthers` rather than trying to detect Mapbox's exact
/// speaking-in-progress state (no such hook is exposed to this app) — it lowers other audio
/// instead of talking over it at full volume, and only one Ride Together utterance plays at a
/// time, with any others queued rather than overlapping.
@MainActor
final class RideAudioCoordinator: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = RideAudioCoordinator()

    private let session = AVAudioSession.sharedInstance()
    private let synthesizer = AVSpeechSynthesizer()
    private var savedCategory: AVAudioSession.Category?
    private var savedMode: AVAudioSession.Mode?
    private var savedOptions: AVAudioSession.CategoryOptions = []
    private var isSessionOverridden = false
    private var readoutQueue: [(sender: String, body: String)] = []

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Configures the shared session for microphone capture, remembering whatever was active
    /// beforehand so `endSpeechCapture()` can restore it exactly.
    func beginSpeechCapture() throws {
        if !isSessionOverridden {
            savedCategory = session.category
            savedMode = session.mode
            savedOptions = session.categoryOptions
            isSessionOverridden = true
        }
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true, options: [])
    }

    func endSpeechCapture() {
        guard isSessionOverridden, let savedCategory else { return }
        try? session.setCategory(savedCategory, mode: savedMode ?? .default, options: savedOptions)
        isSessionOverridden = false
        self.savedCategory = nil
        savedMode = nil
        savedOptions = []
    }

    func speakIncomingMessageIfEnabled(sender: String, body: String) {
        guard GroupRideMessagingPreferences.readMessagesAloud else { return }
        readoutQueue.append((sender, body))
        drainQueueIfIdle()
    }

    private func drainQueueIfIdle() {
        guard !synthesizer.isSpeaking, !readoutQueue.isEmpty else { return }
        let next = readoutQueue.removeFirst()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .mixWithOthers])
        try? session.setActive(true, options: [])
        let utterance = AVSpeechUtterance(string: "\(next.sender) says \(next.body)")
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.drainQueueIfIdle()
        }
    }
}
