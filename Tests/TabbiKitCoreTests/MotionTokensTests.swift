import XCTest
import TabbiKitCore

final class MotionTokensTests: XCTestCase {
    func testSpringConversionMatchesApplesFormula() {
        // Spring(duration: 0.5, bounce: 0.2): stiffness 157.9, damping 20.1.
        let spring = SpringSpec(duration: 0.5, bounce: 0.2)
        XCTAssertEqual(spring.stiffness, 157.9, accuracy: 0.1)
        XCTAssertEqual(spring.damping, 20.1, accuracy: 0.1)
        XCTAssertEqual(spring.dampingRatio, 0.8, accuracy: 0.001)
    }

    func testABounceOfZeroIsCriticallyDampedAndNeverOvershoots() {
        let spring = SpringSpec(duration: 0.4, bounce: 0)
        XCTAssertFalse(spring.overshoots)
        XCTAssertEqual(spring.peak, 1)
        for step in 0...400 {
            XCTAssertLessThanOrEqual(spring.value(at: Double(step) / 200), 1 + 1e-9)
        }
    }

    func testAnOverdampedSpringStillArrives() {
        let spring = SpringSpec(duration: 0.3, bounce: -0.5)
        XCTAssertFalse(spring.overshoots)
        XCTAssertEqual(spring.value(at: 3), 1, accuracy: 0.001)
    }

    func testTheNotchClosesWithoutOvershoot() {
        XCTAssertFalse(MotionTokens.close.overshoots)
    }

    func testTheNotchOpensWithOnlyASmallStretch() {
        XCTAssertTrue(MotionTokens.open.overshoots)
        XCTAssertLessThan(MotionTokens.open.peak, 1.06)
    }

    func testOpenAndCloseLookDoneWithinAboutThreeHundredFiftyMilliseconds() {
        // Perceptually done once within 5% of the target.
        XCTAssertLessThanOrEqual(MotionTokens.open.settlingTime(tolerance: 0.05), 0.4)
        XCTAssertLessThanOrEqual(MotionTokens.close.settlingTime(tolerance: 0.05), 0.35)
    }

    func testClosingIsFasterThanOpening() {
        XCTAssertLessThan(MotionTokens.close.duration, MotionTokens.open.duration)
    }

    func testHoverFeedbackLandsWithinItsBudget() {
        let settle = MotionTokens.hover.settlingTime(tolerance: 0.05)
        XCTAssertGreaterThanOrEqual(settle, 0.15)
        XCTAssertLessThanOrEqual(settle, 0.3)
    }

    func testContentTrailsTheShapeBySixtyToOneHundredMilliseconds() {
        XCTAssertGreaterThanOrEqual(MotionTokens.contentDelay, 0.06)
        XCTAssertLessThanOrEqual(MotionTokens.contentDelay, 0.1)
        XCTAssertLessThan(MotionTokens.contentFadeOut, MotionTokens.close.duration)
    }

    func testStaggerGrowsPerItemAndIsCapped() {
        XCTAssertEqual(MotionTokens.stagger(0), 0)
        XCTAssertEqual(MotionTokens.stagger(2), 2 * MotionTokens.staggerStep, accuracy: 1e-9)
        XCTAssertEqual(MotionTokens.stagger(100), MotionTokens.staggerCap)
        XCTAssertEqual(MotionTokens.stagger(-3), 0)
    }

    func testSpecClampsItsInputs() {
        XCTAssertEqual(SpringSpec(duration: 0.3, bounce: 4).bounce, 1)
        XCTAssertGreaterThan(SpringSpec(duration: 0).duration, 0)
    }
}
