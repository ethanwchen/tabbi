import XCTest
import NotchKitCore

final class PetCoachGlanceTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    /// One second down, two seconds looking, one second back up.
    private func glance() -> PetCoachGlance {
        PetCoachGlance(startedAt: t0, enter: 1, hold: 2, leave: 1)
    }

    func testGlanceLowersHoldsAndPullsBackUp() {
        let glance = glance()
        XCTAssertNil(glance.pose(at: at(-0.1)))
        XCTAssertEqual(glance.pose(at: at(0.5))?.animation, .peekIn)
        XCTAssertEqual(glance.pose(at: at(0.5))?.elapsed ?? -1, 0.5, accuracy: 0.001)
        // Holding keeps peekIn running past its end, i.e. on its last frame.
        XCTAssertEqual(glance.pose(at: at(2.5))?.animation, .peekIn)
        XCTAssertEqual(glance.pose(at: at(3.25))?.animation, .peekOut)
        XCTAssertEqual(glance.pose(at: at(3.25))?.elapsed ?? -1, 0.25, accuracy: 0.001)
        XCTAssertNil(glance.pose(at: at(4)))
        XCTAssertEqual(glance.endsAt, at(4))
    }

    func testGlanceIsTimedByThePetsOwnPeekClips() {
        let clips = PetClipSet(profile: .starter(.cat))
        let glance = PetCoachGlance(startedAt: t0, clips: clips)
        XCTAssertEqual(glance.enter, clips[.peekIn].duration)
        XCTAssertEqual(glance.leave, clips[.peekOut].duration)
        XCTAssertEqual(glance.hold, PetCoachGlance.standardHold)
        // Brief: noticeable, never in the way.
        XCTAssertLessThan(glance.duration, 5)
    }

    func testGlanceStrollStaysAtTheNotchAndEndsWithTheGlance() {
        let stroll = glance().stroll
        XCTAssertEqual(stroll.endsAt, glance().endsAt)
        for second in stride(from: 0.0, through: 4, by: 0.5) {
            XCTAssertEqual(stroll.offset(at: at(second)), 0)
        }
    }

    func testNegativeDurationsClampToZero() {
        let glance = PetCoachGlance(startedAt: t0, enter: -1, hold: -1, leave: -1)
        XCTAssertEqual(glance.duration, 0)
        XCTAssertNil(glance.pose(at: t0))
    }
}
