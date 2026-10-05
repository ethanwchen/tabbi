import XCTest
import TabbiKitCore

final class LoaderClockTests: XCTestCase {
    func testTheSpinnerTurnsOncePerPeriod() {
        XCTAssertEqual(LoaderClock.spinAngle(at: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(LoaderClock.spinAngle(at: 0.25), 90, accuracy: 1e-9)
        XCTAssertEqual(LoaderClock.spinAngle(at: 1.5), 180, accuracy: 1e-9)
        XCTAssertEqual(LoaderClock.spinAngle(at: 1, period: 2), 180, accuracy: 1e-9)
    }

    func testTheSpinAngleStaysInOneTurnForAnyTime() {
        for time in stride(from: -3.0, through: 3.0, by: 0.07) {
            let angle = LoaderClock.spinAngle(at: time)
            XCTAssertGreaterThanOrEqual(angle, 0)
            XCTAssertLessThan(angle, 360)
        }
        XCTAssertEqual(LoaderClock.spinAngle(at: 5, period: 0), 0)
    }

    func testBreathingStaysVisibleAndPeaksOnWholePeriods() {
        let period = LoaderClock.breathPeriod
        XCTAssertEqual(LoaderClock.breathingOpacity(at: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(LoaderClock.breathingOpacity(at: period), 1, accuracy: 1e-9)
        XCTAssertEqual(LoaderClock.breathingOpacity(at: period / 2), LoaderClock.breathFloor, accuracy: 1e-9)
        for step in 0...100 {
            let opacity = LoaderClock.breathingOpacity(at: Double(step) * period / 37)
            XCTAssertGreaterThanOrEqual(opacity, LoaderClock.breathFloor - 1e-9)
            XCTAssertLessThanOrEqual(opacity, 1 + 1e-9)
        }
    }

    func testLoadersRedrawNoFasterThanThirtyFramesASecond() {
        XCTAssertLessThanOrEqual(LoaderClock.frameRate, 30)
    }
}
