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
        userCoordinate: CLLocationCoordinate2D,
        ridePurpose: RidePurpose? = nil,
        interestTags: [InterestTag] = []
    ) async throws -> [POIRecommendation] {
        if let apiKey = Self.apiKey, !apiKey.isEmpty {
            return try await curateWithOpenAI(
                apiKey: apiKey,
                areaDescription: areaDescription,
                candidates: candidates,
                userCoordinate: userCoordinate,
                ridePurpose: ridePurpose,
                interestTags: interestTags
            )
        }
        return curateLocally(
            candidates: candidates,
            userCoordinate: userCoordinate,
            interestTags: interestTags
        )
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
        userCoordinate: CLLocationCoordinate2D,
        ridePurpose: RidePurpose?,
        interestTags: [InterestTag]
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

        let riderProfileLine = Self.riderProfileLine(ridePurpose: ridePurpose, interestTags: interestTags)
        let userContent = [
            "Area: \(areaDescription)",
            riderProfileLine,
            "Candidates: \(String(data: try JSONSerialization.data(withJSONObject: candidatePayload), encoding: .utf8) ?? "[]")"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")

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
                    If a rider profile line is present, let it bias which candidates you pick and the tone of \
                    each blurb (e.g. quick and efficient for a commute, more exploratory for leisure) — but \
                    keep the variety and distance guidance above as the primary criteria.
                    Each blurb is one short sentence (max 90 characters) explaining why it's worth a stop.
                    Return JSON: {"recommendations":[{"id":"...","blurb":"..."}]}
                    """
                ],
                [
                    "role": "user",
                    "content": userContent
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

    /// One sentence summarizing whatever the rider has told us, for the OpenAI prompt.
    /// Returns nil when the rider hasn't set anything, so the prompt stays unchanged for them.
    private static func riderProfileLine(ridePurpose: RidePurpose?, interestTags: [InterestTag]) -> String? {
        var parts: [String] = []
        if let ridePurpose {
            parts.append("this is a \(ridePurpose.rawValue) ride")
        }
        if !interestTags.isEmpty {
            parts.append("interested in " + interestTags.map { $0.title.lowercased() }.joined(separator: ", "))
        }
        parts.append(
            RoutingPreferenceStore.current == .quiet
                ? "prefers calmer, low-stress stops"
                : "doesn't mind busier stops if they're quick"
        )
        guard !parts.isEmpty else { return nil }
        return "Rider profile: " + parts.joined(separator: "; ") + "."
    }

    // MARK: - Local fallback

    private func curateLocally(
        candidates: [SearchResult],
        userCoordinate: CLLocationCoordinate2D,
        interestTags: [InterestTag]
    ) -> [POIRecommendation] {
        let routingPreference = RoutingPreferenceStore.current
        let sorted = candidates
            .sorted { lhs, rhs in
                let lhsScore = Self.matchScore(for: lhs, interestTags: interestTags, routingPreference: routingPreference)
                let rhsScore = Self.matchScore(for: rhs, interestTags: interestTags, routingPreference: routingPreference)
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                return userCoordinate.distance(to: lhs.coordinate) < userCoordinate.distance(to: rhs.coordinate)
            }

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

    private static let calmCategories: Set<String> = ["coffee", "park", "bakery", "tourist_attraction"]
    private static let busyCategories: Set<String> = ["bar"]

    /// Higher score sorts first. +2 for matching a selected interest tag's POI category,
    /// ±1 for calm/busy categories depending on the rider's quiet/fast routing preference.
    private static func matchScore(
        for candidate: SearchResult,
        interestTags: [InterestTag],
        routingPreference: RoutingPreference
    ) -> Int {
        let category = (candidate.category ?? "").lowercased()
        var score = 0
        if interestTags.contains(where: { $0.poiCategories.contains(category) }) {
            score += 2
        }
        if routingPreference == .quiet {
            if Self.calmCategories.contains(category) { score += 1 }
            if Self.busyCategories.contains(category) { score -= 1 }
        }
        return score
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
