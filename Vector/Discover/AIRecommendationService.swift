import Foundation
import CoreLocation

enum AIRecommendationError: LocalizedError {
    case notConfigured
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AI suggestions aren't configured yet."
        case .invalidResponse:
            return "Couldn't get AI suggestions. Try again."
        }
    }
}

/// Curates nearby POI candidates into a short, cyclist-friendly list.
/// Uses OpenAI when `OPENAI_API_KEY` is set; otherwise falls back to local heuristics.
struct AIRecommendationService {
    private static let model = "gpt-4o-mini"

    func curate(
        areaDescription: String,
        candidates: [SearchResult],
        userCoordinate: CLLocationCoordinate2D
    ) async throws -> [POIRecommendation] {
        if let apiKey = Self.apiKey, !apiKey.isEmpty {
            return try await curateWithOpenAI(
                apiKey: apiKey,
                areaDescription: areaDescription,
                candidates: candidates,
                userCoordinate: userCoordinate
            )
        }
        return curateLocally(candidates: candidates, userCoordinate: userCoordinate)
    }

    var isAIEnabled: Bool {
        guard let apiKey = Self.apiKey else { return false }
        return !apiKey.isEmpty
    }

    // MARK: - OpenAI

    private func curateWithOpenAI(
        apiKey: String,
        areaDescription: String,
        candidates: [SearchResult],
        userCoordinate: CLLocationCoordinate2D
    ) async throws -> [POIRecommendation] {
        let candidatePayload = candidates.map { candidate in
            let distance = userCoordinate.distance(to: candidate.coordinate)
            return [
                "id": candidate.id,
                "name": candidate.name,
                "category": candidate.category ?? "Place",
                "distance_m": Int(distance.rounded()),
                "address": candidate.placeFormatted ?? ""
            ] as [String: Any]
        }

        let payload: [String: Any] = [
            "model": Self.model,
            "temperature": 0.7,
            "response_format": ["type": "json_object"],
            "messages": [
                [
                    "role": "system",
                    "content": """
                    You help cyclists discover interesting nearby stops during a casual free ride.
                    Pick 3–5 places from the candidate list only — never invent places.
                    Prefer variety (e.g. a park, a cafe, a viewpoint) and places within easy riding distance.
                    Each blurb is one short sentence (max 90 characters) explaining why it's worth a stop.
                    Return JSON: {"recommendations":[{"id":"...","blurb":"..."}]}
                    """
                ],
                [
                    "role": "user",
                    "content": """
                    Area: \(areaDescription)
                    Candidates: \(String(data: try JSONSerialization.data(withJSONObject: candidatePayload), encoding: .utf8) ?? "[]")
                    """
                ]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIRecommendationError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              let contentData = content.data(using: .utf8) else {
            throw AIRecommendationError.invalidResponse
        }

        let aiResponse = try JSONDecoder().decode(AIRecommendationResponse.self, from: contentData)
        let candidateByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })

        return aiResponse.recommendations.compactMap { pick in
            guard let candidate = candidateByID[pick.id] else { return nil }
            return POIRecommendation(
                from: candidate,
                blurb: pick.blurb,
                userCoordinate: userCoordinate
            )
        }
    }

    // MARK: - Local fallback

    private func curateLocally(
        candidates: [SearchResult],
        userCoordinate: CLLocationCoordinate2D
    ) -> [POIRecommendation] {
        let sorted = candidates
            .sorted { userCoordinate.distance(to: $0.coordinate) < userCoordinate.distance(to: $1.coordinate) }

        var picks: [POIRecommendation] = []
        var usedCategories = Set<String>()

        for candidate in sorted {
            let categoryKey = (candidate.category ?? "place").lowercased()
            if picks.count >= 3, usedCategories.contains(categoryKey) { continue }
            usedCategories.insert(categoryKey)
            picks.append(POIRecommendation(
                from: candidate,
                blurb: Self.templateBlurb(for: candidate),
                userCoordinate: userCoordinate
            ))
            if picks.count == 5 { break }
        }

        if picks.count < 3 {
            for candidate in sorted where !picks.contains(where: { $0.id == candidate.id }) {
                picks.append(POIRecommendation(
                    from: candidate,
                    blurb: Self.templateBlurb(for: candidate),
                    userCoordinate: userCoordinate
                ))
                if picks.count == 5 { break }
            }
        }

        return picks
    }

    private static func templateBlurb(for candidate: SearchResult) -> String {
        switch candidate.category?.lowercased() {
        case "coffee", "cafe":
            return "A good spot to grab a coffee on your ride."
        case "park":
            return "Stretch your legs and enjoy some green space nearby."
        case "restaurant":
            return "Fuel up with a bite before you keep rolling."
        case "bar", "brewery":
            return "A laid-back stop if you want to take a break."
        case "bakery":
            return "Fresh pastries worth a quick detour."
        case "ice cream":
            return "A sweet reward within riding distance."
        default:
            return "Worth a look while you're exploring the area."
        }
    }

    private static var apiKey: String? {
        Bundle.main.object(forInfoDictionaryKey: "OpenAIAPIKey") as? String
    }
}

private struct OpenAIChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }
}

private struct AIRecommendationResponse: Decodable {
    let recommendations: [Pick]

    struct Pick: Decodable {
        let id: String
        let blurb: String
    }
}

private extension POIRecommendation {
    init(from candidate: SearchResult, blurb: String, userCoordinate: CLLocationCoordinate2D) {
        self.id = candidate.id
        self.name = candidate.name
        self.placeFormatted = candidate.placeFormatted
        self.coordinate = candidate.coordinate
        self.category = candidate.category
        self.iconName = candidate.iconName
        self.blurb = blurb
        self.distanceMeters = userCoordinate.distance(to: candidate.coordinate)
    }
}

private extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}
