import Foundation
import TabbiKitCore
import XCTest

final class StudyReminderSaveTests: XCTestCase {
    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar().date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func onAtSeven() -> StudyReminderSave {
        StudyReminderSave(settings: StudyReminderSettings(isEnabled: true, hour: 19, minute: 0))
    }

    func testANewSaveIsOff() {
        var save = StudyReminderSave()
        XCTAssertFalse(save.settings.isEnabled)
        XCTAssertNil(save.plan(now: date(9, hour: 9), studiedToday: false, goalMetToday: false, calendar: calendar()))
        XCTAssertNil(save.scheduledFor)
    }

    func testPlansTodayAndRemembersIt() {
        var save = onAtSeven()
        let fire = save.plan(now: date(9, hour: 9), studiedToday: false, goalMetToday: false, calendar: calendar())
        XCTAssertEqual(fire, date(9, hour: 19))
        XCTAssertEqual(save.scheduledFor, date(9, hour: 19))
        XCTAssertNil(save.lastDelivered)
    }

    func testAPassedPlanCountsAsDeliveredSoTheDayGetsNoSecond() {
        var save = onAtSeven()
        _ = save.plan(now: date(9, hour: 9), studiedToday: false, goalMetToday: false, calendar: calendar())
        // The user moves the time later the same evening, after 7 pm fired.
        save.settings.minuteOfDay = 22 * 60
        let fire = save.plan(now: date(9, hour: 20), studiedToday: false, goalMetToday: false, calendar: calendar())
        XCTAssertEqual(save.lastDelivered, date(9, hour: 19))
        XCTAssertEqual(fire, date(10, hour: 22))
    }

    func testStudyingWithdrawsTodaysPlanWithoutCountingIt() {
        var save = onAtSeven()
        _ = save.plan(now: date(9, hour: 9), studiedToday: false, goalMetToday: false, calendar: calendar())
        let fire = save.plan(now: date(9, hour: 15), studiedToday: true, goalMetToday: false, calendar: calendar())
        XCTAssertEqual(fire, date(10, hour: 19))
        XCTAssertNil(save.lastDelivered)
    }

    func testMeetingTheGoalWithdrawsTodaysPlan() {
        var save = onAtSeven()
        _ = save.plan(now: date(9, hour: 9), studiedToday: false, goalMetToday: false, calendar: calendar())
        XCTAssertEqual(save.plan(now: date(9, hour: 15), studiedToday: false, goalMetToday: true, calendar: calendar()),
                       date(10, hour: 19))
    }

    func testTurningItOffClearsThePlanButKeepsTheDelivery() {
        var save = onAtSeven()
        _ = save.plan(now: date(9, hour: 9), studiedToday: false, goalMetToday: false, calendar: calendar())
        save.settings.isEnabled = false
        XCTAssertNil(save.plan(now: date(9, hour: 21), studiedToday: false, goalMetToday: false, calendar: calendar()))
        XCTAssertNil(save.scheduledFor)
        XCTAssertEqual(save.lastDelivered, date(9, hour: 19))
        // Back on the same night: still none until tomorrow.
        save.settings.isEnabled = true
        save.settings.minuteOfDay = 23 * 60
        XCTAssertEqual(save.plan(now: date(9, hour: 21), studiedToday: false, goalMetToday: false, calendar: calendar()),
                       date(10, hour: 23))
    }

    func testRoundTripsThroughAFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("reminder.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertNil(try StudyReminderSave.load(from: url))
        var save = onAtSeven()
        _ = save.plan(now: date(9, hour: 9), studiedToday: false, goalMetToday: false, calendar: calendar())
        save.lastDelivered = date(8, hour: 19)
        try save.write(to: url)
        XCTAssertEqual(try StudyReminderSave.load(from: url), save)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(json[VersionedJSON.versionKey] as? Int, 1)
    }

    func testDamagedFieldsReadAsOff() throws {
        let data = Data(#"{"schemaVersion":1,"settings":"loud","scheduledFor":"soon"}"#.utf8)
        let save = try StudyReminderSave.schema.decode(StudyReminderSave.self, from: data)
        XCTAssertEqual(save, StudyReminderSave())
    }

    func testGoalMetReadsTheStudyFocusGoal() {
        let goal = StudyDailyGoal(minutes: 60)
        let halfway = goal.progressItem(for: StudyDayTally(minutes: 30, sessions: 1, points: 0))
        let done = goal.progressItem(for: StudyDayTally(minutes: 75, sessions: 3, points: 0))
        let cards = ProgressItem(id: "cards", source: .anki, title: "Cards", completed: 0, target: 0, unit: "cards")
        XCTAssertFalse(StudyReminder.goalMet(in: []))
        XCTAssertFalse(StudyReminder.goalMet(in: [cards, halfway]))
        XCTAssertTrue(StudyReminder.goalMet(in: [cards, done]))
    }
}

final class StudyReminderSpeakerTests: XCTestCase {
    func testANamedPetSpeaksByName() {
        var pet = PetProfile(name: "Mochi", breed: .orangeTabby)
        XCTAssertEqual(StudyReminder.speaker(for: pet), "Mochi")
        pet.rename("Pixel")
        XCTAssertEqual(StudyReminder.speaker(for: pet), "Pixel")
        XCTAssertEqual(StudyReminder.message(petName: StudyReminder.speaker(for: pet), streakLength: 0).title,
                       "Pixel misses you")
    }

    func testACatThatGoesByItsBreedIsYourCat() {
        let pet = PetProfile(name: "", breed: .britishShorthair)
        XCTAssertEqual(pet.name, PetBreed.britishShorthair.displayName)
        XCTAssertEqual(StudyReminder.speaker(for: pet), "Your cat")
    }
}
