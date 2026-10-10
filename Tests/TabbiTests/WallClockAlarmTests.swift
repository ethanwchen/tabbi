import AppKit
import XCTest
@testable import TabbiKit

/// The phase-end and ticker alarm: goes off once at its moment, can be
/// replaced or cancelled, and survives the Mac waking without going off early.
@MainActor
final class WallClockAlarmTests: XCTestCase {
    private func spin(for seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testGoesOffOnceAtItsMoment() {
        var fired = 0
        let alarm = WallClockAlarm { fired += 1 }
        alarm.schedule(at: Date().addingTimeInterval(0.05))
        XCTAssertEqual(fired, 0)
        spin(for: 0.3)
        XCTAssertEqual(fired, 1)
        XCTAssertNil(alarm.date)
    }

    func testAPastMomentGoesOffRightAway() {
        var fired = 0
        let alarm = WallClockAlarm { fired += 1 }
        alarm.schedule(at: Date().addingTimeInterval(-600))
        spin(for: 0.05)
        XCTAssertEqual(fired, 1)
    }

    func testSchedulingAgainReplacesTheEarlierMoment() {
        var fired = 0
        let alarm = WallClockAlarm { fired += 1 }
        alarm.schedule(at: Date().addingTimeInterval(0.05))
        let later = Date().addingTimeInterval(3600)
        alarm.schedule(at: later)
        spin(for: 0.3)
        XCTAssertEqual(fired, 0)
        XCTAssertEqual(alarm.date, later)
    }

    func testCancelTurnsItOff() {
        var fired = 0
        let alarm = WallClockAlarm { fired += 1 }
        alarm.schedule(at: Date().addingTimeInterval(0.05))
        alarm.cancel()
        spin(for: 0.3)
        XCTAssertEqual(fired, 0)
        XCTAssertNil(alarm.date)
    }

    /// Waking re-arms the alarm against the wall clock: a moment still ahead
    /// stays set and does not go off early, and a cancelled one stays off.
    func testWakingKeepsAFutureMomentAndACancelledOneOff() {
        var fired = 0
        let alarm = WallClockAlarm { fired += 1 }
        let later = Date().addingTimeInterval(3600)
        alarm.schedule(at: later)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared)
        spin(for: 0.1)
        XCTAssertEqual(fired, 0)
        XCTAssertEqual(alarm.date, later)

        let cancelled = WallClockAlarm { fired += 1 }
        cancelled.schedule(at: later)
        cancelled.cancel()
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared)
        spin(for: 0.1)
        XCTAssertEqual(fired, 0)
    }
}
