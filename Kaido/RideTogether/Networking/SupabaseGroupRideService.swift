import Foundation
import CoreLocation
import Supabase

/// Talks to the `group_rides` / `group_ride_members` / `group_ride_messages` tables and their
/// SECURITY DEFINER RPCs (see `supabase/migrations/0001_group_rides.sql`) through the app's one
/// shared `KaidoSupabaseClient` — never a second client instance.
///
/// Every RPC/table parameter struct below uses explicit `CodingKeys` matching the Postgres
/// function parameter or column names exactly, and every response is decoded through the
/// explicit `wireDecoder` below rather than relying on the client's own default `JSONDecoder`
/// configuration — so this adapter's on-the-wire behavior doesn't depend on an assumption about
/// the installed SDK version's default encoding/decoding strategy.
final class SupabaseGroupRideService: GroupRideService, @unchecked Sendable {
    private let client: SupabaseClient?

    init(client: SupabaseClient? = KaidoSupabaseClient.shared) {
        self.client = client
    }

    private func requireClient() throws -> SupabaseClient {
        guard let client else { throw GroupRideServiceError.notConfigured }
        return client
    }

    // MARK: - Lifecycle RPCs

    func createRide(
        destinationName: String,
        destination: CLLocationCoordinate2D,
        routeSnapshot: GroupRideRouteSnapshot,
        maxMembers: Int,
        title: String?,
        displayName: String
    ) async throws -> GroupRideCreationResult {
        struct Params: Encodable {
            let destinationName: String
            let destinationLatitude: Double
            let destinationLongitude: Double
            let routeSnapshot: GroupRideRouteSnapshot
            let maxMembers: Int
            let title: String?
            let displayName: String

            enum CodingKeys: String, CodingKey {
                case destinationName = "p_destination_name"
                case destinationLatitude = "p_destination_latitude"
                case destinationLongitude = "p_destination_longitude"
                case routeSnapshot = "p_route_snapshot"
                case maxMembers = "p_max_members"
                case title = "p_title"
                case displayName = "p_display_name"
            }
        }
        struct Envelope: Decodable {
            let ride: GroupRide
            let rawInviteToken: String
        }

        let client = try requireClient()
        let params = Params(
            destinationName: destinationName,
            destinationLatitude: destination.latitude,
            destinationLongitude: destination.longitude,
            routeSnapshot: routeSnapshot,
            maxMembers: maxMembers,
            title: title,
            displayName: displayName
        )
        do {
            let response = try await client.rpc("create_group_ride", params: params).execute()
            let decoded = try Self.wireDecoder.decode(Envelope.self, from: response.data)
            return GroupRideCreationResult(ride: decoded.ride, rawInviteToken: decoded.rawInviteToken)
        } catch {
            throw Self.mapError(error)
        }
    }

    func previewInvite(rideId: UUID, token: String) async throws -> GroupRideInvitePreview {
        struct Params: Encodable {
            let rideId: UUID
            let inviteToken: String
            enum CodingKeys: String, CodingKey {
                case rideId = "p_ride_id"
                case inviteToken = "p_invite_token"
            }
        }
        struct Envelope: Decodable {
            let rideId: UUID
            let status: GroupRideStatus
            let destinationName: String
            let destinationLatitude: Double
            let destinationLongitude: Double
            let routeSnapshot: GroupRideRouteSnapshot
            let maxMembers: Int
            let activeMemberCount: Int
            let hostDisplayName: String
        }

        let client = try requireClient()
        do {
            let response = try await client.rpc(
                "preview_group_ride_invite",
                params: Params(rideId: rideId, inviteToken: token)
            ).execute()
            let decoded = try Self.wireDecoder.decode(Envelope.self, from: response.data)
            return GroupRideInvitePreview(
                rideId: decoded.rideId,
                status: decoded.status,
                destinationName: decoded.destinationName,
                destinationCoordinate: CLLocationCoordinate2D(
                    latitude: decoded.destinationLatitude,
                    longitude: decoded.destinationLongitude
                ),
                routeSnapshot: decoded.routeSnapshot,
                maxMembers: decoded.maxMembers,
                activeMemberCount: decoded.activeMemberCount,
                hostDisplayName: decoded.hostDisplayName
            )
        } catch {
            throw Self.mapError(error)
        }
    }

