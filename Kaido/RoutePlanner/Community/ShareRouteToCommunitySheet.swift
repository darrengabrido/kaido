import SwiftUI

/// Presented from `RouteDetailView`'s toolbar to publish one of the rider's own saved routes to
/// the Routes tab's "Community" section. `onPublish` is expected to call
/// `CommunityRouteService.publish` and record the resulting id on the local `Route` — this view
/// only owns the form and its own submission state.
struct ShareRouteToCommunitySheet: View {
    let route: Route
    let onPublish: (String, String?) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var description = ""
    @State private var isPublishing = false
    @State private var errorMessage: String?

    init(route: Route, onPublish: @escaping (String, String?) async throws -> Void) {
        self.route = route
        self.onPublish = onPublish
        _name = State(initialValue: route.name)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Route name") {
                    TextField("Route name", text: $name)
                        .disabled(isPublishing)
                }

                Section("Description (optional)") {
                    TextField(
                        "What makes this route worth riding?",
                        text: $description,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                    .disabled(isPublishing)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Color.statusCritical)
                }
            }
            .navigationTitle("Share to Community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isPublishing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await publish() }
                    } label: {
                        if isPublishing {
                            ProgressView()
                        } else {
                            Text("Publish")
                        }
                    }
                    .tint(.kaidoViolet)
                    .disabled(isPublishing || trimmedName.isEmpty)
                }
            }
        }
        .interactiveDismissDisabled(isPublishing)
    }

    private func publish() async {
        isPublishing = true
        errorMessage = nil
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await onPublish(trimmedName, trimmedDescription.isEmpty ? nil : trimmedDescription)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isPublishing = false
    }
}
