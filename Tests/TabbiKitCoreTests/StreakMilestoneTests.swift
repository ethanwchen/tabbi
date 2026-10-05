import XCTest
import TabbiKitCore

final class StreakMilestoneTests: XCTestCase {
    func testOnlyRoundLengthsAreMilestones() {
        let firstYear = (0...365).filter(StreakMilestone.isMilestone)
        XCTAssertEqual(firstYear, [7, 14, 30, 50, 100, 200, 365])
        XCTAssertFalse(StreakMilestone.isMilestone(-7))
    }

    func testPastAYearEveryHundredDaysAndEveryYearCount() {
        XCTAssertTrue(StreakMilestone.isMilestone(400))
        XCTAssertTrue(StreakMilestone.isMilestone(730))
        XCTAssertFalse(StreakMilestone.isMilestone(366))
        XCTAssertFalse(StreakMilestone.isMilestone(450))
    }

    func testGrowingOntoAMilestoneReachesIt() {
        XCTAssertEqual(StreakMilestone.reached(from: 6, to: 7), 7)
        XCTAssertEqual(StreakMilestone.reached(from: 364, to: 365), 365)
        XCTAssertNil(StreakMilestone.reached(from: 7, to: 8))
    }

    func testNoBaselineHoldingOrBreakingReachesNothing() {
        XCTAssertNil(StreakMilestone.reached(from: nil, to: 7), "the first look only sets the baseline")
        XCTAssertNil(StreakMilestone.reached(from: 7, to: 7), "a streak still alive from yesterday")
        XCTAssertNil(StreakMilestone.reached(from: 30, to: 0), "a broken streak")
    }

    func testAJumpPastSeveralMilestonesCountsTheLargestOnce() {
        XCTAssertEqual(StreakMilestone.reached(from: 5, to: 16), 14)
        XCTAssertEqual(StreakMilestone.reached(from: 0, to: 9), 7)
        XCTAssertNil(StreakMilestone.reached(from: 0, to: 6))
    }
}