    func joinRide(rideId: UUID, token: String, displayName: String) async throws -> GroupRideJoinResult {
        struct Params: Encodable {
            let rideId: UUID
            let inviteToken: String
            let displayName: String
            enum CodingKeys: String, CodingKey {
                case rideId = "p_ride_id"
                case inviteToken = "p_invite_token"
                case displayName = "p_display_name"
            }
        }
        struct Envelope: Decodable {
            let ride: GroupRide
            let membership: GroupRideMember
        }

        let client = try requireClient()
        do {
            let response = try await client.rpc(
                "join_group_ride",
                params: Params(rideId: rideId, inviteToken: token, displayName: displayName)
            ).execute()
            let decoded = try Self.wireDecoder.decode(Envelope.self, from: response.data)
            return GroupRideJoinResult(ride: decoded.ride, membership: decoded.membership)
        } catch {
            throw Self.mapError(error)
        }
    }

    func rotateInvite(rideId: UUID) async throws -> GroupRideInviteRotation {
        struct Params: Encodable {
            let rideId: UUID
            enum CodingKeys: String, CodingKey { case rideId = "p_ride_id" }
        }
        struct Envelope: Decodable {
            let rawInviteToken: String
            let inviteExpiresAt: Date
        }

        let client = try requireClient()
        do {
            let response = try await client.rpc(
                "rotate_group_ride_invite",
                params: Params(rideId: rideId)
            ).execute()
            let decoded = try Self.wireDecoder.decode(Envelope.self, from: response.data)
            return GroupRideInviteRotation(
                rawInviteToken: decoded.rawInviteToken,
                inviteExpiresAt: decoded.inviteExpiresAt
            )
        } catch {
            throw Self.mapError(error)
        }
    }

    func updateRoute(
        rideId: UUID,
        routeSnapshot: GroupRideRouteSnapshot,
        destinationName: String?,
        destination: CLLocationCoordinate2D?
    ) async throws -> GroupRide {
        struct Params: Encodable {
            let rideId: UUID
            let routeSnapshot: GroupRideRouteSnapshot
            let destinationName: String?
            let destinationLatitude: Double?
            let destinationLongitude: Double?
            enum CodingKeys: String, CodingKey {
                case rideId = "p_ride_id"
                case routeSnapshot = "p_route_snapshot"
                case destinationName = "p_destination_name"
                case destinationLatitude = "p_destination_latitude"
                case destinationLongitude = "p_destination_longitude"
            }
        }
        let client = try requireClient()
        do {
            let response = try await client.rpc(
                "update_group_ride_route",
                params: Params(
                    rideId: rideId,
                    routeSnapshot: routeSnapshot,
                    destinationName: destinationName,
                    destinationLatitude: destination?.latitude,
                    destinationLongitude: destination?.longitude
                )
            ).execute()
            return try Self.decodeRideEnvelope(response.data)
        } catch {
            throw Self.mapError(error)
        }
    }

    func startRide(rideId: UUID) async throws -> GroupRide {
        try await mutateRide(rpc: "start_group_ride", rideId: rideId)
    }

    func endRide(rideId: UUID) async throws -> GroupRide {
        try await mutateRide(rpc: "end_group_ride", rideId: rideId)
    }

    func cancelRide(rideId: UUID) async throws -> GroupRide {
        try await mutateRide(rpc: "cancel_group_ride", rideId: rideId)
    }

    private func mutateRide(rpc: String, rideId: UUID) async throws -> GroupRide {
        struct Params: Encodable {
            let rideId: UUID
            enum CodingKeys: String, CodingKey { case rideId = "p_ride_id" }
        }
        let client = try requireClient()
        do {
            let response = try await client.rpc(rpc, params: Params(rideId: rideId)).execute()
            return try Self.decodeRideEnvelope(response.data)
        } catch {
            throw Self.mapError(error)
        }
    }

