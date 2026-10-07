import XCTest
import TabbiKitCore

/// A Party shared session that runs to its end pays each member who stayed
/// for it a fair bonus over a solo session, and only once.
final class PartySessionRewardTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func session(minutes: Int = 25, friends: Int = 2, startedAt: Date? = nil) -> ProvidedPartySession {
        let startedAt = startedAt ?? start
        return ProvidedPartySession(method: "pomodoro", startedAt: startedAt,
                                    endsAt: startedAt.addingTimeInterval(TimeInterval(minutes * 60)),
                                    friendCount: friends, hostName: "Maya")
    }

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    // MARK: Points

    func testASharedSessionPaysAFairBonusOverASoloOne() {
        let solo = PetPointsRules.points(forMinutes: 25, completed: true)
        XCTAssertEqual(PetPointsRules.sharedPoints(forMinutes: 25, friends: 0), solo, "Alone, it pays like solo")
        XCTAssertEqual(PetPointsRules.sharedPoints(forMinutes: 25, friends: 1), solo + 5)
        XCTAssertEqual(PetPointsRules.sharedPoints(forMinutes: 25, friends: 2), solo + 10)
        XCTAssertEqual(PetPointsRules.sharedPoints(forMinutes: 25, friends: 7), solo + PetPointsRules.maxSharedBonus,
                       "The team bonus is capped")
        XCTAssertEqual(PetPointsRules.sharedPoints(forMinutes: 3, friends: 3), 0, "Too short a stay earns nothing")
    }

    func testTheClosetCreditsTheSharedSessionToTheLedger() throws {
        var closet = PetCloset(save: PetSave(profile: .starter(.cat)))
        let completion = PartySessionCompletion(method: "pomodoro", joinedAt: at(0), endedAt: at(25), friendCount: 2)
        let award = try XCTUnwrap(closet.credit(completion))
        XCTAssertEqual(award.points, 45)
        XCTAssertEqual(award.minutes, 25)
        XCTAssertEqual(award.completedSessions, 1)
        XCTAssertEqual(closet.balance, 45)

        let short = PartySessionCompletion(method: "pomodoro", joinedAt: at(0), endedAt: at(2), friendCount: 2)
        XCTAssertNil(closet.credit(short))
        XCTAssertEqual(closet.balance, 45)
    }

    // MARK: Completion

    func testASessionThatRunsToItsEndCompletesOnce() throws {
        var tracker = PartySessionTracker()
        XCTAssertNil(tracker.observe(session(), at: at(0)))
        XCTAssertNil(tracker.observe(session(friends: 3), at: at(10)))
        XCTAssertNil(tracker.observe(session(friends: 1), at: at(20)))
        let done = try XCTUnwrap(tracker.observe(nil, at: at(25)))
        XCTAssertEqual(done.minutes, 25)
        XCTAssertEqual(done.friendCount, 3, "The most friends who studied along at once")
        XCTAssertEqual(done.hostName, "Maya")
        XCTAssertNil(tracker.observe(nil, at: at(26)), "Paid once")
    }

    func testEndingEarlyOrSteppingOutEarnsNothing() {
        var tracker = PartySessionTracker()
        _ = tracker.observe(session(), at: at(0))
        XCTAssertNil(tracker.observe(nil, at: at(12)), "The host ended it, or I stepped out")
        XCTAssertNil(tracker.observe(nil, at: at(25)))
    }

    func testALateJoinerIsCreditedFromWhenTheyJoined() throws {
        var tracker = PartySessionTracker()
        _ = tracker.observe(session(), at: at(10))
        let done = try XCTUnwrap(tracker.observe(nil, at: at(25)))
        XCTAssertEqual(done.minutes, 15)
    }

    func testRejoiningCountsOnlyTheTimeBackIn() throws {
        var tracker = PartySessionTracker()
        _ = tracker.observe(session(), at: at(0))
        _ = tracker.observe(nil, at: at(5))
        _ = tracker.observe(session(), at: at(15))
        let done = try XCTUnwrap(tracker.observe(nil, at: at(25)))
        XCTAssertEqual(done.minutes, 10)
    }

    func testANewSessionRightAfterTheLastStillPaysTheLast() throws {
        var tracker = PartySessionTracker()
        _ = tracker.observe(session(), at: at(0))
        let next = session(startedAt: at(25))
        let done = try XCTUnwrap(tracker.observe(next, at: at(25)))
        XCTAssertEqual(done.minutes, 25)
        XCTAssertNil(tracker.observe(nil, at: at(30)), "The next one was cut short")
    }

    func testTheCompletionIsLoggedAsAFocusStretch() throws {
        let completion = PartySessionCompletion(method: "pomodoro", joinedAt: at(0), endedAt: at(25), friendCount: 2)
        let record = try XCTUnwrap(completion.activityRecord(source: .party))
        XCTAssertEqual(record.kind, .focusCompleted)
        XCTAssertEqual(record.source, .party)
        XCTAssertEqual(record.quantity, 25)
        XCTAssertEqual(record.unit, .minutes)
        XCTAssertEqual(record.metadata[ActivityMetadata.method], "pomodoro")
        XCTAssertEqual(record.metadata[ActivityMetadata.outcome], "completed")
        XCTAssertEqual(record.metadata[PartySessionCompletion.friendsKey], "2")
        let tiny = PartySessionCompletion(method: "pomodoro", joinedAt: at(0), endedAt: at(0.5), friendCount: 2)
        XCTAssertNil(tiny.activityRecord(source: .party))
    }
}
