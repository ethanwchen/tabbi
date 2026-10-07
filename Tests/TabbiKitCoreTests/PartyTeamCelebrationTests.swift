import XCTest
import TabbiKitCore

/// The message shown when a shared session runs to its end: who it
/// thanks, what was earned, and how long it stays up.
final class PartyTeamCelebrationTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func completion(minutes: Int = 25, friends: Int = 2) -> PartySessionCompletion {
        PartySessionCompletion(method: "pomodoro", joinedAt: start,
                               endedAt: start.addingTimeInterval(TimeInterval(minutes * 60)),
                               friendCount: friends, hostName: "Maya")
    }

    func testItThanksTheTeamWithThePointsEarned() {
        let celebration = PartyTeamCelebration(completion: completion(), points: 45, petName: "Miso", date: start)
        XCTAssertEqual(celebration.title, "Great job, team!")
        XCTAssertEqual(celebration.detail, "+45 points for Miso · 25 min with 2 friends")
    }

    func testItAdaptsToCompanyAndMissingDetails() {
        let alone = PartyTeamCelebration(completion: completion(friends: 0), points: 1, petName: "  ", date: start)
        XCTAssertEqual(alone.title, "Great job!")
        XCTAssertEqual(alone.detail, "+1 point · 25 min on your own")

        let unpaid = PartyTeamCelebration(completion: completion(minutes: 3, friends: 1), points: 0,
                                          petName: "Miso", date: start)
        XCTAssertEqual(unpaid.detail, "3 min with 1 friend", "No points line when nothing was earned")
    }

    func testItShowsForAFewSecondsOnly() {
        let celebration = PartyTeamCelebration(completion: completion(), points: 45, date: start)
        XCTAssertTrue(celebration.isShowing(at: start))
        XCTAssertTrue(celebration.isShowing(at: start.addingTimeInterval(PartyTeamCelebration.displayDuration - 1)))
        XCTAssertFalse(celebration.isShowing(at: celebration.endsAt))
        XCTAssertFalse(celebration.isShowing(at: start.addingTimeInterval(-1)))
    }
}
