import Foundation

/// Explicit Realtime connection lifecycle for the group-ride channel, surfaced in the UI so a
/// rider always knows whether their location/messages are actually flowing.
enum GroupRideConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case failed(String)
}
