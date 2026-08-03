import SwiftUI

/// Quick-message composer: large safety-oriented presets, locally configured custom replies, and
/// press-and-hold dictation. Deliberately has no freeform text field — no keyboard-based
/// composing while the rider is moving. Custom replies are configured elsewhere
/// (`GroupRideCustomReplySettingsView`, outside active navigation).
struct GroupRideQuickMessageSheet: View {
    private struct DictationReview: Identifiable {
        let id = UUID()
        var text: String
    }

    @Environment(GroupRideSessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var speechService = SpeechQuickMessageService()
    @State private var customReplies = GroupRideCustomReplyStore.replies
    @State private var pendingReview: DictationReview?
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Color.statusCritical)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    presetGrid

                    if !customReplies.isEmpty {
                        customReplyGrid
                    }

                    dictationControl
                }
                .padding(20)
            }
            .navigationTitle("Quick Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $pendingReview) { review in
                GroupRideDictationReviewView(
                    transcript: review.text,
                    onSend: {
                        send(kind: .dictated, body: review.text, presetKey: nil)
                        pendingReview = nil
                    },
                    onCancel: { pendingReview = nil }
                )
            }
        }
    }

    private var presetGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(GroupRideQuickPreset.allCases) { preset in
                Button {
                    send(kind: .preset, body: preset.body, presetKey: preset.rawValue)
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: preset.systemImage)
                            .font(.system(size: 22, weight: .semibold))
                        Text(preset.body)
                            .font(.subheadline.weight(.medium))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Color.kaidoInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.kaidoInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(isSending)
                .accessibilityLabel(preset.body)
            }
        }
    }

    private var customReplyGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR QUICK REPLIES")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.kaidoDim)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(customReplies.enumerated()), id: \.offset) { _, reply in
                    Button {
                        send(kind: .preset, body: reply, presetKey: nil)
                    } label: {
                        Text(reply)
                            .font(.subheadline.weight(.medium))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.kaidoInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.kaidoViolet.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending)
                }
            }
        }
    }

    @ViewBuilder
    private var dictationControl: some View {
        VStack(spacing: 10) {
            switch speechService.availability {
            case .available:
                micButton
                if speechService.isRecording {
                    Text(speechService.liveTranscript.isEmpty ? "Listening…" : speechService.liveTranscript)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            case .permissionNotDetermined:
                Button("Enable Dictation") {
                    Task {
                        let granted = await speechService.requestPermission()
                        if !granted {
                            errorMessage = SpeechQuickMessageError.permissionDenied.localizedDescription
                        }
                    }
                }
                .buttonStyle(.bordered)
            case .permissionDenied, .restricted:
                Text("Dictation isn't available. Use a quick reply above instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .recognizerUnavailable:
                Text("Speech recognition isn't available right now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var micButton: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 72, height: 72)
            .background(speechService.isRecording ? Color.statusCritical : Color.kaidoViolet, in: Circle())
            .scaleEffect(speechService.isRecording ? 1.08 : 1)
            .animation(.spring(response: 0.25), value: speechService.isRecording)
            .accessibilityLabel("Hold to dictate a message")
            .accessibilityHint("Press and hold, speak your message, then release to review it")
            .onLongPressGesture(minimumDuration: 0, pressing: { isPressing in
                if isPressing {
                    beginRecording()
                } else {
                    endRecording()
                }
            }, perform: {})
    }

    private func beginRecording() {
        guard !speechService.isRecording else { return }
        errorMessage = nil
        do {
            try RideAudioCoordinator.shared.beginSpeechCapture()
            try speechService.startRecording()
        } catch {
            RideAudioCoordinator.shared.endSpeechCapture()
            errorMessage = SpeechQuickMessageError.recognizerUnavailable.localizedDescription
        }
    }

    private func endRecording() {
        guard speechService.isRecording else { return }
        let transcript = speechService.stopRecording()
        RideAudioCoordinator.shared.endSpeechCapture()

        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = SpeechQuickMessageError.emptyTranscript.localizedDescription
            return
        }
        pendingReview = DictationReview(text: String(trimmed.prefix(GroupRideConfig.maxDictatedMessageLength)))
    }

    private func send(kind: GroupRideMessageKind, body: String, presetKey: String?) {
        isSending = true
        errorMessage = nil
        Task {
            do {
                try await sessionStore.sendMessage(kind: kind, body: body, presetKey: presetKey)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }
}
