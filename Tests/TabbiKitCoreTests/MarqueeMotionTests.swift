import XCTest
@testable import TabbiKitCore

final class MarqueeMotionTests: XCTestCase {
    func testTextThatFitsDoesNotOverflow() {
        XCTAssertEqual(MarqueeMotion.overflow(contentWidth: 120, containerWidth: 148), 0)
        XCTAssertEqual(MarqueeMotion.overflow(contentWidth: 148, containerWidth: 148), 0)
        // Rounding in measured widths is not an overflow.
        XCTAssertEqual(MarqueeMotion.overflow(contentWidth: 148.4, containerWidth: 148), 0)
    }

    func testTextWiderThanItsRoomOverflowsByTheDifference() {
        XCTAssertEqual(MarqueeMotion.overflow(contentWidth: 200, containerWidth: 148), 52)
    }

    func testUnmeasuredWidthsNeverOverflow() {
        XCTAssertEqual(MarqueeMotion.overflow(contentWidth: 200, containerWidth: 0), 0)
        XCTAssertEqual(MarqueeMotion.overflow(contentWidth: .nan, containerWidth: 148), 0)
        XCTAssertEqual(MarqueeMotion.overflow(contentWidth: .infinity, containerWidth: 148), 0)
    }

    func testOnlyOverflowingVisibleTextScrollsWhenMotionIsAllowed() {
        XCTAssertTrue(MarqueeMotion.scrolls(overflow: 10, reduceMotion: false, isVisible: true))
        XCTAssertFalse(MarqueeMotion.scrolls(overflow: 0, reduceMotion: false, isVisible: true))
        XCTAssertFalse(MarqueeMotion.scrolls(overflow: 10, reduceMotion: true, isVisible: true))
        XCTAssertFalse(MarqueeMotion.scrolls(overflow: 10, reduceMotion: false, isVisible: false))
    }

    func testTextThatFitsRestsAtItsStart() {
        XCTAssertEqual(MarqueeMotion.pose(elapsed: 3, overflow: 0), .rest)
        XCTAssertEqual(MarqueeMotion.pose(elapsed: -1, overflow: 40), .rest)
        XCTAssertEqual(MarqueeMotion.pose(elapsed: .nan, overflow: 40), .rest)
    }

    func testCycleRestsScrollsRestsAndFadesBack() {
        let overflow = 60.0
        let travel = MarqueeMotion.travel(overflow: overflow)
        XCTAssertEqual(travel, 2, accuracy: 0.0001)
        // Resting at the start.
        XCTAssertEqual(MarqueeMotion.pose(elapsed: MarqueeMotion.startPause * 0.9, overflow: overflow), .rest)
        // Half way through the scroll, eased.
        let middle = MarqueeMotion.pose(elapsed: MarqueeMotion.startPause + travel / 2, overflow: overflow)
        XCTAssertEqual(middle.offset, overflow / 2, accuracy: 0.0001)
        XCTAssertEqual(middle.opacity, 1)
        // Resting with the end in view.
        let end = MarqueeMotion.pose(elapsed: MarqueeMotion.startPause + travel + MarqueeMotion.endPause / 2,
                                     overflow: overflow)
        XCTAssertEqual(end, MarqueeMotion.Pose(offset: overflow, opacity: 1))
        // Fading out at the end, then back in at the start.
        let fadeStart = MarqueeMotion.startPause + travel + MarqueeMotion.endPause
        let fadingOut = MarqueeMotion.pose(elapsed: fadeStart + MarqueeMotion.fade / 2, overflow: overflow)
        XCTAssertEqual(fadingOut.offset, overflow)
        XCTAssertEqual(fadingOut.opacity, 0.5, accuracy: 0.0001)
        let fadingIn = MarqueeMotion.pose(elapsed: fadeStart + MarqueeMotion.fade * 1.5, overflow: overflow)
        XCTAssertEqual(fadingIn.offset, 0)
        XCTAssertEqual(fadingIn.opacity, 0.5, accuracy: 0.0001)
        // And the next cycle starts over.
        let cycle = MarqueeMotion.cycle(overflow: overflow)
        XCTAssertEqual(cycle, fadeStart + 2 * MarqueeMotion.fade, accuracy: 0.0001)
        XCTAssertEqual(MarqueeMotion.pose(elapsed: cycle + 0.1, overflow: overflow), .rest)
    }

    func testScrollNeverLeavesItsRangeAndMovesGently() {
        let overflow = 90.0
        var previous = 0.0
        for frame in 0..<Int(MarqueeMotion.cycle(overflow: overflow) * 60) {
            let pose = MarqueeMotion.pose(elapsed: Double(frame) / 60, overflow: overflow)
            XCTAssertGreaterThanOrEqual(pose.offset, 0)
            XCTAssertLessThanOrEqual(pose.offset, overflow)
            XCTAssertGreaterThanOrEqual(pose.opacity, 0)
            XCTAssertLessThanOrEqual(pose.opacity, 1)
            // No jumps while visible: the return to the start happens faded out.
            if pose.opacity > 0.01 && pose.offset > 0 {
                XCTAssertLessThan(abs(pose.offset - previous), 2)
            }
            previous = pose.offset
        }
    }

    func testAShortOverflowStillGlides() {
        XCTAssertEqual(MarqueeMotion.travel(overflow: 3), MarqueeMotion.minimumTravel)
    }

    func testStillPoseIsAFractionOfTheScroll() {
        XCTAssertEqual(MarqueeMotion.pose(scrolled: 0.5, overflow: 40), MarqueeMotion.Pose(offset: 20, opacity: 1))
        XCTAssertEqual(MarqueeMotion.pose(scrolled: 2, overflow: 40).offset, 40)
        XCTAssertEqual(MarqueeMotion.pose(scrolled: -1, overflow: 40).offset, 0)
        XCTAssertEqual(MarqueeMotion.pose(scrolled: 0.5, overflow: 0), .rest)
    }
}
