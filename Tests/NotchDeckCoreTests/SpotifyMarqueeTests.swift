import XCTest
@testable import NotchDeckCore

final class SpotifyMarqueeTests: XCTestCase {
    func testOnlyOverflowingTextScrolls() {
        XCTAssertFalse(SpotifyMarquee.needsScrolling(textWidth: 200, containerWidth: 300))
        XCTAssertFalse(SpotifyMarquee.needsScrolling(textWidth: 300.3, containerWidth: 300))
        XCTAssertTrue(SpotifyMarquee.needsScrolling(textWidth: 320, containerWidth: 300))
        XCTAssertFalse(SpotifyMarquee.needsScrolling(textWidth: .nan, containerWidth: 300))
        XCTAssertEqual(SpotifyMarquee.offset(elapsed: 5, textWidth: 200, containerWidth: 300), 0)
    }

    func testRestsAtTheStartOfEachCycle() {
        XCTAssertEqual(SpotifyMarquee.offset(elapsed: 0, textWidth: 400, containerWidth: 300), 0)
        XCTAssertEqual(SpotifyMarquee.offset(elapsed: SpotifyMarquee.pause * 0.9,
                                             textWidth: 400, containerWidth: 300), 0)
        XCTAssertEqual(SpotifyMarquee.offset(elapsed: -3, textWidth: 400, containerWidth: 300), 0)
        XCTAssertLessThan(SpotifyMarquee.offset(elapsed: SpotifyMarquee.pause + 1,
                                                textWidth: 400, containerWidth: 300), 0)
    }

    func testOneCycleMovesExactlyOneTextWidthPlusGapThenLoops() {
        let width = 400.0
        let travel = (width + SpotifyMarquee.gap) / SpotifyMarquee.speed
        let cycle = SpotifyMarquee.pause + travel
        let nearEnd = SpotifyMarquee.offset(elapsed: cycle - 0.0001, textWidth: width, containerWidth: 300)
        XCTAssertEqual(nearEnd, -(width + SpotifyMarquee.gap), accuracy: 0.01)
        XCTAssertEqual(SpotifyMarquee.offset(elapsed: cycle + 0.1, textWidth: width, containerWidth: 300), 0)
        let first = SpotifyMarquee.offset(elapsed: SpotifyMarquee.pause + 2, textWidth: width, containerWidth: 300)
        let second = SpotifyMarquee.offset(elapsed: cycle + SpotifyMarquee.pause + 2,
                                           textWidth: width, containerWidth: 300)
        XCTAssertEqual(first, second, accuracy: 0.0001)
    }

    func testScrollIsSmoothAndOnlyMovesLeft() {
        var previous = 0.0
        for frame in 0..<2_000 {
            let offset = SpotifyMarquee.offset(elapsed: Double(frame) / 60, textWidth: 520, containerWidth: 330)
            XCTAssertLessThanOrEqual(offset, 0)
            XCTAssertGreaterThanOrEqual(offset, -(520 + SpotifyMarquee.gap))
            // Within a cycle the text never moves right; a wrap snaps to 0.
            if offset != 0 && previous != 0 {
                XCTAssertLessThanOrEqual(offset, previous + 1e-9)
                XCTAssertLessThan(previous - offset, 2, "no visible jump between frames")
            }
            previous = offset
        }
    }
}
