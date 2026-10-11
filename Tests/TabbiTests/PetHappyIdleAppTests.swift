import XCTest
import TabbiKitCore
@testable import TabbiKit

/// A grown bond (`PetBondLook.happyIdle`) reaches every pet on screen
/// through `PetPlayer`: it swishes its tail now and then while idling.
@MainActor
final class PetHappyIdleAppTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Whether `player` draws a tail swish frame in its first two minutes.
    private func swishes(_ player: PetPlayer) -> Bool {
        let swish = Set(player.clips[.tailSwish].frames.map(\.canvas))
        let idle = Set(player.clips[.idle].frames.map(\.canvas))
        return stride(from: 0.0, to: 120, by: 1.0 / 30).contains { offset in
            guard let canvas = player.frame(at: start.addingTimeInterval(offset))?.canvas else { return false }
            return swish.contains(canvas) && !idle.contains(canvas)
        }
    }

    private func profile(bond level: Int) -> PetProfile {
        var profile = PetProfile.starter(.cat)
        profile.bondLook = PetBondLook(level: level)
        return profile
    }

    func testAPetSwishesItsTailOnceTheBondUnlocksTheHappyIdle() {
        let level = PetBondLook.happyIdleLevel
        XCTAssertFalse(swishes(PetPlayer(profile: profile(bond: level - 1), at: start, seed: 3)))
        XCTAssertTrue(swishes(PetPlayer(profile: profile(bond: level), at: start, seed: 3)))
    }

    func testANewBondLookSwitchesThePlayingPetToTheHappyIdle() {
        let player = PetPlayer(profile: profile(bond: 1), at: start, seed: 3)
        player.update(profile: profile(bond: PetBondLook.happyIdleLevel), at: start)
        XCTAssertTrue(swishes(player))
    }
}
