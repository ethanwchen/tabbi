import XCTest
@testable import TabbiKitCore

/// A hang is a run of unanswered pings, reported once when it begins and
/// once when the main thread answers again.
final class HangDetectorTests: XCTestCase {
    func testAnsweredPingsNeverMakeAHang() {
        var detector = HangDetector(ticksToHang: 3)
        for _ in 0 ..< 10 {
            XCTAssertNil(detector.tick(answered: true))
        }
        XCTAssertFalse(detector.isHanging)
    }

    func testAHangBeginsOnceAfterEnoughMissedTicksAndEndsOnTheNextAnswer() {
        var detector = HangDetector(ticksToHang: 3)
        XCTAssertNil(detector.tick(answered: false))
        XCTAssertNil(detector.tick(answered: false))
        XCTAssertEqual(detector.tick(answered: false), .began)
        XCTAssertNil(detector.tick(answered: false), "a long hang is reported once")
        XCTAssertTrue(detector.isHanging)
        XCTAssertEqual(detector.tick(answered: true), .ended)
        XCTAssertNil(detector.tick(answered: true))
        XCTAssertFalse(detector.isHanging)
    }

    func testAnAnswerResetsTheCount() {
        var detector = HangDetector(ticksToHang: 3)
        XCTAssertNil(detector.tick(answered: false))
        XCTAssertNil(detector.tick(answered: false))
        XCTAssertNil(detector.tick(answered: true), "a slow moment is not a hang")
        XCTAssertNil(detector.tick(answered: false))
        XCTAssertNil(detector.tick(answered: false))
        XCTAssertEqual(detector.tick(answered: false), .began)
    }

    func testATickCountBelowOneStillNeedsOneMissedTick() {
        var detector = HangDetector(ticksToHang: 0)
        XCTAssertEqual(detector.ticksToHang, 1)
        XCTAssertNil(detector.tick(answered: true))
        XCTAssertEqual(detector.tick(answered: false), .began)
    }
}
