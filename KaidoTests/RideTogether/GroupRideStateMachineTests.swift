@testable import Kaido
import XCTest

final class GroupRideStateMachineTests: XCTestCase {
    func testValidRideTransitions() {
        XCTAssertTrue(GroupRideStateMachine.canTransition(from: .lobby, to: .active))
        XCTAssertTrue(GroupRideStateMachine.canTransition(from: .lobby, to: .cancelled))
        XCTAssertTrue(GroupRideStateMachine.canTransition(from: .active, to: .ended))
        XCTAssertTrue(GroupRideStateMachine.canTransition(from: .active, to: .cancelled))
    }

    func testInvalidRideTransitionsAreRejected() {
        XCTAssertFalse(GroupRideStateMachine.canTransition(from: .ended, to: .active))
        XCTAssertFalse(GroupRideStateMachine.canTransition(from: .cancelled, to: .lobby))
        XCTAssertFalse(GroupRideStateMachine.canTransition(from: .active, to: .lobby))
        XCTAssertFalse(GroupRideStateMachine.canTransition(from: .lobby, to: .ended))

        XCTAssertThrowsError(try GroupRideStateMachine.validateTransition(from: .ended, to: .active)) { error in
            XCTAssertEqual(error as? GroupRideTransitionError, .invalidTransition(from: .ended, to: .active))
        }
    }

    func testRouteSnapshotOnlyEditableInLobby() {
        XCTAssertTrue(GroupRideStateMachine.routeSnapshotIsEditable(status: .lobby))
        XCTAssertFalse(GroupRideStateMachine.routeSnapshotIsEditable(status: .active))
        XCTAssertFalse(GroupRideStateMachine.routeSnapshotIsEditable(status: .ended))
    }

    func testLocationPublishingRequiresActiveRideAndJoinedMembership() {
        XCTAssertTrue(GroupRideStateMachine.locationPublishingAllowed(rideStatus: .active, memberStatus: .joined))
        XCTAssertFalse(GroupRideStateMachine.locationPublishingAllowed(rideStatus: .lobby, memberStatus: .joined))
        XCTAssertFalse(GroupRideStateMachine.locationPublishingAllowed(rideStatus: .active, memberStatus: .left))
        XCTAssertFalse(GroupRideStateMachine.locationPublishingAllowed(rideStatus: .ended, memberStatus: .joined))
    }

    func testHostLeavingEndsAnActiveRideAndCancelsALobbyRide() {
        XCTAssertEqual(GroupRideStateMachine.statusAfterHostLeaving(currentStatus: .active), .ended)
        XCTAssertEqual(GroupRideStateMachine.statusAfterHostLeaving(currentStatus: .lobby), .cancelled)
    }

    func testMemberTransitions() {
        XCTAssertTrue(GroupRideStateMachine.canTransitionMember(from: .joined, to: .left))
        XCTAssertTrue(GroupRideStateMachine.canTransitionMember(from: .joined, to: .removed))
        XCTAssertTrue(GroupRideStateMachine.canTransitionMember(from: .left, to: .joined))
        XCTAssertFalse(GroupRideStateMachine.canTransitionMember(from: .removed, to: .joined))
        XCTAssertFalse(GroupRideStateMachine.canTransitionMember(from: .left, to: .removed))
    }

    func testJoinDenialForExpiredInvite() {
        let reason = GroupRideStateMachine.joinDenialReason(
            rideStatus: .lobby,
            hasValidInvite: false,
            maxMembers: 8,
            currentActiveMemberCount: 1,
            isAlreadyActiveMember: false
        )
        XCTAssertEqual(reason, .expired)
    }

    func testJoinDenialForFullRide() {
        let reason = GroupRideStateMachine.joinDenialReason(
            rideStatus: .lobby,
            hasValidInvite: true,
            maxMembers: 2,
            currentActiveMemberCount: 2,
            isAlreadyActiveMember: false
        )
        XCTAssertEqual(reason, .full)
    }

    func testJoinAllowedForAlreadyActiveMemberEvenWhenFull() {
        let reason = GroupRideStateMachine.joinDenialReason(
            rideStatus: .active,
            hasValidInvite: true,
            maxMembers: 2,
            currentActiveMemberCount: 2,
            isAlreadyActiveMember: true
        )
        XCTAssertNil(reason)
    }

    func testJoinDenialForEndedAndCancelledRides() {
        XCTAssertEqual(
            GroupRideStateMachine.joinDenialReason(
                rideStatus: .ended, hasValidInvite: true, maxMembers: 8,
                currentActiveMemberCount: 1, isAlreadyActiveMember: false
            ),
            .rideEnded
        )
        XCTAssertEqual(
            GroupRideStateMachine.joinDenialReason(
                rideStatus: .cancelled, hasValidInvite: true, maxMembers: 8,
                currentActiveMemberCount: 1, isAlreadyActiveMember: false
            ),
            .rideCancelled
        )
    }

    func testJoiningAnActiveRideIsAllowedWhenValid() {
        let reason = GroupRideStateMachine.joinDenialReason(
            rideStatus: .active,
            hasValidInvite: true,
            maxMembers: 8,
            currentActiveMemberCount: 2,
            isAlreadyActiveMember: false
        )
        XCTAssertNil(reason)
    }
}
