import Foundation
import TabbiKitCore
import XCTest

final class StudyReminderTests: XCTestCase {
    private func calendar(_ zone: String = "America/New_York") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ day: Int, month: Int = 10, hour: Int, minute: Int = 0,
                      in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private let sevenPM = StudyReminderSettings(isEnabled: true, hour: 19, minute: 0)

    private func next(_ settings: StudyReminderSettings? = nil, now: Date, studied: Bool = false,
                      goalMet: Bool = false, delivered: Date? = nil, calendar: Calendar) -> Date? {
        StudyReminder.nextFireDate(settings: settings ?? sevenPM, now: now, studiedToday: studied,
                                   goalMetToday: goalMet, lastDelivered: delivered, calendar: calendar)
    }

    // MARK: Settings

    func testRemindersAreOffByDefault() {
        XCTAssertFalse(StudyReminderSettings.off.isEnabled)
        XCTAssertEqual(StudyReminderSettings.off.hour, 19)
        XCTAssertEqual(StudyReminderSettings.off.minute, 0)
    }

    func testTimeIsClampedToOneDay() {
        XCTAssertEqual(StudyReminderSettings(isEnabled: true, minuteOfDay: -5).minuteOfDay, 0)
        XCTAssertEqual(StudyReminderSettings(isEnabled: true, minuteOfDay: 5000).minuteOfDay, 1439)
        var settings = sevenPM
        settings.minuteOfDay = 2000
        XCTAssertEqual(settings.minuteOfDay, 1439)
    }

    func testSettingsRoundTripAndReadLeniently() throws {
        let settings = StudyReminderSettings(isEnabled: true, hour: 8, minute: 30)
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(StudyReminderSettings.self, from: data), settings)

        let damaged = Data(#"{"isEnabled":"yes","minuteOfDay":99999}"#.utf8)
        let read = try JSONDecoder().decode(StudyReminderSettings.self, from: damaged)
        XCTAssertFalse(read.isEnabled)
        XCTAssertEqual(read.minuteOfDay, 1439)
        XCTAssertEqual(try JSONDecoder().decode(StudyReminderSettings.self, from: Data("{}".utf8)), .off)
    }

    // MARK: When it fires

    func testOffNeverFires() {
        let calendar = calendar()
        XCTAssertNil(next(.off, now: date(14, hour: 9, in: calendar), calendar: calendar))
    }

    func testFiresTodayWhenNotStudiedYet() {
        let calendar = calendar()
        XCTAssertEqual(next(now: date(14, hour: 9, in: calendar), calendar: calendar),
                       date(14, hour: 19, in: calendar))
    }

    func testStudyingTodaySkipsToTomorrow() {
        let calendar = calendar()
        XCTAssertEqual(next(now: date(14, hour: 9, in: calendar), studied: true, calendar: calendar),
                       date(15, hour: 19, in: calendar))
    }

    func testMeetingTheGoalSkipsToTomorrow() {
        let calendar = calendar()
        XCTAssertEqual(next(now: date(14, hour: 9, in: calendar), goalMet: true, calendar: calendar),
                       date(15, hour: 19, in: calendar))
    }

    func testAfterTheTimePassedItWaitsForTomorrow() {
        let calendar = calendar()
        XCTAssertEqual(next(now: date(14, hour: 19, in: calendar), calendar: calendar),
                       date(15, hour: 19, in: calendar))
        XCTAssertEqual(next(now: date(14, hour: 21, in: calendar), calendar: calendar),
                       date(15, hour: 19, in: calendar))
    }

    func testNeverTwiceADayEvenWhenTheTimeMovesLater() {
        let calendar = calendar()
        let delivered = date(14, hour: 19, in: calendar)
        let later = StudyReminderSettings(isEnabled: true, hour: 22, minute: 0)
        XCTAssertEqual(next(later, now: date(14, hour: 20, in: calendar), delivered: delivered, calendar: calendar),
                       date(15, hour: 22, in: calendar))
    }

    func testYesterdaysDeliveryDoesNotBlockToday() {
        let calendar = calendar()
        XCTAssertEqual(next(now: date(14, hour: 9, in: calendar),
                            delivered: date(13, hour: 19, in: calendar), calendar: calendar),
                       date(14, hour: 19, in: calendar))
    }

    func testMidnightReminder() {
        let calendar = calendar()
        let midnight = StudyReminderSettings(isEnabled: true, minuteOfDay: 0)
        XCTAssertEqual(next(midnight, now: date(14, hour: 9, in: calendar), calendar: calendar),
                       date(15, hour: 0, in: calendar))
    }

    func testUsesTheLocalDayOfTheCalendarsTimeZone() {
        // 23:30 in New York on the 14th is already the 15th in Tokyo.
        let newYork = calendar()
        let tokyo = calendar("Asia/Tokyo")
        let now = date(14, hour: 23, minute: 30, in: newYork)
        XCTAssertEqual(next(now: now, calendar: newYork), date(15, hour: 19, in: newYork))
        XCTAssertEqual(next(now: now, calendar: tokyo), date(15, hour: 19, in: tokyo))
        // A delivery on the 14th in New York is the 15th in Tokyo too.
        XCTAssertEqual(next(now: now, delivered: now, calendar: tokyo), date(16, hour: 19, in: tokyo))
    }

    func testKeepsTheWallClockTimeAcrossDaylightSaving() {
        // Clocks fall back on November 1, 2026 in New York.
        let calendar = calendar()
        let fire = next(now: date(31, hour: 20, in: calendar), calendar: calendar)!
        XCTAssertEqual(calendar.component(.hour, from: fire), 19)
        XCTAssertEqual(calendar.component(.day, from: fire), 1)
        XCTAssertEqual(fire.timeIntervalSince(date(31, hour: 19, in: calendar)), 25 * 3600)
    }

    func testATimeSkippedBySpringForwardMovesToTheNextValidMoment() {
        // 2:30 doesn't exist on March 8, 2026 in New York; 3:00 does.
        let calendar = calendar()
        let twoThirty = StudyReminderSettings(isEnabled: true, hour: 2, minute: 30)
        let fire = StudyReminder.fireDate(on: PlannerDayKey(rawValue: "2026-03-08")!, settings: twoThirty,
                                          calendar: calendar)!
        XCTAssertEqual(calendar.component(.day, from: fire), 8)
        XCTAssertEqual(calendar.component(.hour, from: fire), 3)
    }

    // MARK: What it says

    func testMessageUsesThePetsName() {
        XCTAssertEqual(StudyReminder.message(petName: "Mochi", streakLength: 0),
                       .init(title: "Mochi misses you", body: "10 minutes?"))
    }

    func testMessageMentionsARunningStreak() {
        XCTAssertEqual(StudyReminder.message(petName: "Mochi", streakLength: 6).body,
                       "10 minutes? That keeps your 6-day streak going.")
    }

    func testMessageWithoutAPetName() {
        XCTAssertEqual(StudyReminder.message(petName: "  ", streakLength: 0).title, "Tabbi misses you")
        XCTAssertEqual(StudyReminder.message(petName: nil, streakLength: 0).title, "Tabbi misses you")
    }
}
