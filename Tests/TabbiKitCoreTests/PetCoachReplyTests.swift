import XCTest
import TabbiKitCore

final class PetCoachReplyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testEveryBubbleOffersSnoozeLast() {
        for kind in PetCoachNudgeKind.allCases {
            XCTAssertEqual(kind.replies.last, .snooze, "\(kind)")
            XCTAssertEqual(kind.replies.filter { $0 == .snooze }.count, 1, "\(kind)")
        }
    }

    func testBubblesOfferTheRightWayOut() {
        XCTAssertEqual(PetCoachNudgeKind.distraction.replies.first, .backToIt)
        XCTAssertEqual(PetCoachNudgeKind.offerPause.replies.first, .pause)
        XCTAssertEqual(PetCoachNudgeKind.idleCheck.replies.first, .stillHere)
        XCTAssertEqual(PetCoachNudgeKind.autoPause.replies, [.resume, .snooze])
    }

    func testOnlyPauseAndResumeTouchTheTimer() {
        XCTAssertEqual(PetCoachReply.allCases.filter(\.pausesTimer), [.pause])
        XCTAssertEqual(PetCoachReply.allCases.filter(\.resumesTimer), [.resume])
    }

    func testSnoozeReplyQuietsTheCoachForFifteenMinutes() {
        var coach = PetCoach()
        coach.handle(.snooze, at: t0)
        XCTAssertTrue(coach.isSnoozed(at: t0.addingTimeInterval(14 * 60)))
        XCTAssertFalse(coach.isSnoozed(at: t0.addingTimeInterval(15 * 60)))
    }

    func testOtherRepliesLeaveTheCoachAwake() {
        for reply in PetCoachReply.allCases where reply != .snooze {
            var coach = PetCoach()
            coach.handle(reply, at: t0)
            XCTAssertFalse(coach.isSnoozed(at: t0), "\(reply)")
        }
    }

    func testButtonTitlesFitASmallBubble() {
        for reply in PetCoachReply.allCases {
            XCTAssertLessThanOrEqual(reply.title.count, 14, "\(reply)")
        }
    }
}
