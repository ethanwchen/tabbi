import XCTest
@testable import NotchKitCore

final class StudyCardFeedTests: XCTestCase {
    private func cards(_ id: String, _ completed: Int, unit: String = "cards") -> ProgressItem {
        ProgressItem(id: id, source: ModuleID("unset"), title: id, completed: completed, target: completed + 50, unit: unit)
    }

    func testNoCardGoalMeansNoFeed() {
        XCTAssertNil(ProviderSnapshot().cardsReviewedToday(excluding: .study))
        let questions = ProviderSnapshot([(.anki, ModuleProvision(progress: [cards("qbank", 40, unit: "questions")]))])
        XCTAssertNil(questions.cardsReviewedToday(excluding: .study))
    }

    func testCardGoalsFromOtherModulesAddUp() {
        let snapshot = ProviderSnapshot([
            (.anki, ModuleProvision(progress: [cards("reviews", 112), cards("qbank", 9, unit: "questions")])),
            (ModuleID("other"), ModuleProvision(progress: [cards("deck", 8)])),
            (.study, ModuleProvision(progress: [cards("own", 500)])),
        ])
        XCTAssertEqual(snapshot.cardsReviewedToday(excluding: .study), 120)
    }

    func testFeedDrivesASprintToItsGoal() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        func feed(_ reviewed: Int) -> Int? {
            ProviderSnapshot([(.anki, ModuleProvision(progress: [cards("reviews", reviewed)]))])
                .cardsReviewedToday(excluding: .study)
        }
        var session = StudySession(method: .ankiSprint(cards: 30))
        session.start(at: t0)
        session.recordReviewedToday(feed(200)!, at: t0)
        session.recordReviewedToday(feed(215)!, at: t0.addingTimeInterval(300))
        XCTAssertEqual(session.cardsDone, 15)
        let ended = session.recordReviewedToday(feed(232)!, at: t0.addingTimeInterval(600))
        XCTAssertEqual(ended.map(\.cards), [32], "every card answered counts, even past the goal")
        XCTAssertTrue(session.phase.isBreak)
    }
}
