import XCTest
import TabbiKitCore

final class PetCoachStrollTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    /// 100 pt at 50 pt/s: two seconds each way, ten seconds of talking.
    private func stroll() -> PetCoachStroll {
        PetCoachStroll(startedAt: t0, distance: 100, speed: 50, talkDuration: 10)
    }

    func testUnansweredStrollWalksOutTalksAndWalksBack() {
        let stroll = stroll()
        XCTAssertEqual(stroll.phase(at: at(1)), .walkingOut)
        XCTAssertEqual(stroll.phase(at: at(2)), .talking)
        XCTAssertEqual(stroll.phase(at: at(11.9)), .talking)
        XCTAssertEqual(stroll.phase(at: at(12)), .walkingBack)
        XCTAssertEqual(stroll.phase(at: at(14)), .finished)
        XCTAssertEqual(stroll.endsAt, at(14))
    }

    func testOffsetMovesAtWalkingSpeedAndHoldsWhileTalking() {
        let stroll = stroll()
        XCTAssertEqual(stroll.offset(at: at(-1)), 0)
        XCTAssertEqual(stroll.offset(at: at(1)), 50, accuracy: 0.001)
        XCTAssertEqual(stroll.offset(at: at(5)), 100, accuracy: 0.001)
        XCTAssertEqual(stroll.offset(at: at(13)), 50, accuracy: 0.001)
        XCTAssertEqual(stroll.offset(at: at(20)), 0)
    }

    func testPetFacesAwayGoingOutAndTowardTheNotchComingBack() {
        let stroll = stroll()
        XCTAssertEqual(stroll.heading(at: at(1)), .awayFromNotch)
        XCTAssertEqual(stroll.heading(at: at(5)), .awayFromNotch)
        XCTAssertEqual(stroll.heading(at: at(13)), .towardNotch)
    }

    func testBubbleShowsOnlyWhileStandingStill() {
        let stroll = stroll()
        XCTAssertFalse(stroll.showsBubble(at: at(1)))
        XCTAssertTrue(stroll.showsBubble(at: at(3)))
        XCTAssertFalse(stroll.showsBubble(at: at(13)))
    }

    func testDismissingWhileTalkingSendsThePetHomeAtOnce() {
        var stroll = stroll()
        stroll.dismiss(at: at(4))
        XCTAssertEqual(stroll.phase(at: at(4)), .walkingBack)
        XCTAssertFalse(stroll.showsBubble(at: at(4)))
        XCTAssertEqual(stroll.endsAt, at(6))
    }

    func testDismissingMidWalkTurnsAroundWhereThePetStands() {
        var stroll = stroll()
        stroll.dismiss(at: at(1))
        XCTAssertEqual(stroll.phase(at: at(1.5)), .walkingBack)
        XCTAssertEqual(stroll.offset(at: at(1.5)), 25, accuracy: 0.001)
        XCTAssertEqual(stroll.endsAt, at(2))
        XCTAssertFalse(stroll.showsBubble(at: at(1.5)))
    }

    func testOnlyTheFirstDismissalCounts() {
        var stroll = stroll()
        stroll.dismiss(at: at(4))
        stroll.dismiss(at: at(9))
        XCTAssertEqual(stroll.dismissedAt, at(4))
    }

    func testDismissingAfterTheBubbleTimedOutChangesNothing() {
        var stroll = stroll()
        stroll.dismiss(at: at(13))
        XCTAssertEqual(stroll.turnsBackAt, at(12))
        XCTAssertEqual(stroll.endsAt, at(14))
    }

    func testDefaultStrollIsShortAndReadable() {
        let stroll = PetCoachStroll(startedAt: t0)
        XCTAssertLessThanOrEqual(stroll.walkDuration, 2)
        XCTAssertGreaterThanOrEqual(stroll.talkDuration, 8)
    }
}
