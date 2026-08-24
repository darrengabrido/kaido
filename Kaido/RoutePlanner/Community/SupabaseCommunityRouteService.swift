import Foundation
import Supabase

/// Talks to the `community_routes` table (see `supabase/migrations/0002_community_routes.sql`)
/// through the app's one shared `KaidoSupabaseClient` — never a second client instance.
///
/// Follows the same conventions as `SupabaseGroupRideService`: every insert payload uses explicit
/// `CodingKeys` matching the Postgres column names exactly, and every response is decoded through
/// the explicit `wireDecoder` below — reusing the existing file-scope `PostgresDate.parse` helper
/// from `SupabaseGroupRideService.swift` rather than duplicating date parsing.
///
/// Publishing resolves an identity via `SupabaseGroupRideIdentityProvider` — Ride Together's
/// guest-anonymous-session flow, reused as-is here rather than duplicated, since both features
/// need exactly the same thing: a stable `auth.uid()` for RLS that a guest never has to notice as
/// "creating an account".
final class SupabaseCommunityRouteService: CommunityRouteService, @unchecked Sendable {
    private let client: SupabaseClient?
    private let identityProvider: GroupRideIdentityProvider

    init(
        client: SupabaseClient? = KaidoSupabaseClient.shared,
        identityProvider: GroupRideIdentityProvider = SupabaseGroupRideIdentityProvider()
    ) {
        self.client = client
        self.identityProvider = identityProvider
    }

    private func requireClient() throws -> SupabaseClient {
        guard let client else { throw CommunityRouteServiceError.notConfigured }
        return client
    }

    func fetchPublished(limit: Int) async throws -> [CommunityRoute] {
        let client = try requireClient()
        do {
            let response = try await client
                .from("community_routes")
                .select()
                .eq("status", value: CommunityRouteStatus.published.rawValue)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
            return try Self.wireDecoder.decode([CommunityRoute].self, from: response.data)
        } catch {
            throw Self.mapError(error)
        }
    }

    func publish(
        name: String,
        description: String?,
        distanceMeters: Double,
        elevationGainMeters: Double,
        waypoints: [CommunityRoute.Waypoint],
        displayName: String
    ) async throws -> CommunityRoute {
        guard let start = waypoints.first else {
            throw CommunityRouteServiceError.server(
                String(localized: "A route needs at least one waypoint to share.")
            )
        }

        let client = try requireClient()
        let identity: GroupRideIdentity
        do {
            identity = try await identityProvider.ensureIdentity()
        } catch {
            throw CommunityRouteServiceError.notAuthenticated
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = InsertPayload(
            authorUserId: identity.userId,
            authorDisplayName: displayName,
            name: trimmedName.isEmpty ? "Untitled Route" : trimmedName,
            description: (trimmedDescription?.isEmpty ?? true) ? nil : trimmedDescription,
            distanceMeters: distanceMeters,
            elevationGainMeters: elevationGainMeters,
            waypoints: waypoints,
            startLatitude: start.latitude,
            startLongitude: start.longitude,
            status: .published
        )

        do {
            let response = try await client
                .from("community_routes")
                .insert(payload)
                .select()
                .single()
                .execute()
            return try Self.wireDecoder.decode(CommunityRoute.self, from: response.data)
        } catch {
            throw Self.mapError(error)
        }
    }

    func remove(routeId: UUID) async throws {
        let client = try requireClient()
        do {
            _ = try await client
                .from("community_routes")
                .delete()
                .eq("id", value: routeId.uuidString)
                .execute()
        } catch {
            throw Self.mapError(error)
        }
    }

    // MARK: - Wire format

    /// Top-level fields here become real table columns (unlike the opaque `waypoints` jsonb
    /// payload nested inside), so — same reasoning as `SupabaseGroupRideService`'s
    /// `MessageInsertPayload` — this is independent of the Postgrest client's own encoder
    /// configuration rather than relying on it matching what this app assumes.
    private struct InsertPayload: Encodable {
        let authorUserId: UUID
        let authorDisplayName: String
        let name: String
        let description: String?
        let distanceMeters: Double
        let elevationGainMeters: Double
        let waypoints: [CommunityRoute.Waypoint]
        let startLatitude: Double
        let startLongitude: Double
        let status: CommunityRouteStatus

        enum CodingKeys: String, CodingKey {
            case authorUserId = "author_user_id"
            case authorDisplayName = "author_display_name"
            case name
            case description
            case distanceMeters = "distance_meters"
            case elevationGainMeters = "elevation_gain_meters"
            case waypoints
            case startLatitude = "start_latitude"
            case startLongitude = "start_longitude"
            case status
        }
    }

    private static let wireDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = PostgresDate.parse(string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized date format: \(string)"
            )
        }
        return decoder
    }()

    private static func mapError(_ error: Error) -> CommunityRouteServiceError {
        if let serviceError = error as? CommunityRouteServiceError { return serviceError }
        let message: String
        if let postgrestError = error as? PostgrestError {
            message = postgrestError.message
        } else {
            message = error.localizedDescription
        }
        return classifyServerMessage(message)
    }

    /// Split out from `mapError` purely so a unit test can exercise Postgres/PostgREST's
    /// RLS-violation wording without standing up a real (or mocked) network call.
    static func classifyServerMessage(_ message: String) -> CommunityRouteServiceError {
        let lowered = message.lowercased()
        if lowered.contains("row-level security") || lowered.contains("permission denied") {
            return .notOwner
        }
        return .server(message)
    }
}
