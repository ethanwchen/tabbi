import XCTest
import SwiftUI
import TabbiKitCore
@testable import TabbiKit

/// When a real event gets to celebrate: only while an open panel can show
/// it, never in a snapshot run, and within the shared pacer's limits.
@MainActor
final class CelebrationCenterTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    private func center(isEnabled: Bool = true) -> CelebrationCenter {
        CelebrationCenter(isEnabled: isEnabled, hapticsEnabled: { false }, now: { [unowned self] in clock })
    }

    func testNothingPlaysWhileTheNotchIsClosed() {
        let center = center()
        XCTAssertNil(center.celebrate(.burst, style: .confetti, accent: .teal))
        XCTAssertNil(center.current)

        // The unseen event used up nothing: the first visible one plays.
        center.stageAppeared()
        XCTAssertEqual(center.celebrate(.burst, style: .confetti, accent: .teal), .burst)
        XCTAssertEqual(center.current?.tier, .burst)
        XCTAssertEqual(center.current?.date, clock)
    }

    func testSoundPlaysOnlyWhenAllowedAndTheEventHasNone() {
        var played: [CelebrationSound] = []
        var soundOn = true
        let center = CelebrationCenter(hapticsEnabled: { false }, soundEnabled: { soundOn },
                                       playSound: { played.append($0) }, now: { [unowned self] in clock })
        center.stageAppeared()

        // The Pomodoro already chimed: its burst stays quiet.
        XCTAssertEqual(center.celebrate(.burst, style: .confetti, accent: .teal, hasOwnSound: true), .burst)
        XCTAssertEqual(played, [])

        // An unlock has no sound of its own.
        XCTAssertEqual(center.celebrate(.milestone, style: .sparkles, accent: .pink), .milestone)
        XCTAssertEqual(played.map(\.name), ["Hero"])

        // A refused event only nods, silently.
        XCTAssertNil(center.celebrate(.burst, style: .hearts, accent: .pink, from: .closet))
        XCTAssertEqual(played.count, 1)

        // Turning the sound off in Settings applies to the next celebration.
        soundOn = false
        clock += CelebrationPacer.burstInterval
        XCTAssertEqual(center.celebrate(.burst, style: .hearts, accent: .pink), .burst)
        XCTAssertEqual(played.count, 1)
    }

    func testAClosedNotchCheersThePetInstead() {
        var played: [CelebrationSound] = []
        var soundOn = true
        let center = CelebrationCenter(hapticsEnabled: { false }, soundEnabled: { soundOn },
                                       playSound: { played.append($0) }, now: { [unowned self] in clock })

        // The Pomodoro already chimed, so the cheer adds no sound.
        let first = center.cheer(.dance, hasOwnSound: true)
        XCTAssertEqual(first, PetCheer(kind: .dance, id: 1, startedAt: clock))
        XCTAssertEqual(center.cheer, first)
        XCTAssertEqual(played, [])

        // Cheers are not paced: the next finished session cheers again,
        // and is a new value; without a sound of its own it plays a soft one.
        clock += 60
        XCTAssertEqual(center.cheer(.dance)?.id, 2)
        XCTAssertEqual(played.map(\.name), ["Pop"])
        soundOn = false
        XCTAssertEqual(center.cheer(.dance)?.id, 3)
        XCTAssertEqual(played.count, 1)

        // With a panel open the panel's burst plays instead.
        center.stageAppeared()
        XCTAssertNil(center.cheer(.dance))
        XCTAssertEqual(center.cheer?.id, 3)
    }

    func testSnapshotRunsNeverCheer() {
        let center = center(isEnabled: false)
        XCTAssertNil(center.cheer(.dance))
        XCTAssertNil(center.cheer)
    }

    func testSnapshotRunsNeverCelebrate() {
        let center = center(isEnabled: false)
        center.stageAppeared()
        XCTAssertNil(center.celebrate(.milestone, style: .sparkles, accent: .teal))
        XCTAssertNil(center.current)
    }

    func testBurstsArePacedAcrossModules() {
        let center = center()
        center.stageAppeared()
        XCTAssertEqual(center.celebrate(.burst, style: .confetti, accent: .teal), .burst)
        let first = center.current?.id

        clock += 60
        XCTAssertNil(center.celebrate(.burst, style: .hearts, accent: .pink))
        XCTAssertEqual(center.current?.id, first, "a refused burst leaves the last one in place")

        clock += CelebrationPacer.burstInterval
        XCTAssertEqual(center.celebrate(.burst, style: .hearts, accent: .pink), .burst)
        XCTAssertNotEqual(center.current?.id, first)
    }

    func testStageCountFollowsOverlappingPanels() {
        let center = center()
        // A tab switch shows the new panel before the old one leaves.
        center.stageAppeared()
        center.stageAppeared()
        center.stageDisappeared()
        XCTAssertTrue(center.isShowing)
        center.stageDisappeared()
        center.stageDisappeared()
        XCTAssertFalse(center.isShowing)
        center.stageAppeared()
        XCTAssertTrue(center.isShowing, "an extra disappearance never leaves the count negative")
    }

    func testARefusedCelebrationNodsItsModuleTab() {
        let center = center()
        center.stageAppeared()
        XCTAssertEqual(center.celebrate(.burst, style: .confetti, accent: .teal, from: .focus), .burst)
        XCTAssertNil(center.nod, "a burst that plays needs no nod")

        clock += 60
        XCTAssertNil(center.celebrate(.burst, style: .pawPrints, accent: .teal, from: .study))
        XCTAssertEqual(center.nod?.source, .study)
        let first = center.nod?.id

        clock += 60
        center.celebrate(.burst, style: .pawPrints, accent: .teal, from: .study)
        XCTAssertNotEqual(center.nod?.id, first, "a second nod from the same module is still a change")
    }

    func testNothingNodsWhileClosedOrWithoutASource() {
        let center = center()
        center.celebrate(.burst, style: .confetti, accent: .teal, from: .focus)
        XCTAssertNil(center.nod, "an unseen event nods nowhere")

        center.stageAppeared()
        center.celebrate(.burst, style: .confetti, accent: .teal)
        clock += 60
        center.celebrate(.burst, style: .confetti, accent: .teal)
        XCTAssertNil(center.nod, "without a source there is no tab to bounce")
    }

    func testANodBouncesTheOpenTabWhenItsModuleHasNone() {
        let nod = CelebrationNod(id: 1, source: .focus)
        XCTAssertEqual(nod.tab(enabled: [.planner, .focus], selected: .planner), .focus)
        XCTAssertEqual(nod.tab(enabled: [.planner, .anki], selected: .anki), .anki)
    }
}
