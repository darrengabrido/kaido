import Foundation
import CoreLocation
import Observation

/// Kaido's ride companion: the one place the app talks to a language model from.
///
/// Today it has a single capability, curating Free Ride stops. Anything else that wants a
/// model (shared listening suggestions, voice, a memory layer) attaches here rather than
/// growing its own client and key handling. Settings live in `CompanionSettingsStore`; the
/// wire format lives in `CompanionClient`; this class is the seam between features and both.
@Observable
@MainActor
final class Companion {
    static let shared = Companion()

    let settings: CompanionSettingsStore
    private let client: CompanionClient

    init(settings: CompanionSettingsStore = .shared, client: CompanionClient = CompanionClient()) {
        self.settings = settings
        self.client = client
    }

    /// True when a model is actually reachable (a key exists for the chosen provider).
    var isAIEnabled: Bool {
        settings.activeConfiguration != nil
    }

    // MARK: - Capabilities

    /// Free Ride: pick 3 to 5 stops from nearby candidates. Falls back to built-in rules when
    /// no model is configured; a configured model that fails throws so the panel can say so.
    func curateStops(
        areaDescription: String,
        candidates: [SearchResult],
        userCoordinate: CLLocationCoordinate2D
    ) async throws -> [POIRecommendation] {
        guard let configuration = settings.activeConfiguration else {
            return CompanionStopCurator.curateLocally(candidates: candidates, userCoordinate: userCoordinate)
        }
        let prompt = try CompanionStopCurator.prompt(
            areaDescription: areaDescription,
            candidates: candidates,
            userCoordinate: userCoordinate
        )
        let text = try await client.complete(
            system: prompt.system,
            user: prompt.user,
            configuration: configuration
        )
        return try CompanionStopCurator.parse(text, candidates: candidates, userCoordinate: userCoordinate)
    }

    /// One tiny round trip to prove a key and model work. Returns the model's raw reply.
    func testConnection(_ configuration: CompanionConfiguration) async throws -> String {
        let text = try await client.complete(
            system: "You are a connectivity check. Reply with JSON only.",
            user: "Reply with exactly {\"ok\":true}",
            configuration: configuration,
            temperature: 0
        )
        guard let data = CompanionClient.jsonData(from: text),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["ok"] as? Bool == true
        else {
            throw CompanionClientError.notJSON
        }
        return text
    }
}
