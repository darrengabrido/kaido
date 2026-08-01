import SwiftUI

/// Configures custom quick replies outside the high-distraction portion of navigation — reached
/// from the Profile tab, never editable mid-ride.
struct GroupRideCustomReplySettingsView: View {
    @State private var replies = GroupRideCustomReplyStore.replies
    @State private var newReply = ""
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(Array(replies.enumerated()), id: \.offset) { _, reply in
                    Text(reply)
                }
                .onDelete(perform: delete)
            } header: {
                Text("Custom Quick Replies")
            } footer: {
                Text(
                    "Up to \(GroupRideConfig.maxCustomQuickReplies) replies, " +
                    "\(GroupRideConfig.maxCustomQuickReplyLength) characters each. " +
                    "Shown as large buttons during Ride Together."
                )
            }

            if replies.count < GroupRideConfig.maxCustomQuickReplies {
                Section {
                    HStack {
                        TextField("New quick reply", text: $newReply)
                        Button("Add") { addReply() }
                            .disabled(newReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Color.statusCritical)
                    }
                }
            }
        }
        .navigationTitle("Quick Replies")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addReply() {
        do {
            replies = try GroupRideCustomReplyStore.add(newReply)
            newReply = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            GroupRideCustomReplyStore.remove(at: index)
        }
        replies = GroupRideCustomReplyStore.replies
    }
}
