import Foundation

/// Ephemeral, high-frequency transport for one active group ride: rider locations and connected
/// state travel here, never through Postgres (see `GroupRideService` for the durable/lifecycle
/// side). Exactly one ride may be connected at a time per client instance — calling `connect`
/// again tears down any previous subscription first, so reconnection never stacks channels.
///
/// Callback-based rather than `AsyncStream`-based to match this codebase's existing convention
/// for hardware/session event delivery (see `BikeBLEManager`) — callbacks are always invoked on
/// the main actor.
protocol GroupRideRealtimeClient: AnyObject, Sendable {
    /// `onMessage`/`onRideStatusChange` deliberately carry no payload: Realtime Broadcast has no
    /// per-message identity binding, so a "message"/"ride_status" event's own field values (sender,
    /// body, status) are not authenticated — any active member of the ride can broadcast whatever
    /// they like. These callbacks are therefore only ever a "something changed, go check" signal;
    /// the receiver must re-fetch from the durable, RLS-protected service before trusting/acting on
    /// anything (see `GroupRideSessionStore.handleIncomingMessageNotice`/`handleRemoteStatusChangeNotice`).
    func connect(
        rideId: UUID,
        memberId: UUID,
        onLocation: @escaping @Sendable (GroupRideLocationEnvelope) -> Void,
        onMessage: @escaping @Sendable () -> Void,
        onRideStatusChange: @escaping @Sendable () -> Void,
        onPresenceChange: @escaping @Sendable (_ onlineMemberIds: Set<UUID>) -> Void,
        onConnectionStateChange: @escaping @Sendable (GroupRideConnectionState) -> Void
    ) async

    /// Idempotent — safe to call from every teardown path (leave, end, dismiss, deinit) even if
    /// already disconnected.
    func disconnect() async

    func publishLocation(_ envelope: GroupRideLocationEnvelope) async

    /// Fans out a just-persisted message for instant delivery. The database row inserted via
    /// `GroupRideService.sendMessage` remains the durable source of truth (used for recent-history
    /// fetch and reconnection recovery); this broadcast only makes delivery to already-connected
    /// members immediate instead of waiting on a poll.
    func publishMessageNotice(_ message: GroupRideMessage) async

    /// Lets a lifecycle change (start/end/cancel/route update) reach already-connected members
    /// immediately, without a second Realtime primitive — `group_rides` itself has no durable
    /// change feed in this MVP, so the acting client (almost always the host) announces the new
    /// status over the same private channel right after the RPC that changed it succeeds.
    /// Receivers treat this purely as a "go re-fetch" prompt rather than trusting `status` itself,
    /// since the broadcast isn't authenticated as actually coming from the host.
    func publishRideStatusNotice(_ status: GroupRideStatus) async
}
