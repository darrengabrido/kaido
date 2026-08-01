import Foundation

enum GroupRideTransitionError: Error, Equatable {
    case invalidTransition(from: GroupRideStatus, to: GroupRideStatus)
}

enum GroupRideMemberTransitionError: Error, Equatable {
    case invalidTransition(from: GroupRideMemberStatus, to: GroupRideMemberStatus)
}

enum GroupRideJoinDenialReason: Equatable, Sendable {
    case invalidInvite
    case expired
    case rideEnded
    case rideCancelled
    case full
}

/// Explicit state machine for a group ride's lifecycle. This mirrors — but does not replace —
/// the authoritative checks enforced server-side by the `SECURITY DEFINER` RPCs and RLS policies
/// in `supabase/migrations`. Keeping the same rules here lets the UI disable actions that would
/// be rejected anyway, and lets these rules be unit tested without a database.
enum GroupRideStateMachine {
    // MARK: Ride-level transitions

    static func canTransition(from: GroupRideStatus, to: GroupRideStatus) -> Bool {
        switch (from, to) {
        case (.lobby, .active), (.lobby, .cancelled), (.active, .ended), (.active, .cancelled):
            return true
        default:
            return false
        }
    }

    static func validateTransition(from: GroupRideStatus, to: GroupRideStatus) throws {
        guard canTransition(from: from, to: to) else {
            throw GroupRideTransitionError.invalidTransition(from: from, to: to)
        }
    }

    /// The host may still edit destination/waypoints/selected alternative pre-start; once active
    /// the shared snapshot is locked and each device's own navigation session takes over local
    /// map matching and rerouting.
    static func routeSnapshotIsEditable(status: GroupRideStatus) -> Bool {
        status == .lobby
    }

    /// A rider should be publishing/consuming live locations only while the ride is active and
    /// their own membership is still joined.
    static func locationPublishingAllowed(
        rideStatus: GroupRideStatus,
        memberStatus: GroupRideMemberStatus
    ) -> Bool {
        rideStatus.isLive && memberStatus.isActive
    }

    /// No leader transfer in the MVP: the host leaving ends the ride outright — `.ended` if it
    /// was already live (participants were navigating together), `.cancelled` if it never started.
    static func statusAfterHostLeaving(currentStatus: GroupRideStatus) -> GroupRideStatus {
        currentStatus == .active ? .ended : .cancelled
    }

    // MARK: Membership transitions

    static func canTransitionMember(from: GroupRideMemberStatus, to: GroupRideMemberStatus) -> Bool {
        switch (from, to) {
        case (.joined, .left), (.joined, .removed), (.left, .joined):
            return true
        default:
            return false
        }
    }

    static func validateMemberTransition(from: GroupRideMemberStatus, to: GroupRideMemberStatus) throws {
        guard canTransitionMember(from: from, to: to) else {
            throw GroupRideMemberTransitionError.invalidTransition(from: from, to: to)
        }
    }

    // MARK: Join preconditions
    //
    // Joining an already-`.active` ride is intentionally allowed (not restricted to `.lobby`)
    // provided the invite, capacity, and ride state all remain valid — the shared route snapshot
    // and membership/capacity checks are exactly the same regardless of when the rider arrives.

    static func joinDenialReason(
        rideStatus: GroupRideStatus,
        hasValidInvite: Bool,
        maxMembers: Int,
        currentActiveMemberCount: Int,
        isAlreadyActiveMember: Bool
    ) -> GroupRideJoinDenialReason? {
        if rideStatus == .ended { return .rideEnded }
        if rideStatus == .cancelled { return .rideCancelled }
        guard hasValidInvite else { return .expired }
        if !isAlreadyActiveMember, currentActiveMemberCount >= maxMembers { return .full }
        return nil
    }
}
