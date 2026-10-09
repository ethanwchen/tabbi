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
