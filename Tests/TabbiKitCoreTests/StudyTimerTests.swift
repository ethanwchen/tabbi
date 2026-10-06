import XCTest
import TabbiKitCore

/// The plain Timer method: one countdown that stops when it ends, with
/// one-click lengths and a stepper for any other.
final class StudyTimerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    func testCountdownEndsIntoAFreshIdleTimerWithNoBreak() {
        var session = StudySession(method: StudyTimerLength(minutes: 5).method)
        session.start(at: t0)
        let ended = session.advance(to: at(30))
        XCTAssertEqual(ended.map(\.phase), [.focus])
        XCTAssertEqual(ended.first?.outcome, .completed)
        XCTAssertEqual(ended.first?.endedAt, at(5))
        XCTAssertEqual(session.phase, .focus)
        XCTAssertEqual(session.runState, .idle)
        XCTAssertEqual(session.remaining(at: at(30)), 5 * 60)
    }

    func testSkippingARunningTimerStopsIt() {
        var session = StudySession(method: StudyTimerLength(minutes: 10).method)
        session.start(at: t0)
        session.skip(at: at(2))
        XCTAssertEqual(session.runState, .idle)
        XCTAssertEqual(session.phase, .focus)
        XCTAssertEqual(session.log.last?.outcome, .skipped)
    }

    func testTimerHasNoBreaksOrRounds() {
        let method = StudyTimerLength.standard.method
        XCTAssertFalse(method.hasBreaks)
        XCTAssertTrue(StudyMethod.pomodoro.hasBreaks)
        XCTAssertNil(method.duration(of: .shortBreak))
        XCTAssertNil(method.duration(of: .longBreak))
        var session = StudySession(method: method)
        session.start(at: t0)
        session.advance(to: at(11))
        XCTAssertEqual(session.completedFocusCount, 1)
        XCTAssertNil(StudyTimerFormat.roundLabel(session))
    }

    func testLabelsSpeakOfATimer() {
        let session = StudySession(method: StudyTimerLength(minutes: 25).method)
        XCTAssertEqual(session.method.rhythmLabel, "25 min")
        XCTAssertEqual(session.method.info.name, "Timer")
        XCTAssertFalse(session.method.nameIsRhythm)
        XCTAssertEqual(StudyTimerFormat.primaryAction(session), "Start timer")
        XCTAssertEqual(StudyTimerFormat.readout(session, at: t0), StudyDialReadout(value: "25:00", caption: "", countsDown: true))
        var paused = session
        paused.start(at: t0)
        paused.pause(at: t0.addingTimeInterval(60))
        XCTAssertEqual(StudyTimerFormat.readout(paused, at: t0.addingTimeInterval(120)).caption, "Paused")
    }

    func testPresetsAreCommonEverydayLengths() {
        XCTAssertEqual(StudyTimerLength.presets, [5, 10, 25])
        XCTAssertTrue(StudyTimerLength.standard.isPreset)
        XCTAssertFalse(StudyTimerLength(minutes: 7).isPreset)
    }

    func testLengthIsClampedOnInitAndDecode() throws {
        XCTAssertEqual(StudyTimerLength(minutes: 0).minutes, 1)
        XCTAssertEqual(StudyTimerLength(minutes: 999).minutes, 180)
        let decoded = try JSONDecoder().decode(StudyTimerLength.self, from: Data("-4".utf8))
        XCTAssertEqual(decoded.minutes, 1)
        let encoded = try JSONEncoder().encode(StudyTimerLength(minutes: 25))
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "25")
    }

    func testStepperMovesByMinutesThenFives() {
        func up(_ minutes: Int) -> Int { StudyTimerLength(minutes: minutes).stepped(up: true).minutes }
        func down(_ minutes: Int) -> Int { StudyTimerLength(minutes: minutes).stepped(up: false).minutes }
        XCTAssertEqual(up(1), 2)
        XCTAssertEqual(up(9), 10)
        XCTAssertEqual(up(10), 15)
        XCTAssertEqual(up(23), 25)
        XCTAssertEqual(down(25), 20)
        XCTAssertEqual(down(23), 20)
        XCTAssertEqual(down(15), 10)
        XCTAssertEqual(down(10), 9)
        XCTAssertEqual(down(2), 1)
        XCTAssertFalse(StudyTimerLength(minutes: 1).canStep(up: false))
        XCTAssertFalse(StudyTimerLength(minutes: 180).canStep(up: true))
        XCTAssertTrue(StudyTimerLength(minutes: 180).canStep(up: false))
    }

    func testRetuningARunningTimerKeepsItsClock() {
        var session = StudySession(method: StudyTimerLength(minutes: 10).method)
        session.start(at: t0)
        XCTAssertTrue(session.retune(to: StudyTimerLength(minutes: 25).method, at: at(4)))
        XCTAssertEqual(session.remaining(at: at(4)), 21 * 60)
    }

    func testMenuUsesTheUsersTimerLength() {
        let menu = StudyMethodMenu(kinds: [.timer, .pomodoro])
        let methods = menu.methods(custom: .standard, timer: StudyTimerLength(minutes: 5))
        XCTAssertEqual(methods.first, StudyTimerLength(minutes: 5).method)
    }

    func testEssentialsStartsOnTheTimerWithPomodoroNext() throws {
        let kit = try XCTUnwrap(KitLibrary.bundled.kits.first { $0.id == "essentials" })
        let menu = StudyMethodMenu(kit: kit.defaults)
        XCTAssertEqual(menu.kinds.prefix(2), [.timer, .pomodoro])
        XCTAssertEqual(menu.startingKind, .timer)
    }
}
