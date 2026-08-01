import Foundation

/// Thin seam over wall-clock time so throttle/staleness logic is testable without waiting on
/// real timers. Production code uses `SystemClock`; tests substitute `ManualClock`.
protocol GroupRideClock: Sendable {
    func now() -> Date
}

struct SystemClock: GroupRideClock {
    func now() -> Date { Date() }
}

/// Test double with an explicit, steppable "now". Not used outside of `KaidoTests` today, but
/// lives alongside the protocol since both sides of the seam belong together.
final class ManualClock: GroupRideClock, @unchecked Sendable {
    private var current: Date
    init(_ date: Date = Date()) { current = date }
    func now() -> Date { current }
    func advance(by interval: TimeInterval) { current = current.addingTimeInterval(interval) }
    func set(_ date: Date) { current = date }
}
