import Foundation
import TabbiKitCore
import XCTest

/// Buying extra streak freezes with points, keeping them in the pet save
/// and through a sync.
final class StreakFreezePurchaseTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.firstWeekday = 2
        return calendar
    }

    /// Noon on a day of October 2026 (Monday the 12th starts a week).
    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!
    }

    private func studyDays(_ days: [Int]) -> [PlannerDayKey] {
        days.map { PlannerDayKey(date: date($0), calendar: calendar) }
    }

    private func streak(_ ledger: PetPointsLedger, studied days: [Int], today: Int) -> StudyStreak {
        StudyStreak(studyDays: studyDays(days), freezePurchases: ledger.streakFreezes,
                    today: date(today), calendar: calendar)
    }

    // MARK: Buying

    func testBuyingAFreezeSpendsItsPriceAndHoldsIt() throws {
        var ledger = PetPointsLedger(earned: 300)
        try ledger.buyStreakFreeze(for: streak(ledger, studied: [12, 13], today: 14), at: date(14))
        XCTAssertEqual(ledger.balance, 300 - StreakFreezeRules.price)
        XCTAssertEqual(ledger.streakFreezes, [date(14)])
        XCTAssertEqual(streak(ledger, studied: [12, 13], today: 14).extraFreezes, 1)
    }

    func testBuyingWithoutEnoughPointsSaysHowManyAreMissing() {
        var ledger = PetPointsLedger(earned: 100)
        XCTAssertThrowsError(try ledger.buyStreakFreeze(for: streak(ledger, studied: [13], today: 14), at: date(14))) {
            XCTAssertEqual($0 as? StreakFreezePurchaseError, .notEnoughPoints(missing: StreakFreezeRules.price - 100))
        }
        XCTAssertEqual(ledger.balance, 100, "a failed purchase spends nothing")
        XCTAssertTrue(ledger.streakFreezes.isEmpty)
    }

    func testBuyingStopsAtTheHoldingLimit() throws {
        var ledger = PetPointsLedger(earned: 1000)
        for _ in 0..<StreakFreezeRules.maxHeld {
            try ledger.buyStreakFreeze(for: streak(ledger, studied: [13], today: 14), at: date(14))
        }
        let balance = ledger.balance
        XCTAssertThrowsError(try ledger.buyStreakFreeze(for: streak(ledger, studied: [13], today: 14), at: date(14))) {
            XCTAssertEqual($0 as? StreakFreezePurchaseError, .holdingLimit)
        }
        XCTAssertEqual(ledger.balance, balance)
    }

    func testAUsedFreezeMakesRoomForAnother() throws {
        var ledger = PetPointsLedger(earned: 1000)
        // Two extras bought on Monday the 12th, then Tuesday and Wednesday
        // missed: the week's free freeze covers one, an extra the other.
        try ledger.buyStreakFreeze(for: streak(ledger, studied: [12], today: 12), at: date(12))
        try ledger.buyStreakFreeze(for: streak(ledger, studied: [12], today: 12), at: date(12))
        let later = streak(ledger, studied: [12, 15], today: 15)
        XCTAssertEqual(later.length, 2)
        XCTAssertEqual(later.extraFreezes, 1)
        XCTAssertTrue(later.canBuyFreeze)
        try ledger.buyStreakFreeze(for: later, at: date(15))
        XCTAssertEqual(streak(ledger, studied: [12, 15], today: 15).extraFreezes, 2)
    }

    // MARK: Closet

    func testTheClosetBuysAgainstItsOwnStudyDays() throws {
        let records = [12, 13].map { day in
            ActivityRecord(source: .focus, kind: .focusCompleted, start: date(day).addingTimeInterval(-25 * 60),
                           end: date(day), quantity: 25, unit: .minutes)
        }
        let progress = PetMilestoneProgress(records: records, calendar: calendar)
        var closet = PetCloset(save: PetSave(profile: PetProfile(name: "Mochi", breed: .britishShorthair),
                                             ledger: PetPointsLedger(earned: 200)))
        XCTAssertEqual(closet.streak(progress, today: date(14), calendar: calendar).length, 2)
        try closet.buyStreakFreeze(progress, at: date(14), calendar: calendar)
        XCTAssertEqual(closet.balance, 200 - StreakFreezeRules.price)
        XCTAssertEqual(closet.streak(progress, today: date(14), calendar: calendar).freezesReady, 2)
    }

    // MARK: Saving

    func testFreezesSurviveTheSaveFile() throws {
        var ledger = PetPointsLedger(earned: 300)
        try ledger.buyStreakFreeze(for: streak(ledger, studied: [13], today: 14), at: date(14))
        let save = PetSave(profile: PetProfile(name: "Mochi", breed: .britishShorthair), ledger: ledger)
        let decoded = try PetSave.decode(save.encoded())
        XCTAssertEqual(decoded.ledger.streakFreezes, [date(14)])
        XCTAssertEqual(decoded.ledger.balance, ledger.balance)
    }

    func testOlderSavesWithoutFreezesStillLoad() throws {
        let json = Data(#"{"earned": 50, "spent": 10, "purchased": []}"#.utf8)
        let ledger = try JSONDecoder().decode(PetPointsLedger.self, from: json)
        XCTAssertTrue(ledger.streakFreezes.isEmpty)
        XCTAssertEqual(ledger.balance, 40)
    }

    func testASaveWithoutFreezesWritesNoFreezeKey() throws {
        let data = try JSONEncoder().encode(PetPointsLedger(earned: 50))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("streakFreezes"))
    }

    func testAnUnreadableFreezeListIsDroppedNotTheLedger() throws {
        let json = Data(#"{"earned": 50, "spent": 0, "streakFreezes": "soon"}"#.utf8)
        let ledger = try JSONDecoder().decode(PetPointsLedger.self, from: json)
        XCTAssertTrue(ledger.streakFreezes.isEmpty)
        XCTAssertEqual(ledger.balance, 50)
    }

    // MARK: Sync

    func testAdoptingASyncedLedgerKeepsTheFreezesBoughtHere() throws {
        var ledger = PetPointsLedger(earned: 300)
        try ledger.buyStreakFreeze(for: streak(ledger, studied: [13], today: 14), at: date(14))
        let local = PetSave(profile: PetProfile(name: "Mochi", breed: .britishShorthair), ledger: ledger)
        let synced = SyncDocument.empty.recording(local, changedAt: date(14), device: "mac")
        let adopted = synced.applied(to: local)
        XCTAssertEqual(adopted.ledger.streakFreezes, [date(14)])
        XCTAssertEqual(adopted.ledger.balance, local.ledger.balance, "the freeze is paid for once")
    }
}
