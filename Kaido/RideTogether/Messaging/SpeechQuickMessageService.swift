import Speech
import AVFoundation

enum SpeechQuickMessageAvailability: Equatable, Sendable {
    case available
    case permissionNotDetermined
    case permissionDenied
    case restricted
    case recognizerUnavailable
}

enum SpeechQuickMessageError: LocalizedError, Equatable {
    case permissionDenied
    case recognizerUnavailable
    case emptyTranscript
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return String(localized: "Microphone or speech access isn't available.")
        case .recognizerUnavailable:
            return String(localized: "Speech recognition isn't available right now.")
        case .emptyTranscript:
            return String(localized: "Didn't catch that — try again or use a quick reply.")
        case .recognitionFailed:
            return String(localized: "Couldn't transcribe that. Try again or use a quick reply.")
        }
    }
}

/// Press-and-hold dictation for quick messages. Never uploads or retains audio after
/// transcription — only the in-memory `liveTranscript` string exists, and the caller always
/// routes the final text through an explicit review (Send/Cancel) step before it's ever sent.
@MainActor
@Observable
final class SpeechQuickMessageService {
    private(set) var isRecording = false
    private(set) var liveTranscript = ""

    private let recognizer = SFSpeechRecognizer(locale: .current)
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var availability: SpeechQuickMessageAvailability {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            return .permissionNotDetermined
        case .denied:
            return .permissionDenied
        case .restricted:
            return .restricted
        case .authorized:
            return (recognizer?.isAvailable == true) ? .available : .recognizerUnavailable
        @unknown default:
            return .recognizerUnavailable
        }
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Starts live transcription. The caller is expected to have already configured the shared
    /// audio session via `RideAudioCoordinator.beginSpeechCapture()`.
    func startRecording() throws {
        guard availability == .available else {
            throw SpeechQuickMessageError.recognizerUnavailable
        }
        stopRecording()

        let engine = AVAudioEngine()
        let bufferRequest = SFSpeechAudioBufferRecognitionRequest()
        bufferRequest.shouldReportPartialResults = true

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            bufferRequest.append(buffer)
        }

        engine.prepare()
        try engine.start()

        audioEngine = engine
        request = bufferRequest
        liveTranscript = ""
        isRecording = true

        task = recognizer?.recognitionTask(with: bufferRequest) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.liveTranscript = result.bestTranscription.formattedString
                }
                if error != nil {
                    self.teardownEngine()
                }
            }
        }
    }

    /// Stops capture and returns the final transcript for review. Never sends anything itself —
    /// the caller always presents an explicit review step.
    @discardableResult
    func stopRecording() -> String {
        let transcript = liveTranscript
        teardownEngine()
        return transcript
    }

    private func teardownEngine() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        request?.endAudio()
        task?.cancel()
        audioEngine = nil
        request = nil
        task = nil
        isRecording = false
    }
}
