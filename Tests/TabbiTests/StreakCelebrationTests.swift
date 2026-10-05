import XCTest
import TabbiKitCore
@testable import TabbiKit
@testable import Tabbi

/// A review streak reaching a round length is a milestone worth confetti,
/// once, even when Anki reported it while the notch was closed.
@MainActor
final class StreakCelebrationTests: XCTestCase {
    private func store(_ center: CelebrationCenter) -> AnkiStore {
        AnkiStore(celebrations: center, runMode: .live)
    }

    func testReachingAMilestoneOverTheOpenPanelPlaysConfetti() {
        let center = CelebrationCenter(isEnabled: true, hapticsEnabled: { false })
        center.stageAppeared()
        let anki = store(center)

        anki.noteStreak(6)
        XCTAssertNil(center.current, "the first look only sets the baseline")
        anki.noteStreak(7)
        XCTAssertEqual(center.current?.tier, .milestone)
        XCTAssertEqual(center.current?.style, .confetti)
    }

    func testAMilestoneReachedOutOfSightPlaysOnTheNextOpenPanel() {
        let center = CelebrationCenter(isEnabled: true, hapticsEnabled: { false })
        let anki = store(center)
        anki.noteStreak(29)
        anki.noteStreak(30)
        XCTAssertNil(center.current)

        center.stageAppeared()
        anki.noteStreak(30)
        XCTAssertEqual(center.current?.tier, .milestone)
    }

    func testAMilestonePlaysOnlyOnceAndNotAfterTheStreakBroke() {
        let center = CelebrationCenter(isEnabled: true, hapticsEnabled: { false })
        let anki = store(center)
        anki.noteStreak(13)
        anki.noteStreak(14)
        anki.noteStreak(0)
        center.stageAppeared()
        anki.noteStreak(0)
        XCTAssertNil(center.current, "the streak broke before anyone saw the milestone")

        anki.noteStreak(6)
        anki.noteStreak(7)
        let first = center.current
        XCTAssertNotNil(first)
        anki.noteStreak(7)
        XCTAssertEqual(center.current, first, "a held streak does not celebrate again")
    }
}
