import XCTest
import TabbiKitCore

final class MotionPaceTests: XCTestCase {
    func testSmoothPlaysTheTokensAsDesigned() {
        XCTAssertEqual(MotionPace.smooth.adjusted(MotionTokens.open), MotionTokens.open)
        XCTAssertTrue(MotionPace.smooth.adjusted(MotionTokens.open)?.overshoots ?? false,
                      "opening keeps its subtle overshoot")
        XCTAssertEqual(MotionPace.smooth.duration(MotionTokens.contentFadeIn), MotionTokens.contentFadeIn)
    }

    func testFastIsQuickerAndNeverOvershoots() throws {
        for spec in [MotionTokens.open, MotionTokens.close, MotionTokens.hover, MotionTokens.snappy,
                     MotionTokens.content, MotionTokens.press, MotionTokens.check] {
            let fast = try XCTUnwrap(MotionPace.fast.adjusted(spec))
            XCTAssertLessThan(fast.duration, spec.duration)
            XCTAssertFalse(fast.overshoots)
            XCTAssertLessThan(fast.settlingTime(), spec.settlingTime())
        }
        XCTAssertLessThan(MotionPace.fast.duration(0.2), 0.2)
    }

    func testInstantDoesNotAnimate() {
        XCTAssertNil(MotionPace.instant.adjusted(MotionTokens.open))
        XCTAssertEqual(MotionPace.instant.duration(MotionTokens.contentDelay), 0)
        XCTAssertFalse(MotionPace.instant.isAnimated(reduceMotion: false))
    }

    func testReduceMotionStopsMovementAtEveryPace() {
        for pace in MotionPace.allCases {
            XCTAssertFalse(pace.isAnimated(reduceMotion: true), "\(pace)")
        }
        XCTAssertTrue(MotionPace.smooth.isAnimated(reduceMotion: false))
        XCTAssertTrue(MotionPace.fast.isAnimated(reduceMotion: false))
    }

    func testTheGentleThemeStillComposesWithFast() throws {
        let gentle = ThemeMotion.gentle.adjusted(MotionTokens.open)
        let fast = try XCTUnwrap(MotionPace.fast.adjusted(gentle))
        XCTAssertEqual(fast.duration, gentle.duration * MotionPace.fastScale, accuracy: 1e-9)
    }
}
