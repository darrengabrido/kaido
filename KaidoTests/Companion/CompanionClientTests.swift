@testable import Kaido
import XCTest

final class CompanionClientTests: XCTestCase {
    private func body(of request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func configuration(_ provider: AIProvider, model: String = "m", key: String = "k") -> CompanionConfiguration {
        CompanionConfiguration(provider: provider, model: model, apiKey: key)
    }

    // MARK: - Requests

    func testOpenAIRequestShape() throws {
        let request = try CompanionClient.request(
            system: "sys", user: "usr", configuration: configuration(.openAI, model: "gpt-4o-mini", key: "sk-1"), temperature: 0.5
        )
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-1")
        let json = try body(of: request)
        XCTAssertEqual(json["model"] as? String, "gpt-4o-mini")
        XCTAssertEqual((json["response_format"] as? [String: Any])?["type"] as? String, "json_object")
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user"])
    }

    func testGrokUsesOpenAICompatibleShapeOnItsOwnHost() throws {
        let request = try CompanionClient.request(
            system: "sys", user: "usr", configuration: configuration(.grok, key: "xai-1"), temperature: 0.7
        )
        XCTAssertEqual(request.url?.host, "api.x.ai")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer xai-1")
        XCTAssertNotNil(try body(of: request)["response_format"])
    }

    func testAnthropicRequestShape() throws {
        let request = try CompanionClient.request(
            system: "sys", user: "usr", configuration: configuration(.anthropic, model: "claude-opus-5", key: "sk-ant"), temperature: 0.7
        )
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let json = try body(of: request)
        XCTAssertEqual(json["model"] as? String, "claude-opus-5")
        XCTAssertNotNil(json["max_tokens"])
        XCTAssertTrue((json["system"] as? String)?.hasPrefix("sys") == true)
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?["role"] as? String, "user")
    }

    func testGeminiRequestShape() throws {
        let request = try CompanionClient.request(
            system: "sys", user: "usr", configuration: configuration(.gemini, model: "gemini-2.5-flash", key: "AIza"), temperature: 0.7
        )
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "AIza")
        let json = try body(of: request)
        let generation = try XCTUnwrap(json["generationConfig"] as? [String: Any])
        XCTAssertEqual(generation["responseMimeType"] as? String, "application/json")
        XCTAssertNotNil(json["system_instruction"])
    }

    func testOffProviderCannotBuildARequest() {
        XCTAssertThrowsError(
            try CompanionClient.request(system: "s", user: "u", configuration: configuration(.off), temperature: 0)
        )
    }

    func testKeyNeverAppearsInURL() throws {
        for provider in AIProvider.allCases where provider != .off {
            let request = try CompanionClient.request(
                system: "s", user: "u", configuration: configuration(provider, key: "SECRET-KEY"), temperature: 0
            )
            XCTAssertFalse(request.url?.absoluteString.contains("SECRET-KEY") ?? true, "\(provider) leaked the key into the URL")
        }
    }

    // MARK: - Responses

    func testExtractsOpenAIText() throws {
        let data = Data(#"{"choices":[{"message":{"role":"assistant","content":"{\"ok\":true}"}}]}"#.utf8)
        XCTAssertEqual(try CompanionClient.extractText(from: data, provider: .openAI), #"{"ok":true}"#)
        XCTAssertEqual(try CompanionClient.extractText(from: data, provider: .grok), #"{"ok":true}"#)
    }

    func testExtractsAnthropicTextBlocksAndSkipsThinking() throws {
        let data = Data(#"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"{\"ok\":"},{"type":"text","text":"true}"}],"stop_reason":"end_turn"}"#.utf8)
        XCTAssertEqual(try CompanionClient.extractText(from: data, provider: .anthropic), #"{"ok":true}"#)
    }

    func testAnthropicRefusalIsSurfaced() {
        let data = Data(#"{"content":[],"stop_reason":"refusal"}"#.utf8)
        XCTAssertThrowsError(try CompanionClient.extractText(from: data, provider: .anthropic)) { error in
            XCTAssertEqual(error as? CompanionClientError, .refused)
        }
    }

    func testExtractsGeminiText() throws {
        let data = Data(#"{"candidates":[{"content":{"parts":[{"text":"{\"ok\":true}"}],"role":"model"}}]}"#.utf8)
        XCTAssertEqual(try CompanionClient.extractText(from: data, provider: .gemini), #"{"ok":true}"#)
    }

    func testEmptyReplyThrows() {
        let data = Data(#"{"choices":[{"message":{"content":"   "}}]}"#.utf8)
        XCTAssertThrowsError(try CompanionClient.extractText(from: data, provider: .openAI)) { error in
            XCTAssertEqual(error as? CompanionClientError, .emptyResponse)
        }
    }

    func testProviderErrorMessageIsExtracted() {
        let data = Data(#"{"error":{"message":"Incorrect API key provided","type":"invalid_request_error"}}"#.utf8)
        XCTAssertEqual(CompanionClient.errorMessage(from: data), "Incorrect API key provided")
        XCTAssertEqual(
            CompanionClientError.httpStatus(401, message: "Incorrect API key provided").errorDescription,
            "Incorrect API key provided"
        )
    }

    func testJSONDataStripsCodeFences() throws {
        let fenced = "```json\n{\"recommendations\":[]}\n```"
        let data = try XCTUnwrap(CompanionClient.jsonData(from: fenced))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["recommendations"])
        XCTAssertNil(CompanionClient.jsonData(from: "no json here"))
    }
}
