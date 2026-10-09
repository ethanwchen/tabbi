import AppKit
import XCTest
@testable import TabbiKit
import TabbiKitCore
@testable import Tabbi

/// A Study block finished with the notch closed makes the pet beside it
/// cheer, like a finished Focus session. With the Study panel in view the
/// panel celebrates instead, and behind another tab the hop waits for it.
@MainActor
final class StudyCheerTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var folder: URL!
    private var sounds: [CelebrationSound] = []
    private var haptics: [NSHapticFeedbackManager.FeedbackPattern] = []

    override func setUp() async throws {
        suite = "StudyCheerTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudyCheerTests-\(UUID().uuidString)", isDirectory: true)
        sounds = []
        haptics = []
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
    }

    private func center() -> CelebrationCenter {
        CelebrationCenter(hapticsEnabled: { true }, soundEnabled: { true },
                          playSound: { [unowned self] in sounds.append($0) },
                          performHaptic: { [unowned self] in haptics.append($0) })
    }

    /// A Flowtime stretch running, cue sounds and taps cleared.
    private func flowtime(_ center: CelebrationCenter, runMode: RunMode = .live) -> StudyStore {
        let study = StudyStore(storage: EditionStorage(root: folder), celebrations: center, runMode: runMode,
                               defaults: defaults, interruptions: (NotificationCenter(), NotificationCenter()))
        study.choose(.flowtime)
        study.primaryAction()
        sounds = []
        haptics = []
        return study
    }

    func testEndingAStretchWithTheNotchClosedCheersWithASoftSound() {
        let center = center()
        let study = flowtime(center)
        study.primaryAction()
        XCTAssertEqual(study.session.completedFocusCount, 1)
        XCTAssertEqual(center.cheer?.kind, .dance)
        // The user ended it, so no chime played: the cheer brings the soft sound.
        XCTAssertEqual(sounds.count, 1)
        XCTAssertEqual(haptics.count, 1)
        study.stop()
    }

    func testThePanelInViewCelebratesInsteadOfTheClosedNotchPet() {
        let center = center()
        let study = flowtime(center)
        study.setVisible(true)
        study.primaryAction()
        XCTAssertEqual(study.session.completedFocusCount, 1)
        XCTAssertNil(center.cheer)
        study.setVisible(false)
        study.stop()
    }

    func testAnotherTabOpenHoldsTheHopForTheStudyPanel() {
        let center = center()
        let study = flowtime(center)
        center.stageAppeared()
        study.primaryAction()
        XCTAssertNil(center.cheer, "a panel is open, so the closed-notch pet stays put")
        center.stageDisappeared()
        study.stop()
    }

    func testSnapshotRunsNeverCheer() {
        let center = center()
        let study = flowtime(center, runMode: RunMode(isSnapshot: true))
        study.primaryAction()
        XCTAssertNil(center.cheer)
    }
}