    func leaveRide(rideId: UUID) async throws -> GroupRideLeaveResult {
        struct Params: Encodable {
            let rideId: UUID
            enum CodingKeys: String, CodingKey { case rideId = "p_ride_id" }
        }
        struct Envelope: Decodable {
            let hostLeft: Bool
        }
        let client = try requireClient()
        do {
            let response = try await client.rpc("leave_group_ride", params: Params(rideId: rideId)).execute()
            let decoded = try Self.wireDecoder.decode(Envelope.self, from: response.data)
            return GroupRideLeaveResult(hostLeft: decoded.hostLeft)
        } catch {
            throw Self.mapError(error)
        }
    }

    func removeMember(rideId: UUID, userId: UUID) async throws {
        struct Params: Encodable {
            let rideId: UUID
            let memberUserId: UUID
            enum CodingKeys: String, CodingKey {
                case rideId = "p_ride_id"
                case memberUserId = "p_member_user_id"
            }
        }
        let client = try requireClient()
        do {
            _ = try await client.rpc(
                "remove_group_ride_member",
                params: Params(rideId: rideId, memberUserId: userId)
            ).execute()
        } catch {
            throw Self.mapError(error)
        }
    }

    func touchPresence(rideId: UUID) async throws {
        struct Params: Encodable {
            let rideId: UUID
            enum CodingKeys: String, CodingKey { case rideId = "p_ride_id" }
        }
        let client = try requireClient()
        do {
            _ = try await client.rpc("touch_group_ride_presence", params: Params(rideId: rideId)).execute()
        } catch {
            throw Self.mapError(error)
        }
    }

    // MARK: - Reads

    private static let groupRideColumns = """
    id, host_user_id, status, title, destination_name, destination_latitude, destination_longitude, \
    route_snapshot, route_snapshot_version, max_members, invite_expires_at, created_at, updated_at, \
    started_at, ended_at
    """

    func fetchRide(rideId: UUID) async throws -> GroupRide {
        let client = try requireClient()
        do {
            let response = try await client
                .from("group_rides")
                .select(Self.groupRideColumns)
                .eq("id", value: rideId.uuidString)
                .single()
                .execute()
            return try Self.wireDecoder.decode(GroupRide.self, from: response.data)
        } catch {
            throw Self.mapError(error)
        }
    }

    func fetchMembers(rideId: UUID) async throws -> [GroupRideMember] {
        let client = try requireClient()
        do {
            let response = try await client
                .from("group_ride_members")
                .select()
                .eq("ride_id", value: rideId.uuidString)
                .order("joined_at", ascending: true)
                .execute()
            return try Self.wireDecoder.decode([GroupRideMember].self, from: response.data)
        } catch {
            throw Self.mapError(error)
        }
    }

    func fetchRecentMessages(rideId: UUID, limit: Int) async throws -> [GroupRideMessage] {
        let client = try requireClient()
        do {
            let response = try await client
                .from("group_ride_messages")
                .select()
                .eq("ride_id", value: rideId.uuidString)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
            let messages = try Self.wireDecoder.decode([GroupRideMessage].self, from: response.data)
            return messages.reversed()
        } catch {
            throw Self.mapError(error)
        }
    }

    /// Explicit column-name `CodingKeys`, independent of the Postgrest client's own encoder
    /// configuration — top-level fields here become real table columns, unlike the opaque
    /// jsonb `route_snapshot` payload nested inside the RPC params above.
    private struct MessageInsertPayload: Encodable {
        let id: UUID
        let rideId: UUID
        let senderUserId: UUID
        let senderDisplayName: String
        let kind: GroupRideMessageKind
        let body: String
        let presetKey: String?
        let clientMessageId: UUID

        enum CodingKeys: String, CodingKey {
            case id
            case rideId = "ride_id"
            case senderUserId = "sender_user_id"
            case senderDisplayName = "sender_display_name"
            case kind
            case body
            case presetKey = "preset_key"
            case clientMessageId = "client_message_id"
        }
    }

