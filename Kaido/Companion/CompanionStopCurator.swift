import Foundation
import CoreLocation

/// Turns a list of nearby POI candidates into 3 to 5 stops worth pulling over for, with a
/// one-line blurb each. Prompt and parsing are provider-agnostic; when no model is configured
/// the local rules pick by distance and category variety instead.
enum CompanionStopCurator {
    struct Prompt {
        let system: String
        let user: String
    }

    static let systemPrompt = """
    You help cyclists discover interesting nearby stops during a casual free ride.
    Pick 3–5 places from the candidate list only — never invent places.
    Prefer variety (e.g. a park, a cafe, a viewpoint) and places within easy riding distance.
    Each blurb is one short sentence (max 90 characters) explaining why it's worth a stop.
    Return JSON: {"recommendations":[{"id":"...","blurb":"..."}]}
    """

    static func prompt(
        areaDescription: String,
        candidates: [SearchResult],
        userCoordinate: CLLocationCoordinate2D
    ) throws -> Prompt {
        let payload = candidates.map { candidate -> [String: Any] in
            let distance = userCoordinate.distance(to: candidate.coordinate)
            return [
                "id": candidate.id,
                "name": candidate.name,
                "category": candidate.category ?? "Place",
                "distance_m": Int(distance.rounded()),
                "address": candidate.placeFormatted ?? ""
            ]
        }
        let candidatesJSON = String(
            data: try JSONSerialization.data(withJSONObject: payload),
            encoding: .utf8
        ) ?? "[]"
        return Prompt(
            system: systemPrompt,
            user: """
            Area: \(areaDescription)
            Candidates: \(candidatesJSON)
            """
        )
    }

    /// Parses the model's JSON reply back onto the real candidates. Anything the model made up
    /// (an id that isn't in the list) is dropped rather than shown.
    static func parse(
        _ text: String,
        candidates: [SearchResult],
        userCoordinate: CLLocationCoordinate2D
    ) throws -> [POIRecommendation] {
        guard let data = CompanionClient.jsonData(from: text) else {
            throw CompanionClientError.notJSON
        }
        let response: CuratedResponse
        do {
            response = try JSONDecoder().decode(CuratedResponse.self, from: data)
        } catch {
            throw CompanionClientError.notJSON
        }
        let candidateByID = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return response.recommendations.compactMap { pick in
            guard let candidate = candidateByID[pick.id] else { return nil }
            return POIRecommendation(from: candidate, blurb: pick.blurb, userCoordinate: userCoordinate)
        }
    }

    // MARK: - Local fallback

    static func curateLocally(
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
                blurb: templateBlurb(for: candidate),
                userCoordinate: userCoordinate
            ))
            if picks.count == 5 { break }
        }

        if picks.count < 3 {
            for candidate in sorted where !picks.contains(where: { $0.id == candidate.id }) {
                picks.append(POIRecommendation(
                    from: candidate,
                    blurb: templateBlurb(for: candidate),
                    userCoordinate: userCoordinate
                ))
                if picks.count == 5 { break }
            }
        }

        return picks
    }

    static func templateBlurb(for candidate: SearchResult) -> String {
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

    private struct CuratedResponse: Decodable {
        let recommendations: [Pick]

        struct Pick: Decodable {
            let id: String
            let blurb: String
        }
    }
}

extension POIRecommendation {
    init(from candidate: SearchResult, blurb: String, userCoordinate: CLLocationCoordinate2D) {
        self.init(
            id: candidate.id,
            name: candidate.name,
            placeFormatted: candidate.placeFormatted,
            coordinate: candidate.coordinate,
            category: candidate.category,
            iconName: candidate.iconName,
            blurb: blurb,
            distanceMeters: userCoordinate.distance(to: candidate.coordinate)
        )
    }
}

private extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}
