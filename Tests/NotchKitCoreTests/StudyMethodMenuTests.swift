import XCTest
import NotchKitCore

final class StudyMethodMenuTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testNoKitOffersEveryPresetStartingOnPomodoro() {
        let menu = StudyMethodMenu(kit: nil)
        XCTAssertEqual(menu.kinds, StudyMethod.presets.map(\.kind))
        XCTAssertEqual(menu.startingKind, .pomodoro)
        XCTAssertEqual(menu, .all)
    }

    func testKitPicksMethodsInOrderAndTheStartingOne() {
        let kit = KitDefaults(studyMethods: ["flowtime", "pomodoro", "flowtime", "chess"], studyMethod: "pomodoro")
        let menu = StudyMethodMenu(kit: kit)
        XCTAssertEqual(menu.kinds, [.flowtime, .pomodoro])
        XCTAssertEqual(menu.startingKind, .pomodoro)
        XCTAssertEqual(menu.methods.map(\.kind), [.flowtime, .pomodoro])
        XCTAssertTrue(menu.offers(.flowtime))
        XCTAssertFalse(menu.offers(.ankiSprint))
    }

    func testStartingMethodMustBeOffered() {
        XCTAssertEqual(StudyMethodMenu(kinds: [.ultradian, .custom], starting: .ankiSprint).startingKind, .ultradian)
        XCTAssertEqual(StudyMethodMenu(kinds: [.ultradian, .custom]).startingKind, .ultradian)
        XCTAssertEqual(StudyMethodMenu(kinds: nil, starting: .flowtime).startingKind, .flowtime)
    }

    func testKitNamingNoKnownMethodOffersEveryPreset() {
        let menu = StudyMethodMenu(kit: KitDefaults(studyMethods: ["chess"], studyMethod: "chess"))
        XCTAssertEqual(menu.kinds, StudyMethod.presets.map(\.kind))
        XCTAssertEqual(menu.startingKind, .pomodoro)
    }

    func testStoppedSessionMovesOffAMethodTheKitDropped() {
        let menu = StudyMethodMenu(kinds: [.pomodoro, .flowtime], starting: .flowtime)
        XCTAssertEqual(menu.replacement(for: StudySession(method: .ultradian), kitApplied: false), .flowtime)
        XCTAssertNil(menu.replacement(for: StudySession(method: .pomodoro), kitApplied: false))
    }

    func testApplyingAKitStartsAStoppedSessionOnItsMethod() {
        let menu = StudyMethodMenu(kinds: [.pomodoro, .flowtime], starting: .flowtime)
        XCTAssertEqual(menu.replacement(for: StudySession(method: .pomodoro), kitApplied: true), .flowtime)
        XCTAssertNil(menu.replacement(for: StudySession(method: .flowtime), kitApplied: true))
    }

    func testSessionInProgressIsNeverInterrupted() {
        let menu = StudyMethodMenu(kinds: [.flowtime])
        var running = StudySession(method: .pomodoro)
        running.start(at: t0)
        XCTAssertNil(menu.replacement(for: running, kitApplied: true))

        var paused = running
        paused.pause(at: t0.addingTimeInterval(60))
        XCTAssertNil(menu.replacement(for: paused, kitApplied: false))

        // A finished block rolls into a break, which counts as in progress.
        var onBreak = running
        onBreak.advance(to: t0.addingTimeInterval(25 * 60))
        XCTAssertEqual(onBreak.phase, .shortBreak)
        XCTAssertNil(menu.replacement(for: onBreak, kitApplied: true))
    }

    func testOnlyAMethodNamedForItsRhythmHidesTheRhythm() {
        let named = StudyMethodKind.allCases.filter { StudyMethod.preset($0).nameIsRhythm }
        XCTAssertEqual(named, [.fiftyTwoSeventeen])
        XCTAssertEqual(StudyMethod.preset(.fiftyTwoSeventeen).rhythmLabel, "52/17")
    }
}
