import XCTest
import TabbiKitCore

final class StudyCustomRhythmTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testStandardRhythmMatchesTheCustomPreset() {
        XCTAssertEqual(StudyCustomRhythm.standard.method, StudyMethod.preset(.custom))
        XCTAssertEqual(StudyCustomRhythm.standard.method.rhythmLabel, "30/5")
    }

    func testValuesAreClampedToEachFieldsRange() {
        let rhythm = StudyCustomRhythm(focusMinutes: 0, breakMinutes: -3, longBreakMinutes: 900,
                                       longBreakEvery: 0, hasLongBreak: true)
        XCTAssertEqual(rhythm.focusMinutes, 5)
        XCTAssertEqual(rhythm.breakMinutes, 1)
        XCTAssertEqual(rhythm.longBreakMinutes, 60)
        XCTAssertEqual(rhythm.longBreakEvery, 2)
        XCTAssertEqual(rhythm.method.longBreak, StudyLongBreak(duration: 60 * 60, every: 2))
    }

    func testDecodingClampsAndFillsMissingValues() throws {
        let json = #"{"focusMinutes": 9000, "longBreakEvery": -1, "hasLongBreak": true}"#
        let rhythm = try JSONDecoder().decode(StudyCustomRhythm.self, from: Data(json.utf8))
        XCTAssertEqual(rhythm.focusMinutes, 180)
        XCTAssertEqual(rhythm.breakMinutes, 5)
        XCTAssertEqual(rhythm.longBreakMinutes, 15)
        XCTAssertEqual(rhythm.longBreakEvery, 2)
        XCTAssertTrue(rhythm.hasLongBreak)
    }

    func testRoundTripsThroughJSON() throws {
        let rhythm = StudyCustomRhythm(focusMinutes: 45, breakMinutes: 10, longBreakMinutes: 30,
                                       longBreakEvery: 3, hasLongBreak: true)
        let data = try JSONEncoder().encode(rhythm)
        XCTAssertEqual(try JSONDecoder().decode(StudyCustomRhythm.self, from: data), rhythm)
    }

    func testSteppingMovesByTheFieldsStepAndStopsAtTheEnds() {
        let rhythm = StudyCustomRhythm.standard
        XCTAssertEqual(rhythm.stepped(.focus, by: 1).focusMinutes, 35)
        XCTAssertEqual(rhythm.stepped(.shortBreak, by: -1).breakMinutes, 4)
        XCTAssertEqual(rhythm.stepped(.longBreakEvery, by: 2).longBreakEvery, 6)

        let shortest = rhythm.setting(.focus, to: 5)
        XCTAssertFalse(shortest.canStep(.focus, by: -1))
        XCTAssertTrue(shortest.canStep(.focus, by: 1))
        XCTAssertFalse(rhythm.setting(.shortBreak, to: 60).canStep(.shortBreak, by: 1))
    }

    func testSteppingSnapsAnOffGridValueToTheGrid() {
        let odd = StudyCustomRhythm(focusMinutes: 23, breakMinutes: 5)
        XCTAssertEqual(odd.stepped(.focus, by: 1).focusMinutes, 25)
        XCTAssertEqual(odd.stepped(.focus, by: -1).focusMinutes, 20)
    }

    func testLongBreakSwitchKeepsItsSettings() {
        let on = StudyCustomRhythm.standard.setting(.longBreak, to: 25).setting(.longBreakEvery, to: 3).withLongBreak(true)
        XCTAssertEqual(on.method.longBreak, StudyLongBreak(duration: 25 * 60, every: 3))
        let off = on.withLongBreak(false)
        XCTAssertNil(off.method.longBreak)
        XCTAssertEqual(off.withLongBreak(true), on)
    }

    func testMenuOffersCustomOnTheUsersLengths() {
        let rhythm = StudyCustomRhythm(focusMinutes: 40, breakMinutes: 8)
        let menu = StudyMethodMenu(kinds: [.pomodoro, .custom])
        XCTAssertEqual(menu.methods(custom: rhythm), [.pomodoro, rhythm.method])
        XCTAssertEqual(StudyMethod.preset(.pomodoro, custom: rhythm), .pomodoro)
    }

    func testRetuneKeepsTheRoundAndClock() {
        var session = StudySession(method: StudyCustomRhythm.standard.method)
        session.start(at: t0)
        session.advance(to: t0.addingTimeInterval(30 * 60))
        XCTAssertEqual(session.phase, .shortBreak)

        let longer = StudyCustomRhythm(focusMinutes: 50, breakMinutes: 10)
        XCTAssertTrue(session.retune(to: longer.method, at: t0.addingTimeInterval(31 * 60)))
        XCTAssertEqual(session.phase, .shortBreak)
        XCTAssertEqual(session.completedFocusCount, 1)
        XCTAssertTrue(session.isRunning)
        XCTAssertEqual(session.remaining(at: t0.addingTimeInterval(31 * 60)), 9 * 60)

        session.advance(to: t0.addingTimeInterval(40 * 60))
        XCTAssertEqual(session.phase, .focus)
        XCTAssertEqual(session.remaining(at: t0.addingTimeInterval(40 * 60)), 50 * 60)
    }

    func testRetuneNeverEndsAPhaseOnTheSpot() {
        var session = StudySession(method: StudyCustomRhythm(focusMinutes: 45, breakMinutes: 5).method)
        session.start(at: t0)
        let now = t0.addingTimeInterval(30 * 60)
        session.retune(to: StudyCustomRhythm(focusMinutes: 20, breakMinutes: 5).method, at: now)
        XCTAssertEqual(session.remaining(at: now), 60)
        XCTAssertTrue(session.advance(to: now).isEmpty)
        XCTAssertEqual(session.phase, .focus)
    }

    func testRetuneRefusesAnotherKind() {
        var session = StudySession(method: .pomodoro)
        XCTAssertFalse(session.retune(to: StudyCustomRhythm.standard.method, at: t0))
        XCTAssertEqual(session.method, .pomodoro)
    }

    func testRetuneOfAFreshSessionTakesTheNewLength() {
        var session = StudySession(method: StudyCustomRhythm.standard.method)
        session.retune(to: StudyCustomRhythm(focusMinutes: 15, breakMinutes: 3).method, at: t0)
        XCTAssertEqual(session.remaining(at: t0), 15 * 60)
        XCTAssertEqual(session.runState, .idle)
    }
}
