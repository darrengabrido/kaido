import Foundation

/// The AI backends the companion can talk to. `off` means the rider has chosen built-in
/// suggestions only; every other case needs an API key the rider pastes in on their own phone.
enum AIProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case off
    case openAI
    case anthropic
    case gemini
    case grok

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .gemini: "Google Gemini"
        case .grok: "xAI Grok"
        }
    }

    var systemImage: String {
        switch self {
        case .off: "binoculars"
        case .openAI, .anthropic, .gemini, .grok: "sparkles"
        }
    }

    /// Short, hand-curated list. The settings screen also accepts any model ID typed in, so
    /// this only needs to cover the sensible defaults, not track every release.
    var suggestedModels: [String] {
        switch self {
        case .off: []
        case .openAI: ["gpt-4o-mini", "gpt-4.1-mini", "gpt-4.1", "gpt-5-mini"]
        case .anthropic: ["claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5"]
        case .gemini: ["gemini-2.5-flash", "gemini-2.5-pro"]
        case .grok: ["grok-4", "grok-3-mini"]
        }
    }

    var defaultModel: String {
        suggestedModels.first ?? ""
    }

    /// Where to get a key, shown under the key field. Kept short: it's read on a phone.
    var keyHint: String {
        switch self {
        case .off:
            "Free Ride picks nearby stops with built-in rules. No key, nothing leaves the phone."
        case .openAI:
            "Create a key at platform.openai.com/api-keys."
        case .anthropic:
            "Create a key at console.anthropic.com."
        case .gemini:
            "Create a key at aistudio.google.com/apikey."
        case .grok:
            "Create a key at console.x.ai."
        }
    }

    var keyPrefixHint: String {
        switch self {
        case .off: ""
        case .openAI: "sk-…"
        case .anthropic: "sk-ant-…"
        case .gemini: "AIza…"
        case .grok: "xai-…"
        }
    }
}
