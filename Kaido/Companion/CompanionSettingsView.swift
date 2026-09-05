import SwiftUI

/// Bring-your-own-key settings for the companion. Reached from the Settings tab.
struct CompanionSettingsView: View {
    private let companion = Companion.shared

    @State private var keyDraft = ""
    @State private var modelDraft = ""
    @State private var endpointDraft = ""
    @State private var testState: TestState = .idle

    private enum TestState: Equatable {
        case idle
        case running
        case passed
        case failed(String)
    }

    private var settings: CompanionSettingsStore { companion.settings }
    private var provider: AIProvider { settings.provider }

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: Binding(
                    get: { settings.provider },
                    set: { newValue in
                        settings.setProvider(newValue)
                        loadDrafts()
                        testState = .idle
                    }
                )) {
                    ForEach(AIProvider.allCases) { candidate in
                        Label(candidate.title, systemImage: candidate.systemImage)
                            .tag(candidate)
                    }
                }
            } footer: {
                Text(settings.statusDescription)
            }

            if provider != .off {
                if provider.requiresBaseURL {
                    endpointSection
                }
                keySection
                modelSection
                testSection
            }
        }
        .navigationTitle("Companion")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadDrafts)
    }

    // MARK: - Sections

    private var endpointSection: some View {
        Section {
            TextField(provider.defaultBaseURL, text: $endpointDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .onSubmit(saveEndpoint)

            HStack {
                Button("Save endpoint", action: saveEndpoint)
                    .disabled(endpointDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .tint(.kaidoViolet)
                Spacer()
                if settings.baseURL(for: provider) != provider.defaultBaseURL {
                    Button("Reset default", role: .destructive) {
                        settings.setBaseURL("", for: provider)
                        endpointDraft = provider.defaultBaseURL
                        testState = .idle
                    }
                }
            }
        } header: {
            Text("\(provider.title) Endpoint")
        } footer: {
            Text("Local server address. Defaults to \(provider.defaultBaseURL) if left blank.")
        }
    }

    private var keySection: some View {
        Section {
            SecureField(provider.keyPrefixHint, text: $keyDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(saveKey)

            HStack {
                Button("Save key", action: saveKey)
                    .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .tint(.kaidoViolet)
                Spacer()
                if settings.hasAPIKey(for: provider) {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.statusGood)
                    Button("Remove", role: .destructive, action: removeKey)
                }
            }
        } header: {
            Text("\(provider.title) API key")
        } footer: {
            Text("\(provider.keyHint) Stored in this phone's Keychain and sent only to \(provider.title).")
        }
    }

    private var modelSection: some View {
        Section {
            Picker("Model", selection: Binding(
                get: { settings.model(for: provider) },
                set: { newValue in
                    settings.setModel(newValue, for: provider)
                    modelDraft = ""
                    testState = .idle
                }
            )) {
                ForEach(modelChoices, id: \.self) { model in
                    Text(model).tag(model)
                }
            }

            TextField("Or type a model ID", text: $modelDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(saveCustomModel)
        } header: {
            Text("Model")
        } footer: {
            Text("The list is a starting point. Any model ID your provider accepts works.")
        }
    }

    private var testSection: some View {
        Section {
            Button {
                runTest()
            } label: {
                HStack {
                    Text("Test connection")
                    Spacer()
                    switch testState {
                    case .idle:
                        EmptyView()
                    case .running:
                        ProgressView()
                    case .passed:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.statusGood)
                    case .failed:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.statusCritical)
                    }
                }
            }
            .disabled(testState == .running || settings.activeConfiguration == nil)

            if case .failed(let message) = testState {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color.statusCritical)
            } else if testState == .passed {
                Text("\(provider.title) answered with \(settings.model(for: provider)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("Sends one tiny request so you know the key and model work before you're on the bike.")
        }
    }

    // MARK: - Helpers

    /// Suggested models plus whatever is currently saved, so a custom ID shows as selected.
    private var modelChoices: [String] {
        var choices = provider.suggestedModels
        let current = settings.model(for: provider)
        if !current.isEmpty, !choices.contains(current) {
            choices.insert(current, at: 0)
        }
        return choices
    }

    private func loadDrafts() {
        keyDraft = ""
        modelDraft = ""
        endpointDraft = settings.baseURL(for: provider)
    }

    private func saveEndpoint() {
        settings.setBaseURL(endpointDraft, for: provider)
        testState = .idle
    }

    private func saveKey() {
        settings.setAPIKey(keyDraft, for: provider)
        keyDraft = ""
        testState = .idle
    }

    private func removeKey() {
        settings.setAPIKey("", for: provider)
        keyDraft = ""
        testState = .idle
    }

    private func saveCustomModel() {
        let trimmed = modelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        settings.setModel(trimmed, for: provider)
        modelDraft = ""
        testState = .idle
    }

    private func runTest() {
        guard let configuration = settings.activeConfiguration else {
            let message = provider.requiresAPIKey ? "Save a key first." : "Configure endpoint first."
            testState = .failed(message)
            return
        }
        testState = .running
        Task {
            do {
                _ = try await companion.testConnection(configuration)
                testState = .passed
            } catch {
                testState = .failed(error.localizedDescription)
            }
        }
    }
}
