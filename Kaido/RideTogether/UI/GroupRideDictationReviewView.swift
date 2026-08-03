import SwiftUI

/// Large, simple review state shown after releasing the dictation mic. A transcript is never
/// sent automatically — the rider always sees this and explicitly chooses Send or Cancel.
struct GroupRideDictationReviewView: View {
    let transcript: String
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Review Message")
                .font(.title2.bold())

            ScrollView {
                Text(transcript)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            HStack(spacing: 16) {
                Button {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.bordered)

                Button {
                    onSend()
                } label: {
                    Text("Send")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.kaidoViolet)
            }
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
