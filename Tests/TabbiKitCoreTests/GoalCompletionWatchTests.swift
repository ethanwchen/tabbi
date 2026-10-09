import XCTest
@testable import TabbiKitCore

/// When a goal for today counts as just reached, which crowns the pet:
/// only on the change from work left to done, never at launch.
final class GoalCompletionWatchTests: XCTestCase {
    private func reviews(_ completed: Int, of target: Int, source: ModuleID = .anki) -> ProgressItem {
        ProgressItem(id: "reviews", source: source, title: "Anki reviews", completed: completed, target: target,
                     unit: "cards")
    }

    func testAGoalIsReachedOnceWhenItsLastWorkIsDone() {
        var watch = GoalCompletionWatch()
        XCTAssertEqual(watch.reached(in: [reviews(10, of: 40)]), [])
        XCTAssertEqual(watch.reached(in: [reviews(39, of: 40)]), [])
        XCTAssertEqual(watch.reached(in: [reviews(40, of: 40)]), [reviews(40, of: 40)])
        XCTAssertEqual(watch.reached(in: [reviews(40, of: 40)]), [], "still done is no new news")
        XCTAssertEqual(watch.reached(in: [reviews(45, of: 45)]), [], "extra work on a done goal")
    }

    func testAGoalAlreadyDoneAtLaunchOrWhenItAppearsIsNotReached() {
        var watch = GoalCompletionWatch()
        XCTAssertEqual(watch.reached(in: [reviews(40, of: 40)]), [], "the first look sets the baseline")

        var later = GoalCompletionWatch()
        XCTAssertEqual(later.reached(in: []), [])
        XCTAssertEqual(later.reached(in: [reviews(40, of: 40)]), [], "a module switched on with its goal done")
    }

    func testAGoalOfNothingIsNeverReached() {
        var watch = GoalCompletionWatch()
        XCTAssertEqual(watch.reached(in: [reviews(0, of: 0)]), [])
        XCTAssertEqual(watch.reached(in: [reviews(0, of: 0)]), [])
    }

    func testTheNextDaysGoalCanBeReachedAgain() {
        var watch = GoalCompletionWatch()
        _ = watch.reached(in: [reviews(5, of: 40)])
        XCTAssertEqual(watch.reached(in: [reviews(40, of: 40)]).count, 1)
        // Anki rolls over: new cards are due.
        XCTAssertEqual(watch.reached(in: [reviews(0, of: 30)]), [])
        XCTAssertEqual(watch.reached(in: [reviews(30, of: 30)]).count, 1)
    }

    func testGoalsAreTrackedPerModule() {
        var watch = GoalCompletionWatch()
        let focus = ProgressItem(id: "reviews", source: .study, title: "Focus time", completed: 50, target: 60,
                                 unit: "min", waitsForStart: true)
        _ = watch.reached(in: [reviews(40, of: 40), focus])
        var done = focus
        done.completed = 60
        XCTAssertEqual(watch.reached(in: [reviews(40, of: 40), done]), [done])
    }

    func testAGoalThatDisappearsAndComesBackDoneIsNotReached() {
        var watch = GoalCompletionWatch()
        _ = watch.reached(in: [reviews(10, of: 40)])
        _ = watch.reached(in: [])
        XCTAssertEqual(watch.reached(in: [reviews(40, of: 40)]), [], "its module was off while it was done")
    }
}
