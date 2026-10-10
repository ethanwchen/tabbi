import XCTest
import TabbiKitCore

/// `ProvidedFocus.nextShownChange(after:)` lets a view that mirrors a shared
/// clock (Today's card for Study's timer) redraw only when its face changes,
/// and not at all while the clock is stopped.
final class ProvidedFocusClockTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 700_000_000.25)

    private func focus(_ clock: ProvidedFocus.Clock, length: TimeInterval? = 25 * 60) -> ProvidedFocus {
        ProvidedFocus(source: .focus, phase: .focus, clock: clock, phaseLength: length)
    }

    /// Follows the schedule from `now` for `seconds` and checks that every
    /// wakeup shows a different face than the one before it.
    private func wakeups(of focus: ProvidedFocus, over seconds: TimeInterval,
                         file: StaticString = #filePath, line: UInt = #line) -> Int {
        func face(at date: Date) -> String { StudyTimerFormat.clock(focus.shownTime(at: date)) }
        var count = 0
        var date = now
        while let next = focus.nextShownChange(after: date), next < now.addingTimeInterval(seconds) {
            XCTAssertGreaterThan(next, date, "the schedule moves forward", file: file, line: line)
            XCTAssertNotEqual(face(at: next), face(at: date), "a wakeup lands on a change", file: file, line: line)
            count += 1
            date = next
        }
        return count
    }

    func testAStoppedClockNeedsNoRedraws() {
        XCTAssertNil(focus(.idle).nextShownChange(after: now))
        XCTAssertNil(focus(.paused(shown: 9 * 60 + 47)).nextShownChange(after: now))
        XCTAssertNil(focus(.countdown(endsAt: now.addingTimeInterval(-5))).nextShownChange(after: now),
                     "a countdown that ran out holds 0:00")
        XCTAssertNil(focus(.countUp(since: now.addingTimeInterval(-30 * 60))).nextShownChange(after: now),
                     "a timed count-up past its length holds 0:00")
    }

    func testARunningCountdownChangesOncePerSecond() {
        let countdown = focus(.countdown(endsAt: now.addingTimeInterval(90.5)))
        XCTAssertEqual(wakeups(of: countdown, over: 60), 60)
        XCTAssertEqual(wakeups(of: countdown, over: 200), 91, "the last wakeup shows 0:00, then it stops")
    }

    func testATimedCountUpChangesOncePerSecondUntilItsEnd() {
        let countUp = focus(.countUp(since: now.addingTimeInterval(-10)), length: 20)
        XCTAssertEqual(wakeups(of: countUp, over: 60), 10)
    }

    func testAnOpenEndedCountUpKeepsCounting() {
        XCTAssertEqual(wakeups(of: focus(.countUp(since: now.addingTimeInterval(-12.5)), length: nil), over: 60), 60)
        XCTAssertEqual(wakeups(of: focus(.countUp(since: now), length: nil), over: 10), 10,
                       "a stretch that starts now turns its first second right away")
    }
}
