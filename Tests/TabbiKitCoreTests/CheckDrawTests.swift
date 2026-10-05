import XCTest
import TabbiKitCore

final class CheckDrawTests: XCTestCase {
    func testOffShowsOnlyTheRing() {
        let off = CheckDraw(progress: 0)
        XCTAssertEqual(off.ringOpacity, 1)
        XCTAssertEqual(off.fillOpacity, 0)
        XCTAssertEqual(off.checkTrim, 0)
        XCTAssertEqual(off.checkOpacity, 0)
    }

    func testOnIsAFullFillWithTheWholeCheck() {
        let on = CheckDraw(progress: 1)
        XCTAssertEqual(on.ringOpacity, 0)
        XCTAssertEqual(on.fillOpacity, 1)
        XCTAssertEqual(on.fillScale, 1, accuracy: 1e-9)
        XCTAssertEqual(on.checkTrim, 1, accuracy: 1e-9)
        XCTAssertEqual(on.checkOpacity, 1)
    }

    /// The check starts drawing while the fill still grows, so the two read
    /// as one gesture, and the stroke only finishes once the fill is full.
    func testTheCheckDrawsOnAfterTheFillStarts() {
        XCTAssertEqual(CheckDraw(progress: CheckDraw.checkStart).checkTrim, 0)
        let overlap = CheckDraw(progress: (CheckDraw.checkStart + CheckDraw.fillEnd) / 2)
        XCTAssertGreaterThan(overlap.checkTrim, 0)
        XCTAssertLessThan(overlap.fillScale, 1)
        XCTAssertEqual(CheckDraw(progress: CheckDraw.fillEnd).fillScale, 1, accuracy: 1e-9)
        XCTAssertLessThan(CheckDraw(progress: CheckDraw.fillEnd).checkTrim, 1)
    }

    func testDrawingIsMonotonic() {
        var previous = CheckDraw(progress: 0)
        for step in 1...100 {
            let next = CheckDraw(progress: Double(step) / 100)
            XCTAssertGreaterThanOrEqual(next.fillScale, previous.fillScale)
            XCTAssertGreaterThanOrEqual(next.checkTrim, previous.checkTrim)
            XCTAssertGreaterThanOrEqual(next.fillOpacity, previous.fillOpacity)
            XCTAssertLessThanOrEqual(next.ringOpacity, previous.ringOpacity)
            previous = next
        }
    }

    /// The check spring's overshoot is the toggle's bounce: the fill swells
    /// a little, never past the cap, and the stroke never overdraws.
    func testOvershootSwellsTheFillWithinTheCap() {
        let spring = MotionTokens.check
        XCTAssertTrue(spring.overshoots)
        let atPeak = CheckDraw(progress: spring.peak)
        XCTAssertGreaterThan(atPeak.fillScale, 1)
        XCTAssertLessThanOrEqual(atPeak.fillScale, CheckDraw.maxSwell)
        XCTAssertEqual(atPeak.checkTrim, 1)
        XCTAssertEqual(CheckDraw(progress: 5).fillScale, CheckDraw.maxSwell)
    }

    /// Springing back to off undershoots below 0; that must look like off.
    func testUndershootAndBadValuesLookOff() {
        for progress in [-0.2, .nan, -.infinity] {
            XCTAssertEqual(CheckDraw(progress: progress), CheckDraw(progress: 0))
        }
    }

    func testCheckSpringIsQuick() {
        XCTAssertLessThan(MotionTokens.check.settlingTime(), 0.5)
        XCTAssertLessThan(MotionTokens.check.peak, 1.15)
    }

    /// Under Reduce Motion nothing grows or draws: the finished checkbox
    /// crossfades in over the ring.
    func testReduceMotionCrossfadesTheFinishedCheck() {
        for progress in [0.0, 0.3, 0.7, 1, 1.1] {
            let state = CheckDraw(progress: progress, reduceMotion: true)
            XCTAssertEqual(state.fillScale, 1)
            XCTAssertEqual(state.checkTrim, 1)
            XCTAssertEqual(state.fillOpacity, min(progress, 1), accuracy: 1e-9)
            XCTAssertEqual(state.ringOpacity + state.fillOpacity, 1, accuracy: 1e-9)
        }
    }
}
