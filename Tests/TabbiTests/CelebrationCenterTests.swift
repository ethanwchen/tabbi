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
}
