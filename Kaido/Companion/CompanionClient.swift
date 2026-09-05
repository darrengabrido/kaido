import Foundation

enum CompanionClientError: LocalizedError, Equatable {
    case httpStatus(Int, message: String?)
    case emptyResponse
    case refused
    case notJSON

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code, let message):
            if let message, !message.isEmpty { return message }
            switch code {
            case 401, 403: return "The key was rejected. Check it and try again."
            case 404: return "That model wasn't found. Check the model ID."
            case 429: return "Rate limited. Try again in a moment."
            default: return "The provider returned an error (\(code))."
            }
        case .emptyResponse:
            return "The provider returned an empty reply."
        case .refused:
            return "The model declined to answer this request."
        case .notJSON:
            return "The model didn't return the JSON Kaido asked for."
        }
    }
}

/// One small HTTP client that speaks to every supported provider's chat endpoint. Every call
/// asks for a JSON reply, because everything the companion does today is "pick from this list
/// and explain why" and JSON is the one format all four providers can be told to return.
///
/// Request building and response parsing are pure static functions so they can be unit-tested
/// without a network.
struct CompanionClient: Sendable {
    var session: URLSession = .shared

    /// Sends `system` + `user` and returns the model's text reply, which should be JSON.
    func complete(
        system: String,
        user: String,
        configuration: CompanionConfiguration,
        temperature: Double = 0.7
    ) async throws -> String {
        let request = try Self.request(
            system: system,
            user: user,
            configuration: configuration,
            temperature: temperature
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CompanionClientError.emptyResponse
        }
        guard http.statusCode == 200 else {
            throw CompanionClientError.httpStatus(http.statusCode, message: Self.errorMessage(from: data))
        }
        return try Self.extractText(from: data, provider: configuration.provider)
    }

    // MARK: - Requests

    static func request(
        system: String,
        user: String,
        configuration: CompanionConfiguration,
        temperature: Double
    ) throws -> URLRequest {
        var request: URLRequest
        let body: [String: Any]

        switch configuration.provider {
        case .off:
            throw CompanionClientError.emptyResponse

        case .openAI, .grok, .ollama:
            let endpoint: String
            switch configuration.provider {
            case .openAI:
                endpoint = "https://api.openai.com/v1/chat/completions"
            case .grok:
                endpoint = "https://api.x.ai/v1/chat/completions"
            case .ollama:
                let rawBase = configuration.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines)
                let base = (rawBase?.isEmpty == false ? rawBase! : "http://localhost:11434")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                endpoint = "\(base)/v1/chat/completions"
            default:
                endpoint = ""
            }
            guard let url = URL(string: endpoint) else {
                throw CompanionClientError.emptyResponse
            }
            request = URLRequest(url: url)
            if !configuration.apiKey.isEmpty {
                request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
            }
            body = [
                "model": configuration.model,
                "temperature": temperature,
                "response_format": ["type": "json_object"],
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": user]
                ]
            ]

        case .anthropic:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            // Thinking is left at its default (adaptive on current models). The reply is a
            // short JSON object, so a modest max_tokens keeps the round trip quick on a bike.
            body = [
                "model": configuration.model,
                "max_tokens": 1024,
                "system": system + "\nReply with a single JSON object and nothing else.",
                "messages": [
                    ["role": "user", "content": user]
                ]
            ]

        case .gemini:
            let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(configuration.model):generateContent"
            request = URLRequest(url: URL(string: endpoint)!)
            request.setValue(configuration.apiKey, forHTTPHeaderField: "x-goog-api-key")
            body = [
                "system_instruction": ["parts": [["text": system]]],
                "contents": [
                    ["role": "user", "parts": [["text": user]]]
                ],
                "generationConfig": [
                    "temperature": temperature,
                    "responseMimeType": "application/json"
                ]
            ]
        }

        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Responses

    static func extractText(from data: Data, provider: AIProvider) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CompanionClientError.emptyResponse
        }

        let text: String?
        switch provider {
        case .off:
            text = nil

        case .openAI, .grok, .ollama:
            let choices = json["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            text = message?["content"] as? String

        case .anthropic:
            if json["stop_reason"] as? String == "refusal" {
                throw CompanionClientError.refused
            }
            let blocks = json["content"] as? [[String: Any]] ?? []
            let parts = blocks.compactMap { block -> String? in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }
            text = parts.isEmpty ? nil : parts.joined()

        case .gemini:
            let candidates = json["candidates"] as? [[String: Any]]
            let content = candidates?.first?["content"] as? [String: Any]
            let parts = content?["parts"] as? [[String: Any]] ?? []
            let joined = parts.compactMap { $0["text"] as? String }.joined()
            text = joined.isEmpty ? nil : joined
        }

        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CompanionClientError.emptyResponse
        }
        return text
    }

    /// The provider's own error message, when the body carries one. All four wrap it as
    /// `{"error": {"message": "..."}}`.
    static func errorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }

    /// Models sometimes wrap JSON in a Markdown code fence even when asked not to. Strip it.
    static func jsonData(from text: String) -> Data? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            trimmed = trimmed
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") else {
            return nil
        }
        return Data(trimmed[start...end].utf8)
    }
}
