import Foundation

/// In-memory message history, delivery dedup, and the incoming-banner queue. Deliberately has no
/// network dependency of its own — `GroupRideSessionStore` performs the actual send/fetch calls
/// and feeds results in through `ingest`, which keeps dedup/queueing logic directly unit testable.
@MainActor
@Observable
final class GroupRideMessageCenter {
    private(set) var recentMessages: [GroupRideMessage] = []
    private(set) var bannerQueue: [GroupRideMessage] = []
    private(set) var currentBanner: GroupRideMessage?
    private var seenMessageIds: Set<UUID> = []
    private var bannerTask: Task<Void, Never>?

    /// Replaces state with durable history — called on join and on reconnect/foreground refresh.
    func loadHistory(_ messages: [GroupRideMessage]) {
        recentMessages = messages
        seenMessageIds = Set(messages.map(\.id))
    }

    /// Ingests one message from either a send confirmation or a realtime notice. A repeat
    /// delivery of the same `id` (e.g. the durable fetch and the broadcast notice racing each
    /// other) is dropped silently. Only `isIncoming` messages — ones this rider didn't just send
    /// themselves — enter the banner queue.
    @discardableResult
    func ingest(_ message: GroupRideMessage, isIncoming: Bool) -> Bool {
        guard !seenMessageIds.contains(message.id) else { return false }
        seenMessageIds.insert(message.id)
        recentMessages.append(message)
        if recentMessages.count > GroupRideConfig.Messaging.recentMessageHistoryLimit {
            recentMessages.removeFirst(recentMessages.count - GroupRideConfig.Messaging.recentMessageHistoryLimit)
        }
        if isIncoming {
            enqueueBanner(message)
        }
        return true
    }

    func dismissCurrentBanner() {
        currentBanner = nil
        bannerTask?.cancel()
        bannerTask = nil
        advanceBannerQueueIfNeeded()
    }

    func reset() {
        recentMessages = []
        seenMessageIds = []
        bannerQueue = []
        currentBanner = nil
        bannerTask?.cancel()
        bannerTask = nil
    }

    private func enqueueBanner(_ message: GroupRideMessage) {
        bannerQueue.append(message)
        advanceBannerQueueIfNeeded()
    }

    private func advanceBannerQueueIfNeeded() {
        guard currentBanner == nil, !bannerQueue.isEmpty else { return }
        currentBanner = bannerQueue.removeFirst()
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(GroupRideConfig.Messaging.bannerDisplayDuration))
            guard !Task.isCancelled else { return }
            self?.dismissCurrentBanner()
        }
    }
}
