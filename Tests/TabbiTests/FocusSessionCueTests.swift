import AppKit
import XCTest
import TabbiKit
import TabbiKitCore
@testable import Tabbi

/// The small touches around a Pomodoro: a fresh focus block starts with a
/// light tap and a soft sound, a break running out taps the trackpad (its
/// chime is the sound), and resuming after a pause stays quiet. Both follow
/// the haptics and celebration sound settings.
@MainActor
final class FocusSessionCueTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var sounds: [CelebrationSound] = []
    private var haptics: [NSHapticFeedbackManager.FeedbackPattern] = []

    override func setUp() async throws {
        suite = "FocusSessionCueTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        sounds = []
        haptics = []
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func store(hapticsOn: Bool = true, soundOn: Bool = true, runMode: RunMode = .live) -> FocusStore {
        let center = CelebrationCenter(hapticsEnabled: { hapticsOn },
                                       soundEnabled: { soundOn },
                                       playSound: { [unowned self] in sounds.append($0) },
                                       performHaptic: { [unowned self] in haptics.append($0) })
        return FocusStore(celebrations: center, runMode: runMode, defaults: defaults,
                          interruptions: (NotificationCenter(), NotificationCenter()))
    }

    func testStartingAFocusBlockTapsAndPlaysASoftSoundOnce() {
        let store = store()
        store.start()
        XCTAssertEqual(sounds.map(\.name), ["Tink"])
        XCTAssertEqual(haptics, [.generic])

        // Pausing and resuming is not a new block.
        store.pause()
        store.start()
        XCTAssertEqual(sounds.count, 1)
        XCTAssertEqual(haptics.count, 1)
        store.stop()
    }

    func testStartCueFollowsSettings() {
        let quiet = store(hapticsOn: false, soundOn: false)
        quiet.start()
        XCTAssertEqual(sounds, [])
        XCTAssertEqual(haptics, [])
        quiet.stop()

        let tapOnly = store(hapticsOn: true, soundOn: false)
        tapOnly.start()
        XCTAssertEqual(sounds, [])
        XCTAssertEqual(haptics, [.generic])
        tapOnly.stop()
    }

    func testStartingABreakHasNoCue() {
        let store = store()
        store.skip()
        XCTAssertEqual(store.timer.phase, .rest)
        store.start()
        XCTAssertEqual(sounds, [])
        XCTAssertEqual(haptics, [])
        store.stop()
    }

    func testABreakRunningOutTapsWithoutAddingASound() async throws {
        let timer = FocusTimer(phase: .rest, runState: .idle, config: FocusTimerConfig(restDuration: 0.5))
        FocusTimerStorage(defaults: defaults).save(timer)
        let store = store()
        store.start()
        XCTAssertEqual(store.timer.phase, .rest)
        XCTAssertEqual(haptics, [], "starting a break has no cue")

        try await Task.sleep(for: .seconds(1.2))
        XCTAssertEqual(store.timer.phase, .focus)
        XCTAssertEqual(haptics, [.levelChange])
        // The chime already plays for the end of a break.
        XCTAssertEqual(sounds, [])
    }

    func testStudyStartsABlockWithTheSameCue() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("FocusSessionCueTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let center = CelebrationCenter(hapticsEnabled: { true }, soundEnabled: { true },
                                       playSound: { [unowned self] in sounds.append($0) },
                                       performHaptic: { [unowned self] in haptics.append($0) })
        let study = StudyStore(storage: EditionStorage(root: folder), celebrations: center, runMode: .live,
                               defaults: defaults, interruptions: (NotificationCenter(), NotificationCenter()))
        study.primaryAction()
        XCTAssertEqual(sounds.map(\.name), ["Tink"])
        XCTAssertEqual(haptics, [.generic])

        // Pause, then resume: no second cue.
        study.primaryAction()
        study.primaryAction()
        XCTAssertEqual(haptics.count, 1)
        study.stop()
    }

    func testSnapshotRunsCueNothing() {
        let store = store(runMode: RunMode(isSnapshot: true))
        store.start()
        XCTAssertEqual(sounds, [])
        XCTAssertEqual(haptics, [])
    }
}
