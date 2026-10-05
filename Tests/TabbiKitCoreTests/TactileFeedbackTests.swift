import XCTest
import TabbiKitCore

final class TactileFeedbackTests: XCTestCase {
    func testPressingWinsOverHovering() {
        let feedback = TactileFeedback.control
        XCTAssertEqual(feedback.scale(pressed: true, hovering: true, lifts: true, reduceMotion: false), feedback.pressedScale)
        XCTAssertEqual(feedback.scale(pressed: false, hovering: true, lifts: true, reduceMotion: false), feedback.hoverScale)
        XCTAssertEqual(feedback.scale(pressed: false, hovering: false, lifts: true, reduceMotion: false), 1)
    }

    func testOnlyLiftingControlsGrowOnHover() {
        XCTAssertEqual(TactileFeedback.pill.scale(pressed: false, hovering: true, lifts: false, reduceMotion: false), 1)
        XCTAssertLessThan(TactileFeedback.pill.scale(pressed: true, hovering: true, lifts: false, reduceMotion: false), 1)
    }

    func testReduceMotionDimsInsteadOfScaling() {
        for feedback in [TactileFeedback.control, .pill] {
            for pressed in [false, true] {
                for hovering in [false, true] {
                    XCTAssertEqual(feedback.scale(pressed: pressed, hovering: hovering, lifts: true, reduceMotion: true), 1)
                }
            }
            XCTAssertLessThan(feedback.opacity(pressed: true, reduceMotion: true), 1)
            XCTAssertEqual(feedback.opacity(pressed: false, reduceMotion: true), 1)
            XCTAssertEqual(feedback.opacity(pressed: true, reduceMotion: false), 1)
        }
    }

    /// A press should read as a push of a few points, never a jump: a 36 pt
    /// play button and a 140 pt pill both shrink by at most about 4 pt.
    func testPressesMoveEdgesByAFewPoints() {
        let playButton = 36 * (1 - TactileFeedback.control.pressedScale)
        let pill = 140 * (1 - TactileFeedback.pill.pressedScale)
        XCTAssertTrue(playButton > 1 && playButton <= 4)
        XCTAssertTrue(pill > 1 && pill <= 4.5)
        XCTAssertGreaterThan(TactileFeedback.pill.pressedScale, TactileFeedback.control.pressedScale)
    }

    func testLiftsStaySubtle() {
        for feedback in [TactileFeedback.control, .pill] {
            XCTAssertTrue(feedback.hoverScale > 1 && feedback.hoverScale <= 1.06)
        }
    }
}