    func sendMessage(_ message: GroupRideMessage) async throws -> GroupRideMessage {
        let client = try requireClient()
        let payload = MessageInsertPayload(
            id: message.id,
            rideId: message.rideId,
            senderUserId: message.senderUserId,
            senderDisplayName: message.senderDisplayName,
            kind: message.kind,
            body: message.body,
            presetKey: message.presetKey,
            clientMessageId: message.clientMessageId
        )
        do {
            let response = try await client
                .from("group_ride_messages")
                .upsert(
                    payload,
                    onConflict: "ride_id,sender_user_id,client_message_id",
                    returning: .representation
                )
                .select()
                .single()
                .execute()
            return try Self.wireDecoder.decode(GroupRideMessage.self, from: response.data)
        } catch {
            throw Self.mapError(error)
        }
    }

    // MARK: - Wire format

    private static func decodeRideEnvelope(_ data: Data) throws -> GroupRide {
        struct Envelope: Decodable { let ride: GroupRide }
        return try wireDecoder.decode(Envelope.self, from: data).ride
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

    private static func mapError(_ error: Error) -> GroupRideServiceError {
        if let serviceError = error as? GroupRideServiceError { return serviceError }
        // Catch response-parsing failures before the substring heuristics below see their raw,
        // rider-unfriendly system message (e.g. "The data couldn't be read because it isn't in
        // the correct format." for malformed/non-JSON bytes). The underlying error is logged
        // since it's otherwise invisible without an attached debugger — see `DebugLogView`.
        let nsError = error as NSError
        if error is DecodingError || (nsError.domain == NSCocoaErrorDomain && nsError.code == 3840) {
            DebugLog.shared.log("Response failed to decode: \(error)", category: "RideTogether")
            return .decoding
        }
        let message: String
        if let postgrestError = error as? PostgrestError {
            message = postgrestError.message
        } else {
            message = error.localizedDescription
        }
        let lowered = message.lowercased()
        if lowered.contains("invalid or has expired") { return .invalidInvite }
        if lowered.contains("rejoin") { return .invalidInvite }
        if lowered.contains("has ended") { return .rideEnded }
        if lowered.contains("was cancelled") || lowered.contains("no longer be started")
            || lowered.contains("no longer be invited") || lowered.contains("no longer be cancelled") {
            return .rideCancelled
        }
        if lowered.contains("is full") { return .rideFull }
        if lowered.contains("only the host") { return .notHost }
        if lowered.contains("authentication required") { return .notAuthenticated }
        return .server(message)
    }
}

/// Best-effort parser for Postgres's `timestamptz` JSON text representation, which includes
/// fractional seconds and a `+HH:MM` offset (not `Z`) — outside what `JSONDecoder`'s built-in
/// `.iso8601` strategy accepts. Also accepts the plain `Z`-suffixed form this app itself produces
/// when round-tripping `GroupRideRouteSnapshot.capturedAt` through `wireEncoder`.
enum PostgresDate {
    private static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let withoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ string: String) -> Date? {
        if let date = withFractionalSeconds.date(from: string) { return date }
        if let date = withoutFractionalSeconds.date(from: string) { return date }
        // Postgres's `now()` almost always lands on 6-digit microsecond precision (trailing
        // zeros trimmed, so anywhere from 1 to 6 digits) — `ISO8601DateFormatter`'s
        // fractional-seconds mode only ever accepts exactly 3, so a real timestamptz value
        // fails both formatters above nearly every time. Pad/truncate to milliseconds and retry
        // rather than reject a well-formed Postgres timestamp outright.
        guard let normalized = normalizedToMilliseconds(string) else { return nil }
        return withFractionalSeconds.date(from: normalized)
    }

    private static func normalizedToMilliseconds(_ string: String) -> String? {
        guard let dotIndex = string.firstIndex(of: ".") else { return nil }
        let digitsStart = string.index(after: dotIndex)
        var digitsEnd = digitsStart
        while digitsEnd < string.endIndex, string[digitsEnd].isNumber {
            digitsEnd = string.index(after: digitsEnd)
        }
        let milliseconds = String((string[digitsStart..<digitsEnd] + "000").prefix(3))
        return string.replacingCharacters(in: digitsStart..<digitsEnd, with: milliseconds)
    }
}
