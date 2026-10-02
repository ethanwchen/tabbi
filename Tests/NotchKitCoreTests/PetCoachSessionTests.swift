import XCTest
import NotchKitCore

final class PetCoachSessionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Study state from the shared timer

    func testNoTimerOrIdleTimerIsNotStudying() {
        XCTAssertEqual(PetCoachStudyState(nil), .notStudying)
        XCTAssertEqual(PetCoachStudyState(FocusTimer()), .notStudying)
    }

    func testRunningFocusPhaseIsFocusing() {
        var timer = FocusTimer()
        timer.start(at: t0)
        XCTAssertEqual(PetCoachStudyState(timer), .focusing)
    }

    func testPausedTimerIsPaused() {
        var timer = FocusTimer()
        timer.start(at: t0)
        timer.pause(at: t0.addingTimeInterval(60))
        XCTAssertEqual(PetCoachStudyState(timer), .paused)
    }

    func testRunningBreakIsOnBreak() {
        var timer = FocusTimer()
        timer.start(at: t0)
        timer.advance(to: t0.addingTimeInterval(timer.config.focusDuration + 1))
        XCTAssertEqual(timer.phase, .rest)
        XCTAssertEqual(PetCoachStudyState(timer), .onBreak)
    }

    // MARK: Inputs

    func testLongFocusPhasesCountAsDeepFocus() {
        var short = FocusTimer(config: FocusTimerConfig(focusDuration: 25 * 60))
        short.start(at: t0)
        var long = FocusTimer(config: FocusTimerConfig(focusDuration: 50 * 60))
        long.start(at: t0)
        let shortInput = PetCoachInput(now: t0, idleSeconds: 0, frontmost: .neutral, timer: short)
        let longInput = PetCoachInput(now: t0, idleSeconds: 0, frontmost: .neutral, timer: long)
        XCTAssertFalse(shortInput.deepFocus)
        XCTAssertTrue(longInput.deepFocus)
        XCTAssertEqual(longInput.study, .focusing)
    }

    func testCoachNudgesFromTimerInputOnlyWhileFocusing() {
        var focusing = FocusTimer()
        focusing.start(at: t0)
        var onBreak = focusing
        onBreak.skip(at: t0)

        var coach = PetCoach()
        let away = PetCoachInput(now: t0, idleSeconds: 6 * 60, frontmost: .neutral, timer: onBreak)
        XCTAssertEqual(coach.evaluate(away), .none)

        let idle = PetCoachInput(now: t0, idleSeconds: 3 * 60, frontmost: .neutral, timer: focusing)
        XCTAssertEqual(coach.evaluate(idle).nudge?.kind, .idleCheck)
    }

    func testSamplingIsSlowerThanTheShortestThreshold() {
        XCTAssertLessThan(PetCoach.sampleInterval, PetCoachRules.standard.lookOverAfter)
    }

    // MARK: Save

    func testSaveRoundTripsSnoozeCooldownsAndAppLists() throws {
        var coach = PetCoach()
        var focusing = FocusTimer()
        focusing.start(at: t0)
        _ = coach.evaluate(PetCoachInput(now: t0, idleSeconds: 3 * 60, frontmost: .neutral, timer: focusing))
        coach.handle(.snooze, at: t0)
        var apps = CoachAppList()
        apps.markDistracting("com.hnc.Discord")
        let save = PetCoachSave(coach: coach, apps: apps)

        let restored = try PetCoachSave.decode(save.encoded())
        XCTAssertEqual(restored, save)
        XCTAssertTrue(restored.coach.isSnoozed(at: t0.addingTimeInterval(60)))
        XCTAssertEqual(restored.coach.lastNudgeAt, t0)
        XCTAssertEqual(restored.apps.category(of: "com.hnc.discord"), .distracting)
    }

    func testLoadReturnsNilWithoutAFileAndThrowsOnACorruptOne() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Pet/coach.json")
        XCTAssertNil(try PetCoachSave.load(from: url))

        try PetCoachSave().write(to: url)
        XCTAssertEqual(try PetCoachSave.load(from: url), PetCoachSave())

        try Data("not json".utf8).write(to: url)
        XCTAssertThrowsError(try PetCoachSave.load(from: url))
    }
}
