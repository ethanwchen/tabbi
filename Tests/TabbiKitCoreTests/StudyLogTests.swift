import XCTest
import TabbiKitCore

final class StudyLogTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    private func record(
        _ phase: StudyPhaseKind = .focus, minutes: Double, outcome: StudyPhaseOutcome = .completed,
        method: StudyMethodKind = .pomodoro, startingAt start: Double = 0, cards: Int? = nil
    ) -> StudyPhaseRecord {
        StudyPhaseRecord(method: method, phase: phase, startedAt: at(start), endedAt: at(start + minutes),
                         activeDuration: minutes * 60, outcome: outcome, cards: cards)
    }

    func testCompletedPomodoroEarnsMinutesPlusBonus() {
        var log = StudyLog()
        let added = log.record([record(minutes: 25)])
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(added[0].minutes, 25)
        XCTAssertTrue(added[0].completed)
        XCTAssertEqual(added[0].points, PetPointsRules.points(forMinutes: 25, completed: true))
        XCTAssertEqual(log.totalPoints, 35)
    }

    func testBreaksAndSubMinuteStretchesAreNotLogged() {
        var log = StudyLog()
        let added = log.record([record(.shortBreak, minutes: 5), record(.longBreak, minutes: 15),
                                record(minutes: 0.9, outcome: .skipped)])
        XCTAssertTrue(added.isEmpty)
        XCTAssertTrue(log.entries.isEmpty)
    }

    func testQuestionReviewCountsAsStudy() {
        var log = StudyLog()
        log.record([record(.review, minutes: 30, method: .questionBlock)])
        XCTAssertEqual(log.entries.map(\.minutes), [30])
    }

    func testSkippedStretchIsLoggedAsNotCompletedWithoutBonus() {
        var log = StudyLog()
        let entry = log.record([record(minutes: 30.7, outcome: .skipped)])[0]
        XCTAssertEqual(entry.minutes, 30)
        XCTAssertFalse(entry.completed)
        XCTAssertEqual(entry.points, 30)
    }

    func testStoppedFlowtimeCountsAsCompleted() {
        var log = StudyLog()
        let entry = log.record([record(minutes: 40, outcome: .stopped, method: .flowtime)])[0]
        XCTAssertTrue(entry.completed)
        XCTAssertEqual(entry.points, 50)
    }

    func testShortStretchIsLoggedButEarnsNothing() {
        var log = StudyLog()
        log.record([record(minutes: 3, outcome: .abandoned)])
        XCTAssertEqual(log.entries.count, 1)
        XCTAssertEqual(log.entries[0].points, 0)
        XCTAssertEqual(log.totalPoints, 0)
    }

    func testLogPointsMatchWhatThePetLedgerPays() {
        var log = StudyLog()
        log.record([record(minutes: 25), record(minutes: 10, outcome: .skipped, startingAt: 30),
                    record(minutes: 3, outcome: .abandoned, startingAt: 45)])
        var ledger = PetPointsLedger()
        for entry in log.entries {
            ledger.recordStudy(minutes: entry.minutes, completed: entry.completed)
        }
        XCTAssertEqual(ledger.earned, 45)
        XCTAssertEqual(log.totalPoints, ledger.earned)
    }

    func testSessionLogFlowsIntoStudyLog() {
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)
        session.advance(to: at(31))
        var log = StudyLog()
        log.record(session.takeLog())
        XCTAssertEqual(log.entries.count, 1, "the running break hasn't ended yet")
        XCTAssertEqual(log.entries[0].minutes, 25)
        XCTAssertTrue(log.entries[0].completed)
    }

    func testSprintKeepsItsCards() {
        var log = StudyLog()
        let entry = log.record([record(minutes: 12, method: .ankiSprint, cards: 100)])[0]
        XCTAssertEqual(entry.cards, 100)
    }

    func testDaySummaryCountsOnlyThatDay() {
        var log = StudyLog()
        let dayStart = utc.startOfDay(for: t0)
        let minutesIntoDay = t0.timeIntervalSince(dayStart) / 60
        log.record([
            record(minutes: 25, startingAt: -minutesIntoDay - 60),
            record(minutes: 25),
            record(minutes: 12, outcome: .skipped, startingAt: 30),
        ])
        let today = log.summary(on: t0, calendar: utc)
        XCTAssertEqual(today, StudyDayTally(minutes: 37, sessions: 1, points: 47))
        let yesterday = log.summary(on: dayStart.addingTimeInterval(-3600), calendar: utc)
        XCTAssertEqual(yesterday.minutes, 25)
    }

    func testDayTallyReachesTheSharedSnapshotForWrapUp() {
        var log = StudyLog()
        log.record([record(minutes: 25), record(minutes: 10, outcome: .skipped, startingAt: 30)])
        let tally = log.summary(on: t0, calendar: utc)
        let other = StudyDayTally(minutes: 20, sessions: 1, points: 25)
        let snapshot = ProviderSnapshot([
            (module: .study, provision: ModuleProvision(study: tally)),
            (module: .planner, provision: ModuleProvision()),
            (module: .anki, provision: ModuleProvision(study: other)),
        ])
        XCTAssertEqual(tally.minutes, 35)
        XCTAssertEqual(snapshot.study, StudyDayTally(minutes: 55, sessions: 2, points: tally.points + 25))
        XCTAssertNil(ProviderSnapshot([(module: .planner, provision: ModuleProvision())]).study)
    }

    func testLogKeepsOnlyTheNewestEntries() {
        var log = StudyLog()
        let records = (0..<(StudyLog.capacity + 5)).map { record(minutes: 1, startingAt: Double($0) * 2) }
        log.record(records)
        XCTAssertEqual(log.entries.count, StudyLog.capacity)
        XCTAssertEqual(log.entries.last?.endedAt, records.last?.endedAt)
    }

    func testRoundTripsThroughDisk() throws {
        var log = StudyLog()
        log.record([record(minutes: 25)])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("log.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertNil(try StudyLog.load(from: url))
        try log.write(to: url)
        XCTAssertEqual(try StudyLog.load(from: url), log)
    }

    func testDecodingClampsCorruptValues() throws {
        let json = """
        {"entries":[{"id":"\(UUID().uuidString)","method":"pomodoro","startedAt":0,"endedAt":60,
        "minutes":-4,"completed":true,"cards":-2,"points":-10}]}
        """
        let log = try JSONDecoder().decode(StudyLog.self, from: Data(json.utf8))
        XCTAssertEqual(log.entries[0].minutes, 0)
        XCTAssertEqual(log.entries[0].cards, 0)
        XCTAssertEqual(log.entries[0].points, 0)
        XCTAssertEqual(log.totalPoints, 0)
    }

    func testDecodingIgnoresTheRetiredUncreditedList() throws {
        let entry = StudyLogEntry(StudyPhaseRecord(
            method: .pomodoro, phase: .focus, startedAt: t0, endedAt: at(25),
            activeDuration: 25 * 60, outcome: .completed, cards: nil))!
        let old = try JSONEncoder().encode(["entries": [entry], "uncredited": [entry]])
        let log = try JSONDecoder().decode(StudyLog.self, from: old)
        XCTAssertEqual(log, StudyLog(entries: [entry]))
    }
}
