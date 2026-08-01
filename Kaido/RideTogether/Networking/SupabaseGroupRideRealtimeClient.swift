import Foundation
import Supabase
import Realtime

/// Concrete Realtime transport for one `group-ride:<id>` private channel.
///
/// NOTE ON VERIFICATION: this file is the single most likely spot to need a small adjustment
/// once compiled against the exact installed `supabase-swift` version — private-channel
/// broadcast/presence is a newer part of that SDK and its precise method names have shifted
/// across releases. Everything else in Ride Together depends only on the `GroupRideRealtimeClient`
/// protocol above, so a fix here is isolated to this one file. See docs/RideTogether.md.
actor SupabaseGroupRideRealtimeClient: GroupRideRealtimeClient {
    private let client: SupabaseClient?
    private var channel: RealtimeChannelV2?
    private var listenTasks: [Task<Void, Never>] = []

    init(client: SupabaseClient? = KaidoSupabaseClient.shared) {
        self.client = client
    }

    func connect(
        rideId: UUID,
        memberId: UUID,
        onLocation: @escaping @Sendable (GroupRideLocationEnvelope) -> Void,
        onMessage: @escaping @Sendable (GroupRideMessage) -> Void,
        onRideStatusChange: @escaping @Sendable (GroupRideStatus) -> Void,
        onPresenceChange: @escaping @Sendable (Set<UUID>) -> Void,
        onConnectionStateChange: @escaping @Sendable (GroupRideConnectionState) -> Void
    ) async {
        await tearDown()

        guard let client else {
            onConnectionStateChange(.failed("Ride Together isn't configured"))
            return
        }

        onConnectionStateChange(.connecting)

        let topic = "group-ride:\(rideId.uuidString)"
        let newChannel = client.channel(topic) { config in
            config.isPrivate = true
        }
        channel = newChannel

        listenTasks = [
            Task {
                for await payload in newChannel.broadcastStream(event: "location") {
                    if let envelope = Self.decode(GroupRideLocationEnvelope.self, from: payload) {
                        onLocation(envelope)
                    }
                }
            },
            Task {
                for await payload in newChannel.broadcastStream(event: "message") {
                    if let message = Self.decode(GroupRideMessage.self, from: payload) {
                        onMessage(message)
                    }
                }
            },
            Task {
                for await payload in newChannel.broadcastStream(event: "ride_status") {
                    if let notice = Self.decode(RideStatusNotice.self, from: payload) {
                        onRideStatusChange(notice.status)
                    }
                }
            },
            Task {
                var online = Set<UUID>()
                for await change in newChannel.presenceChange() {
                    for join in change.joins.values {
                        if let id = Self.memberId(fromPresenceState: join.state) {
                            online.insert(id)
                        }
                    }
                    for leave in change.leaves.values {
                        if let id = Self.memberId(fromPresenceState: leave.state) {
                            online.remove(id)
                        }
                    }
                    onPresenceChange(online)
                }
            }
        ]

        do {
            try await newChannel.subscribeWithError()
            await newChannel.track(state: ["member_id": .string(memberId.uuidString)])
            onConnectionStateChange(.connected)
        } catch {
            onConnectionStateChange(.failed(error.localizedDescription))
        }
    }

    func disconnect() async {
        await tearDown()
    }

    func publishLocation(_ envelope: GroupRideLocationEnvelope) async {
        guard let channel else { return }
        try? await channel.broadcast(event: "location", message: envelope)
    }

    func publishMessageNotice(_ message: GroupRideMessage) async {
        guard let channel else { return }
        try? await channel.broadcast(event: "message", message: message)
    }

    func publishRideStatusNotice(_ status: GroupRideStatus) async {
        guard let channel else { return }
        try? await channel.broadcast(event: "ride_status", message: RideStatusNotice(status: status))
    }

    private struct RideStatusNotice: Codable, Sendable {
        let status: GroupRideStatus
    }

    private func tearDown() async {
        for task in listenTasks { task.cancel() }
        listenTasks = []
        if let channel {
            await channel.unsubscribe()
        }
        channel = nil
    }

    // MARK: - Payload decoding

    private static func decode<T: Decodable>(_ type: T.Type, from payload: JSONObject) -> T? {
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func memberId(fromPresenceState state: JSONObject) -> UUID? {
        guard case let .string(raw)? = state["member_id"] else { return nil }
        return UUID(uuidString: raw)
    }
}
