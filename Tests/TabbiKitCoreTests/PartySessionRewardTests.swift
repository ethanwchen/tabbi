import XCTest
import TabbiKitCore

/// A Party shared session pays every member (host or not) for the time
/// they studied in it, once: a fair team bonus for staying to the end, and
/// the minutes studied for a stay cut short.
final class PartySessionRewardTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func session(minutes: Int = 25, friends: Int = 2, startedAt: Date? = nil,
                         hostName: String? = "Maya") -> ProvidedPartySession {
        let startedAt = startedAt ?? start
        return ProvidedPartySession(method: "pomodoro", startedAt: startedAt,
                                    endsAt: startedAt.addingTimeInterval(TimeInterval(minutes * 60)),
                                    friendCount: friends, hostName: hostName)
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

    func testAStayCutShortPaysTheMinutesStudiedWithoutBonuses() {
        XCTAssertEqual(PetPointsRules.sharedPoints(forMinutes: 12, friends: 2, finished: false), 12)
        XCTAssertEqual(PetPointsRules.sharedPoints(forMinutes: 30, friends: 3, finished: false),
                       PetPointsRules.points(forMinutes: 30, completed: false), "Like a solo session cut short")
        XCTAssertEqual(PetPointsRules.sharedPoints(forMinutes: 4, friends: 3, finished: false), 0)
    }

    func testSteppingOutAndBackInIsNeverWorthMoreThanStaying() {
        let stayed = PetPointsRules.sharedPoints(forMinutes: 25, friends: 3)
        for leftAt in stride(from: 5, through: 20, by: 5) {
            let before = PetPointsRules.sharedPoints(forMinutes: leftAt, friends: 3, finished: false)
            let after = PetPointsRules.sharedPoints(forMinutes: 25 - leftAt, friends: 3)
            XCTAssertLessThanOrEqual(before + after, stayed, "Leaving at minute \(leftAt)")
        }
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

    func testTheClosetCreditsAStayCutShort() throws {
        var closet = PetCloset(save: PetSave(profile: .starter(.cat)))
        let left = PartySessionCompletion(method: "pomodoro", joinedAt: at(0), endedAt: at(15), friendCount: 2,
                                          finished: false)
        let award = try XCTUnwrap(closet.credit(left))
        XCTAssertEqual(award.points, 15)
        XCTAssertEqual(award.minutes, 15)
        XCTAssertEqual(award.completedSessions, 0, "Not a finished session")
        XCTAssertEqual(closet.balance, 15)
    }

    func testTheClosetDoesNotPayPartysLogRecordsAgain() throws {
        var closet = PetCloset(save: PetSave(profile: .starter(.cat)))
        let left = PartySessionCompletion(method: "pomodoro", joinedAt: at(0), endedAt: at(15), friendCount: 2,
                                          finished: false)
        XCTAssertNil(closet.credit(try XCTUnwrap(left.activityRecord(source: .party))),
                     "Party pays its stays itself, with the team bonus")
        XCTAssertEqual(closet.balance, 0)
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

    func testSteppingOutOrEndingEarlyReportsTheTimeStudied() throws {
        var tracker = PartySessionTracker()
        _ = tracker.observe(session(), at: at(0))
        let left = try XCTUnwrap(tracker.observe(nil, at: at(12)), "The host ended it, or I stepped out")
        XCTAssertFalse(left.finished)
        XCTAssertEqual(left.minutes, 12)
        XCTAssertEqual(left.friendCount, 2)
        XCTAssertNil(tracker.observe(nil, at: at(25)), "Reported once")
    }

    func testTheHostAndEveryMemberArePaidAlike() throws {
        for host in [nil, "Maya"] {
            var tracker = PartySessionTracker()
            _ = tracker.observe(session(hostName: host), at: at(0))
            let done = try XCTUnwrap(tracker.observe(nil, at: at(25)))
            XCTAssertTrue(done.finished)
            XCTAssertEqual(done.hostName, host)
            var closet = PetCloset(save: PetSave(profile: .starter(.cat)))
            XCTAssertEqual(closet.credit(done)?.points, PetPointsRules.sharedPoints(forMinutes: 25, friends: 2))
        }
    }

    func testALateJoinerIsCreditedFromWhenTheyJoined() throws {
        var tracker = PartySessionTracker()
        _ = tracker.observe(session(), at: at(10))
        let done = try XCTUnwrap(tracker.observe(nil, at: at(25)))
        XCTAssertEqual(done.minutes, 15)
        XCTAssertTrue(done.finished, "A late joiner who stays to the end finished it")
        var closet = PetCloset(save: PetSave(profile: .starter(.cat)))
        XCTAssertEqual(closet.credit(done)?.points, PetPointsRules.sharedPoints(forMinutes: 15, friends: 2),
                       "With the team bonus")
    }

    func testRejoiningCountsOnlyTheTimeIn() throws {
        var tracker = PartySessionTracker()
        _ = tracker.observe(session(), at: at(0))
        let left = try XCTUnwrap(tracker.observe(nil, at: at(5)))
        XCTAssertEqual(left.minutes, 5)
        XCTAssertFalse(left.finished)
        XCTAssertNil(tracker.observe(session(), at: at(15)))
        let done = try XCTUnwrap(tracker.observe(nil, at: at(25)))
        XCTAssertEqual(done.minutes, 10)
        XCTAssertTrue(done.finished)
    }

    func testANewSessionRightAfterTheLastStillPaysTheLast() throws {
        var tracker = PartySessionTracker()
        _ = tracker.observe(session(), at: at(0))
        let next = session(startedAt: at(25))
        let done = try XCTUnwrap(tracker.observe(next, at: at(25)))
        XCTAssertEqual(done.minutes, 25)
        XCTAssertTrue(done.finished)
        let cut = try XCTUnwrap(tracker.observe(nil, at: at(30)), "The next one was cut short")
        XCTAssertFalse(cut.finished)
        XCTAssertEqual(cut.minutes, 5)
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
        let left = PartySessionCompletion(method: "pomodoro", joinedAt: at(0), endedAt: at(12), friendCount: 2,
                                          finished: false)
        let leftRecord = try XCTUnwrap(left.activityRecord(source: .party))
        XCTAssertEqual(leftRecord.quantity, 12, "The minutes studied still count")
        XCTAssertEqual(leftRecord.metadata[ActivityMetadata.outcome], "skipped", "But not as a finished session")
    }
}
