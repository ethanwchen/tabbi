import XCTest
import TabbiKitCore

final class StudyTimerFormatTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    func testClockAddsAnHourFieldOnlyWhenNeeded() {
        XCTAssertEqual(StudyTimerFormat.clock(245), "4:05")
        XCTAssertEqual(StudyTimerFormat.clock(52 * 60), "52:00")
        XCTAssertEqual(StudyTimerFormat.clock(90 * 60), "1:30:00")
        XCTAssertEqual(StudyTimerFormat.clock(0.2), "0:01")
        XCTAssertEqual(StudyTimerFormat.clock(-5), "0:00")
        XCTAssertEqual(StudyTimerFormat.clock(.nan), "0:00")
        XCTAssertEqual(StudyTimerFormat.clock(.infinity), "0:00")
    }

    func testTimedFocusCountsDown() {
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)
        let readout = StudyTimerFormat.readout(session, at: at(10))
        XCTAssertEqual(readout, StudyDialReadout(value: "15:00", caption: "Focus", countsDown: true))

        session.pause(at: at(10))
        XCTAssertEqual(StudyTimerFormat.readout(session, at: at(30)).caption, "Focus · Paused")
    }

    func testFlowtimeCountsUp() {
        var session = StudySession(method: .flowtime)
        XCTAssertEqual(StudyTimerFormat.readout(session, at: t0),
                       StudyDialReadout(value: "0:00", caption: "Flow", countsDown: false))
        session.start(at: t0)
        XCTAssertEqual(StudyTimerFormat.readout(session, at: at(70)),
                       StudyDialReadout(value: "1:10:00", caption: "In flow", countsDown: false))
    }

    func testSprintShowsCardsAgainstTheGoal() {
        var session = StudySession(method: .ankiSprint(cards: 50))
        session.start(at: t0)
        session.recordReviewedToday(10, at: t0)
        session.recordReviewedToday(22, at: at(5))
        XCTAssertEqual(StudyTimerFormat.readout(session, at: at(5)),
                       StudyDialReadout(value: "12", caption: "of 50 cards", countsDown: false))
    }

    func testBreaksAreNamedByKind() {
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)
        session.advance(to: at(25))
        XCTAssertEqual(session.phase, .shortBreak)
        XCTAssertEqual(StudyTimerFormat.readout(session, at: at(26)).caption, "Break")
        XCTAssertEqual(StudyTimerFormat.phaseName(.longBreak, method: .pomodoro), "Long break")
        XCTAssertEqual(StudyTimerFormat.phaseName(.review, method: .questionBlock), "Review")
        XCTAssertEqual(StudyTimerFormat.phaseName(.focus, method: .ankiSprint()), "Sprint")
    }

    func testRoundLabelFollowsTheLongBreakCycle() {
        var session = StudySession(method: .pomodoro)
        XCTAssertEqual(StudyTimerFormat.roundLabel(session), "Round 1 of 4")
        session.start(at: t0)
        session.advance(to: at(25))
        // On the break after round 1, it still reads round 1.
        XCTAssertEqual(StudyTimerFormat.roundLabel(session), "Round 1 of 4")
        session.advance(to: at(30))
        XCTAssertEqual(StudyTimerFormat.roundLabel(session), "Round 2 of 4")
    }

    func testRoundLabelWithoutALongBreakCountsRoundsDone() {
        var session = StudySession(method: .fiftyTwoSeventeen)
        XCTAssertNil(StudyTimerFormat.roundLabel(session))
        session.start(at: t0)
        session.advance(to: at(52))
        XCTAssertEqual(StudyTimerFormat.roundLabel(session), "1 round done")
    }

    func testPrimaryActionMatchesState() {
        var pomodoro = StudySession(method: .pomodoro)
        XCTAssertEqual(StudyTimerFormat.primaryAction(pomodoro), "Start focus")
        pomodoro.start(at: t0)
        XCTAssertEqual(StudyTimerFormat.primaryAction(pomodoro), "Pause")
        pomodoro.pause(at: at(1))
        XCTAssertEqual(StudyTimerFormat.primaryAction(pomodoro), "Resume")

        var flow = StudySession(method: .flowtime)
        flow.start(at: t0)
        XCTAssertEqual(StudyTimerFormat.primaryAction(flow), "Take a break")

        XCTAssertEqual(StudyTimerFormat.primaryAction(StudySession(method: .ankiSprint())), "Start sprint")
    }

    func testStudiedMinutesLabel() {
        XCTAssertEqual(StudyTimerFormat.studied(minutes: -3), "0 min")
        XCTAssertEqual(StudyTimerFormat.studied(minutes: 45), "45 min")
        XCTAssertEqual(StudyTimerFormat.studied(minutes: 60), "1 h")
        XCTAssertEqual(StudyTimerFormat.studied(minutes: 125), "2 h 5 min")
    }

    /// The Timer tab's "45 min of 2 h" reads the daily goal the way Today and
    /// the closed notch do, so one label never mixes "min" with "h".
    func testStudiedMatchesTheSharedGoalFormat() {
        for minutes in [0, 45, 60, 64, 125, 240] {
            XCTAssertEqual(StudyTimerFormat.studied(minutes: minutes),
                           ProgressItem.amount(minutes, unit: ProgressItem.minutesUnit))
        }
    }

    func testPointsLabel() {
        XCTAssertEqual(StudyTimerFormat.points(0), "0 pts")
        XCTAssertEqual(StudyTimerFormat.points(-5), "0 pts")
        XCTAssertEqual(StudyTimerFormat.points(1), "+1 pt")
        XCTAssertEqual(StudyTimerFormat.points(79), "+79 pts")
    }
}
