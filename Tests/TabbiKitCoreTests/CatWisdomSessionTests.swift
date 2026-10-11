import XCTest
import TabbiKitCore

/// Building a Cat wisdom session from a study award and what the pet tracks.
final class CatWisdomSessionTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func time(day: Int, hour: Int = 14) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 5 + day, hour: hour))!
    }

    private func focus(_ minutes: Double, day: Int, hour: Int = 10) -> ActivityRecord {
        let end = time(day: day, hour: hour)
        return ActivityRecord(source: .focus, kind: .focusCompleted, start: end.addingTimeInterval(-minutes * 60),
                              end: end, quantity: minutes, unit: .minutes)
    }

    private func session(_ award: PetStudyAward, records: [ActivityRecord], lastCompletion: Date? = nil) -> CatWisdomSession? {
        let progress = PetMilestoneProgress(records: records, calendar: calendar)
        let now = time(day: 3)
        let streak = StudyStreak(studyDays: progress.studyDays, today: now, calendar: calendar)
        return CatWisdomSession(award: award, at: now, lastCompletion: lastCompletion, streak: streak,
                                progress: progress, calendar: calendar)
    }

    func testCompletedSessionNotYetLoggedCountsTowardStreakAndTotal() throws {
        let award = PetStudyAward(completedSessions: 1, minutes: 25, points: 35)
        let made = try XCTUnwrap(session(award, records: [focus(60, day: 1), focus(60, day: 2)]))
        XCTAssertEqual(made.outcome, .completed)
        XCTAssertEqual(made.streakDays, 3)
        XCTAssertEqual(made.totalFocusMinutes, 145)
        XCTAssertEqual(made.previousCompletion, calendar.startOfDay(for: time(day: 2)))
    }

    func testSessionAlreadyLoggedIsNotCountedTwice() throws {
        let award = PetStudyAward(completedSessions: 1, minutes: 25, points: 35)
        let made = try XCTUnwrap(session(award, records: [focus(60, day: 2), focus(25, day: 3, hour: 13)]))
        XCTAssertEqual(made.streakDays, 2)
        XCTAssertEqual(made.totalFocusMinutes, 85)
        // Today's own record is not the previous completion.
        XCTAssertEqual(made.previousCompletion, calendar.startOfDay(for: time(day: 2)))
    }

    func testEarlyStopAndSavedLastCompletion() throws {
        let award = PetStudyAward(completedSessions: 0, minutes: 12, points: 12)
        let made = try XCTUnwrap(session(award, records: [], lastCompletion: time(day: 0)))
        XCTAssertEqual(made.outcome, .stoppedWithPoints)
        XCTAssertEqual(made.streakDays, 0)
        XCTAssertEqual(made.previousCompletion, time(day: 0))
    }

    func testNoSessionWithoutPoints() {
        XCTAssertNil(session(PetStudyAward(completedSessions: 0, minutes: 2, points: 0), records: []))
    }
}
