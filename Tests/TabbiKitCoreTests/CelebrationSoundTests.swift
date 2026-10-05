import XCTest
@testable import TabbiKitCore

final class CelebrationSoundTests: XCTestCase {
    func testEachTierHasAQuietCue() {
        for tier in CelebrationTier.allCases {
            let cue = CelebrationSound.cue(for: tier, isEnabled: true, eventHasSound: false)
            XCTAssertNotNil(cue, "\(tier)")
            // Quieter than the 0.5 focus chime, so it never announces itself.
            XCTAssertLessThan(cue?.volume ?? 1, 0.5, "\(tier)")
        }
    }

    func testMilestonesSoundDifferentFromBursts() {
        XCTAssertNotEqual(CelebrationSound.cue(for: .burst, isEnabled: true, eventHasSound: false),
                          CelebrationSound.cue(for: .milestone, isEnabled: true, eventHasSound: false))
    }

    func testSilentWhenTurnedOffOrTheEventAlreadyPlayedASound() {
        for tier in CelebrationTier.allCases {
            XCTAssertNil(CelebrationSound.cue(for: tier, isEnabled: false, eventHasSound: false))
            XCTAssertNil(CelebrationSound.cue(for: tier, isEnabled: true, eventHasSound: true))
        }
    }
}
