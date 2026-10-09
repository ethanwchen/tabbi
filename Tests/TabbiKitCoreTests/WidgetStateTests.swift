import XCTest
@testable import TabbiKitCore

final class WidgetStateTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func day(_ key: String) throws -> PlannerDayKey {
        try XCTUnwrap(PlannerDayKey(rawValue: key))
    }

    /// 2026-10-`day` at `hour`:`minute` UTC.
    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func state(timer: WidgetState.Timer? = nil) throws -> WidgetState {
        WidgetState(pet: .starter(.cat), day: try day("2026-10-09"), focusMinutes: 50, streakDays: 3,
                    lastFocusDay: try day("2026-10-09"), timer: timer)
    }

    // MARK: Shown at a date

    func testMinutesResetAtMidnight() throws {
        let state = try state()
        XCTAssertEqual(state.minutes(at: date(23, 59), calendar: calendar), 50)
        XCTAssertEqual(state.minutes(at: date(0, 1, day: 10), calendar: calendar), 0)
    }

    func testStreakHoldsThroughTheNextDayThenBreaks() throws {
        let state = try state()
        XCTAssertEqual(state.streak(at: date(12), calendar: calendar), 3)
        XCTAssertEqual(state.streak(at: date(12, day: 10), calendar: calendar), 3)
        XCTAssertEqual(state.streak(at: date(0, 1, day: 11), calendar: calendar), 0)
        var fresh = state
        fresh.lastFocusDay = nil
        XCTAssertEqual(fresh.streak(at: date(12), calendar: calendar), 0)
    }

    func testCountdownDisappearsOnceItRunsOut() throws {
        let running = try state(timer: .init(phase: .focus, label: "Focus", clock: .countdown(endsAt: date(10, 25))))
        XCTAssertNotNil(running.timer(at: date(10, 24)))
        XCTAssertNil(running.timer(at: date(10, 25)))
        let paused = try state(timer: .init(phase: .rest, label: "Break", clock: .paused(shown: 120)))
        XCTAssertEqual(paused.timer(at: date(23))?.label, "Break")
    }

    func testChangeDatesAreTheCountdownEndAndMidnight() throws {
        let running = try state(timer: .init(phase: .focus, label: "Focus", clock: .countdown(endsAt: date(10, 25))))
        XCTAssertEqual(running.changeDates(after: date(10), calendar: calendar), [date(10, 25), date(0, day: 10)])
        XCTAssertEqual(running.changeDates(after: date(11), calendar: calendar), [date(0, day: 10)])
        let counting = try state(timer: .init(phase: .focus, label: "Focus", clock: .countUp(since: date(9))))
        XCTAssertEqual(counting.changeDates(after: date(10), calendar: calendar), [date(0, day: 10)])
    }

    // MARK: Timer from the shared clock

    func testTimerFollowsTheProvidedFocusClock() {
        let idle = ProvidedFocus(source: .focus, phase: .focus, clock: .idle, phaseLength: 1500)
        XCTAssertNil(WidgetState.Timer(idle))
        let running = ProvidedFocus(source: .focus, phase: .rest, label: "Long break",
                                    clock: .countdown(endsAt: date(10, 15)), phaseLength: 900)
        XCTAssertEqual(WidgetState.Timer(running),
                       .init(phase: .rest, label: "Long break", clock: .countdown(endsAt: date(10, 15))))
    }

    // MARK: Streak

    func testStreakCountsConsecutiveDaysEndingOnTheLatestFocusDay() throws {
        let days: Set = [try day("2026-10-05"), try day("2026-10-07"), try day("2026-10-08"), try day("2026-10-09")]
        let today = WidgetState.streak(focusDays: days, today: try day("2026-10-09"), calendar: calendar)
        XCTAssertEqual(today.days, 3)
        XCTAssertEqual(today.last, try day("2026-10-09"))
        let earlier = WidgetState.streak(focusDays: days, today: try day("2026-10-07"), calendar: calendar)
        XCTAssertEqual(earlier.days, 1)
        let acrossMonths = WidgetState.streak(focusDays: [try day("2026-09-30"), try day("2026-10-01")],
                                              today: try day("2026-10-01"), calendar: calendar)
        XCTAssertEqual(acrossMonths.days, 2)
        let none = WidgetState.streak(focusDays: [], today: try day("2026-10-09"), calendar: calendar)
        XCTAssertEqual(none.days, 0)
        XCTAssertNil(none.last)
    }

    // MARK: File

    func testFileRoundTripsAndSkipsUnchangedWrites() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetStateTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = WidgetStateFile(folder: folder)
        XCTAssertNil(file.read())

        // A fractional end second must not make every write look like a change.
        var state = try state(timer: .init(phase: .focus, label: "Focus",
                                           clock: .countdown(endsAt: date(10, 25).addingTimeInterval(0.4))))
        state.pet.outfit = .allCases.last ?? .none
        XCTAssertTrue(try file.write(state))
        XCTAssertEqual(file.read(), state)
        XCTAssertFalse(try file.write(state))

        state.timer = nil
        XCTAssertTrue(try file.write(state))
        XCTAssertNil(file.read()?.timer)
    }

    func testFileRecordsItsSchemaVersion() throws {
        let data = try state().encoded()
        XCTAssertEqual(VersionedJSON.version(of: data), WidgetState.schema.current)
    }

    func testUnreadableFileReadsAsNothing() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetStateTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = WidgetStateFile(folder: folder)
        try Data("not json".utf8).write(to: file.url)
        XCTAssertNil(file.read())
    }
}
