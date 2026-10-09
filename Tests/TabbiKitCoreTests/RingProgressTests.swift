import XCTest
import TabbiKitCore

final class RingProgressTests: XCTestCase {
    func testValuesOutsideTheRingAreClamped() {
        XCTAssertEqual(RingProgress.clamped(-0.2), 0)
        XCTAssertEqual(RingProgress.clamped(0.4), 0.4)
        XCTAssertEqual(RingProgress.clamped(1.3), 1)
    }

    func testMissingOrNonFiniteValuesDrawAnEmptyRing() {
        XCTAssertEqual(RingProgress.clamped(nil), 0)
        XCTAssertEqual(RingProgress.clamped(.nan), 0)
        XCTAssertEqual(RingProgress.clamped(.infinity), 0)
    }

    func testTheRingFillsAsWorkAdvances() {
        XCTAssertEqual(RingProgress.change(from: 0.2, to: 0.25), .advance)
        XCTAssertEqual(RingProgress.change(from: nil, to: 0.1), .advance)
    }

    func testASmallDropUnwindsAndABigDropRestarts() {
        XCTAssertEqual(RingProgress.change(from: 0.3, to: 0), .unwind)
        XCTAssertEqual(RingProgress.change(from: 0.9, to: 0.6), .unwind)
        // A Pomodoro phase change: the full ring starts over.
        XCTAssertEqual(RingProgress.change(from: 1, to: 0), .restart)
        XCTAssertEqual(RingProgress.change(from: 0.86, to: 0.02), .restart)
    }

    func testATickTooSmallToSeeStepsWithoutAGlide() {
        // A 25 minute Pomodoro advances 1/1500 of the ring each second, a
        // 5 minute break 1/300.
        for tick in [1.0 / 1500, 1.0 / 300] {
            XCTAssertEqual(RingProgress.change(from: 0.4, to: 0.4 + tick), .step)
            XCTAssertEqual(RingProgress.change(from: 0.4, to: 0.4 - tick), .step)
        }
        // One card of a 100-card goal still glides.
        XCTAssertEqual(RingProgress.change(from: 0.4, to: 0.41), .advance)
    }

    func testChangesThatClampToTheSameValueDoNothing() {
        XCTAssertEqual(RingProgress.change(from: 1, to: 1.4), .none)
        XCTAssertEqual(RingProgress.change(from: nil, to: 0), .none)
        XCTAssertEqual(RingProgress.change(from: -1, to: .nan), .none)
    }
}
