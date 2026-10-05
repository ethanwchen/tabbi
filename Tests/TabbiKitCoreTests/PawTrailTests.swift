import XCTest
import TabbiKitCore

final class PawTrailTests: XCTestCase {
    func testPrintsAppearOneAfterAnotherAlongTheTrail() {
        // Just after the third print lands, the first two are already down
        // and the fourth has not appeared yet.
        let time = 2 * PawTrail.stepInterval + PawTrail.pressDuration
        XCTAssertGreaterThan(PawTrail.opacity(ofStep: 0, at: time), 0)
        XCTAssertGreaterThan(PawTrail.opacity(ofStep: 1, at: time), 0)
        XCTAssertEqual(PawTrail.opacity(ofStep: 2, at: time), 1, accuracy: 1e-9)
        XCTAssertEqual(PawTrail.opacity(ofStep: 3, at: time), 0)
        // Older prints have faded further than newer ones.
        XCTAssertLessThan(PawTrail.opacity(ofStep: 0, at: time), PawTrail.opacity(ofStep: 1, at: time))
    }

    func testEveryPrintIsGoneBeforeTheNextWalkStarts() {
        let end = PawTrail.cycle - 0.001
        for step in 0..<PawTrail.stepCount {
            XCTAssertEqual(PawTrail.opacity(ofStep: step, at: end), 0, accuracy: 1e-9,
                           "print \(step) should have faded by the end of the walk")
        }
        // And the walk repeats: the next cycle looks like the first.
        XCTAssertEqual(PawTrail.opacity(ofStep: 1, at: PawTrail.cycle * 2 + 0.5),
                       PawTrail.opacity(ofStep: 1, at: 0.5), accuracy: 1e-9)
    }

    func testOpacityStaysInRangeAtAnyTime() {
        for time in stride(from: -2.0, through: 4.0, by: 0.013) {
            for step in -1...PawTrail.stepCount {
                let opacity = PawTrail.opacity(ofStep: step, at: time)
                XCTAssertGreaterThanOrEqual(opacity, 0)
                XCTAssertLessThanOrEqual(opacity, 1)
                let scale = PawTrail.scale(ofStep: step, at: time)
                XCTAssertGreaterThanOrEqual(scale, 1)
                XCTAssertLessThanOrEqual(scale, 1.15 + 1e-9)
            }
        }
        XCTAssertEqual(PawTrail.opacity(ofStep: PawTrail.stepCount, at: 0.5), 0)
    }

    func testAPrintLandsLargeAndSettles() {
        let landing = PawTrail.stepInterval
        XCTAssertGreaterThan(PawTrail.scale(ofStep: 1, at: landing + 0.01), 1.1)
        XCTAssertEqual(PawTrail.scale(ofStep: 1, at: landing + PawTrail.pressDuration), 1, accuracy: 1e-9)
    }

    func testTheTrailZigzags() {
        XCTAssertTrue(PawTrail.isLeftFoot(0))
        XCTAssertFalse(PawTrail.isLeftFoot(1))
        XCTAssertTrue(PawTrail.isLeftFoot(2))
    }

    func testAFastWaitNeverShowsTheLoader() {
        XCTAssertEqual(PawTrail.revealOpacity(elapsed: 0), 0)
        XCTAssertEqual(PawTrail.revealOpacity(elapsed: 0.29), 0)
        XCTAssertEqual(PawTrail.revealOpacity(elapsed: PawTrail.revealDelay + PawTrail.revealDuration / 2),
                       0.5, accuracy: 1e-9)
        XCTAssertEqual(PawTrail.revealOpacity(elapsed: 2), 1)
        XCTAssertEqual(PawTrail.revealOpacity(elapsed: 0, delay: 0), 0)
        XCTAssertEqual(PawTrail.revealOpacity(elapsed: 1, delay: 0), 1)
    }
}
