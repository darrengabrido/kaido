import Foundation
import Observation

/// Everything the companion needs to reach a model: which provider, which model, which key.
struct CompanionConfiguration: Equatable, Sendable {
    let provider: AIProvider
    let model: String
    let apiKey: String
}

/// Which key the companion is actually running on. Surfaced in the UI so the rider is never
/// guessing whether their pasted key is the one being used.
enum CompanionConfigurationSource: Equatable, Sendable {
    /// The rider's own key, entered on this phone.
    case riderKey(AIProvider)
    /// The OpenAI key compiled into this build (local Xcode builds only; TestFlight ships none).
    case bundledKey
    /// No usable key. Free Ride falls back to built-in rules.
    case builtIn
}

/// Persists the rider's AI provider choice, per-provider model, and per-provider API key.
///
/// Provider and model go in `UserDefaults`. Keys go in the Keychain and never leave the device
/// except in a request to the provider they belong to. Nothing here syncs via CloudKit on
/// purpose: a pasted key is this phone's business.
@Observable
@MainActor
final class CompanionSettingsStore {
    static let shared = CompanionSettingsStore()

    private static let providerKey = "kaido.companion.provider"
    private static func modelKey(for provider: AIProvider) -> String {
        "kaido.companion.model.\(provider.rawValue)"
    }

    private let defaults: UserDefaults
    private let secrets: any SecretStore
    private let bundledOpenAIKey: String?

    private(set) var provider: AIProvider
    /// Providers that currently have a key stored. Mirrored from the secret store so views can
    /// observe it; the store itself is the source of truth.
    private(set) var providersWithKeys: Set<AIProvider>
    private var models: [AIProvider: String]

    init(
        defaults: UserDefaults = .standard,
        secrets: any SecretStore = KeychainSecretStore(service: "com.oaktreehouse.kaido.companion"),
        bundledOpenAIKey: String? = CompanionSettingsStore.bundledOpenAIKeyFromInfoPlist()
    ) {
        self.defaults = defaults
        self.secrets = secrets
        self.bundledOpenAIKey = bundledOpenAIKey

        let storedProvider = defaults.string(forKey: Self.providerKey).flatMap(AIProvider.init(rawValue:))
        // Default to OpenAI so a build with a bundled key keeps behaving exactly as before this
        // screen existed. `.off` is only ever an explicit choice.
        provider = storedProvider ?? .openAI

        var models: [AIProvider: String] = [:]
        var withKeys = Set<AIProvider>()
        for candidate in AIProvider.allCases where candidate != .off {
            if let model = defaults.string(forKey: Self.modelKey(for: candidate)), !model.isEmpty {
                models[candidate] = model
            }
            if let key = secrets.read(account: candidate.rawValue), !key.isEmpty {
                withKeys.insert(candidate)
            }
        }
        self.models = models
        self.providersWithKeys = withKeys
    }

    // MARK: - Provider

    func setProvider(_ newValue: AIProvider) {
        provider = newValue
        defaults.set(newValue.rawValue, forKey: Self.providerKey)
    }

    // MARK: - Model

    func model(for provider: AIProvider) -> String {
        models[provider] ?? provider.defaultModel
    }

    func setModel(_ model: String, for provider: AIProvider) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            models[provider] = nil
            defaults.removeObject(forKey: Self.modelKey(for: provider))
        } else {
            models[provider] = trimmed
            defaults.set(trimmed, forKey: Self.modelKey(for: provider))
        }
    }

    // MARK: - API keys

    func hasAPIKey(for provider: AIProvider) -> Bool {
        providersWithKeys.contains(provider)
    }

    func apiKey(for provider: AIProvider) -> String? {
        guard provider != .off else { return nil }
        let key = secrets.read(account: provider.rawValue)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (key?.isEmpty == false) ? key : nil
    }

    /// Empty or whitespace removes the key.
    func setAPIKey(_ key: String, for provider: AIProvider) {
        guard provider != .off else { return }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            secrets.delete(account: provider.rawValue)
            providersWithKeys.remove(provider)
        } else {
            secrets.write(trimmed, account: provider.rawValue)
            providersWithKeys.insert(provider)
        }
    }

    // MARK: - Resolution

    /// Rider's key for the chosen provider first, the bundled OpenAI key second (only when the
    /// chosen provider is OpenAI), built-in rules last. `.off` always means built-in.
    var configurationSource: CompanionConfigurationSource {
        guard provider != .off else { return .builtIn }
        if hasAPIKey(for: provider) { return .riderKey(provider) }
        if provider == .openAI, let bundled = bundledOpenAIKey, !bundled.isEmpty { return .bundledKey }
        return .builtIn
    }

    var activeConfiguration: CompanionConfiguration? {
        switch configurationSource {
        case .riderKey(let provider):
            guard let key = apiKey(for: provider) else { return nil }
            return CompanionConfiguration(provider: provider, model: model(for: provider), apiKey: key)
        case .bundledKey:
            guard let bundled = bundledOpenAIKey else { return nil }
            return CompanionConfiguration(provider: .openAI, model: model(for: .openAI), apiKey: bundled)
        case .builtIn:
            return nil
        }
    }

    /// One line for the Profile card and the settings screen.
    var statusDescription: String {
        switch configurationSource {
        case .riderKey(let provider):
            "Free Ride is using \(provider.title) · \(model(for: provider))"
        case .bundledKey:
            "Free Ride is using OpenAI · \(model(for: .openAI)) (key from this build)"
        case .builtIn:
            provider == .off
                ? "Free Ride is using built-in suggestions."
                : "No \(provider.title) key yet. Free Ride is using built-in suggestions."
        }
    }

    // MARK: - Bundle

    nonisolated static func bundledOpenAIKeyFromInfoPlist(bundle: Bundle = .main) -> String? {
        guard let key = bundle.object(forInfoDictionaryKey: "OpenAIAPIKey") as? String else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        // Secrets.xcconfig.example ships a placeholder; treat it as absent.
        guard !trimmed.isEmpty, !trimmed.contains("your_openai"), !trimmed.hasSuffix("_here") else { return nil }
        return trimmed
    }
}
