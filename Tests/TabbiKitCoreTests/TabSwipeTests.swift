import XCTest
@testable import TabbiKitCore

final class TabSwipeTests: XCTestCase {
    /// Feeds one gesture of `count` events, each moving `deltaX`, and returns its steps.
    private func gesture(_ swipe: inout TabSwipe, deltaX: Double, count: Int, momentum: Int = 0) -> [TabSwipe.Step] {
        var steps: [TabSwipe.Step?] = [swipe.feed(deltaX: deltaX, deltaY: 0, phase: .began)]
        for _ in 1..<count { steps.append(swipe.feed(deltaX: deltaX, deltaY: 0, phase: .changed)) }
        steps.append(swipe.feed(deltaX: 0, deltaY: 0, phase: .ended))
        for _ in 0..<momentum { steps.append(swipe.feed(deltaX: deltaX, deltaY: 0, phase: .momentum)) }
        return steps.compactMap { $0 }
    }

    func testALongSwipeStepsExactlyOnce() {
        // The old handler stepped back and forth on every event after the
        // first step, so a swipe of 8 or 9 events landed on the starting tab.
        for count in 1...20 {
            var swipe = TabSwipe()
            XCTAssertEqual(gesture(&swipe, deltaX: -100, count: count), [.next], "\(count) events")
            XCTAssertEqual(gesture(&swipe, deltaX: 30, count: count + 2), [.previous], "\(count + 2) events")
        }
    }

    func testMomentumAfterTheFingersLiftDoesNotStepAgain() {
        var swipe = TabSwipe()
        XCTAssertEqual(gesture(&swipe, deltaX: -40, count: 3, momentum: 30), [.next])
    }

    func testAShortSwipeDoesNotStep() {
        var swipe = TabSwipe()
        XCTAssertEqual(gesture(&swipe, deltaX: -20, count: 3), [])
        // Travel does not carry over into the next gesture.
        XCTAssertEqual(gesture(&swipe, deltaX: -20, count: 2), [])
    }

    func testMostlyVerticalScrollingIsIgnored() {
        var swipe = TabSwipe()
        XCTAssertNil(swipe.feed(deltaX: 0, deltaY: 5, phase: .began))
        for _ in 0..<20 { XCTAssertNil(swipe.feed(deltaX: -10, deltaY: 40, phase: .changed)) }
    }

    func testAMouseWheelStepsOncePerThresholdOfTravel() {
        var swipe = TabSwipe()
        let steps = (0..<14).compactMap { _ in swipe.feed(deltaX: -10, deltaY: 0, phase: .none) }
        XCTAssertEqual(steps, [.next, .next])
    }
}

final class TickerSwipeTests: XCTestCase {
    /// Feeds one gesture of `count` events, each moving `down`, and returns how many steps it made.
    private func gesture(_ swipe: inout TickerSwipe, down: Double, count: Int, momentum: Int = 0) -> Int {
        var steps = [swipe.feed(deltaX: 0, fingersDown: down, phase: .began)]
        for _ in 1..<count { steps.append(swipe.feed(deltaX: 0, fingersDown: down, phase: .changed)) }
        steps.append(swipe.feed(deltaX: 0, fingersDown: 0, phase: .ended))
        for _ in 0..<momentum { steps.append(swipe.feed(deltaX: 0, fingersDown: down, phase: .momentum)) }
        return steps.filter { $0 }.count
    }

    func testASwipeDownCyclesExactlyOnce() {
        for count in 2...20 {
            var swipe = TickerSwipe()
            XCTAssertEqual(gesture(&swipe, down: 30, count: count, momentum: 20), 1, "\(count) events")
        }
    }

    func testShortUpwardAndSidewaysSwipesDoNotCycle() {
        var swipe = TickerSwipe()
        XCTAssertEqual(gesture(&swipe, down: 15, count: 2), 0)
        XCTAssertEqual(gesture(&swipe, down: 15, count: 2), 0, "travel does not carry over")
        XCTAssertEqual(gesture(&swipe, down: -50, count: 10), 0)
        XCTAssertFalse(swipe.feed(deltaX: 0, fingersDown: 0, phase: .began))
        for _ in 0..<10 { XCTAssertFalse(swipe.feed(deltaX: -60, fingersDown: 20, phase: .changed)) }
    }

    func testGoingUpFirstDoesNotDelayASwipeDown() {
        var swipe = TickerSwipe()
        XCTAssertFalse(swipe.feed(deltaX: 0, fingersDown: -100, phase: .began))
        XCTAssertTrue(swipe.feed(deltaX: 0, fingersDown: 45, phase: .changed))
    }

    func testAMouseWheelCyclesOncePerThreshold() {
        var swipe = TickerSwipe()
        let steps = (0..<10).filter { _ in swipe.feed(deltaX: 0, fingersDown: 10, phase: .none) }.count
        XCTAssertEqual(steps, 2)
    }
}

final class CloseSwipeTests: XCTestCase {
    /// Feeds one gesture of `count` events, each moving `up`, and returns how many closes it made.
    private func gesture(
        _ swipe: inout CloseSwipe, up: Double, deltaX: Double = 0, count: Int, momentum: Int = 0, overList: Bool = false
    ) -> Int {
        var closes = [swipe.feed(deltaX: deltaX, fingersUp: up, phase: .began, overScrollableList: overList)]
        for _ in 1..<count {
            closes.append(swipe.feed(deltaX: deltaX, fingersUp: up, phase: .changed, overScrollableList: false))
        }
        closes.append(swipe.feed(deltaX: 0, fingersUp: 0, phase: .ended, overScrollableList: false))
        for _ in 0..<momentum {
            closes.append(swipe.feed(deltaX: 0, fingersUp: up, phase: .momentum, overScrollableList: false))
        }
        return closes.filter { $0 }.count
    }

    func testASwipeUpClosesOnce() {
        for count in 4...20 {
            var swipe = CloseSwipe()
            XCTAssertEqual(gesture(&swipe, up: 20, count: count, momentum: 10), 1, "\(count) events")
        }
    }

    func testAShortOrDownwardSwipeDoesNotClose() {
        var swipe = CloseSwipe()
        XCTAssertEqual(gesture(&swipe, up: 20, count: 3), 0)
        // Travel does not carry over into the next gesture.
        XCTAssertEqual(gesture(&swipe, up: 20, count: 3), 0)
        XCTAssertEqual(gesture(&swipe, up: -30, count: 10), 0)
    }

    func testASwipeOverAScrollableListBelongsToTheList() {
        var swipe = CloseSwipe()
        XCTAssertEqual(gesture(&swipe, up: 30, count: 10, overList: true), 0)
        // The next gesture, away from the list, closes again.
        XCTAssertEqual(gesture(&swipe, up: 30, count: 10), 1)
    }

    func testASidewaysTabSwipeDoesNotClose() {
        var swipe = CloseSwipe()
        XCTAssertEqual(gesture(&swipe, up: 15, deltaX: -40, count: 20), 0)
    }

    func testAMouseWheelNeverCloses() {
        var swipe = CloseSwipe()
        let closes = (0..<40).filter { _ in swipe.feed(deltaX: 0, fingersUp: 30, phase: .none, overScrollableList: false) }
        XCTAssertTrue(closes.isEmpty)
    }
}
