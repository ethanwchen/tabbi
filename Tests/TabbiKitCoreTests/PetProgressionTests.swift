import Foundation
import TabbiKitCore
import XCTest

/// Badge tiers, monthly quests, the progression save and the mastery
/// outfits they unlock (docs/design/progression.md).
final class PetProgressionTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func focus(_ minutes: Double, on day: Date, outcome: StudyPhaseOutcome = .completed) -> ActivityRecord {
        ActivityRecord(source: "focus", kind: .focusCompleted, start: day.addingTimeInterval(-minutes * 60), end: day,
                       quantity: minutes, unit: .minutes, metadata: [ActivityMetadata.outcome: outcome.rawValue])
    }

    // MARK: Tracks

    func testEveryTrackHasFourRisingTiers() {
        for track in ProgressTrack.allCases {
            XCTAssertEqual(track.thresholds.count, ProgressTier.allCases.count, "\(track)")
            XCTAssertEqual(track.thresholds, track.thresholds.sorted(), "\(track)")
            XCTAssertEqual(Set(track.thresholds).count, 4, "\(track)")
            XCTAssertNil(track.tier(for: track.thresholds[0] - 1))
            XCTAssertEqual(track.tier(for: track.thresholds[0]), .bronze)
            XCTAssertEqual(track.tier(for: track.thresholds[3] * 2), .starlight)
            XCTAssertFalse(track.displayName.isEmpty)
            XCTAssertFalse(track.howToReach(track.thresholds[2]).isEmpty)
        }
        XCTAssertEqual(ProgressBadge.allCases.count, 48)
    }

    func testStarlightTakesMonthsEvenAtThreeHoursADay() {
        // Three hours of Pomodoro a day: 180 minutes, 7 finished blocks,
        // a study day and a streak day each day.
        let perDay: [ProgressTrack: Double] = [.focusHours: 180, .studyDays: 1, .gentleStreak: 1, .sessions: 7]
        for (track, pace) in perDay {
            let days = Double(track.goal(for: .starlight)) / pace
            XCTAssertGreaterThanOrEqual(days, 80, "\(track) Starlight in \(days) days")
        }
    }

    func testBadgeIDsRoundTrip() {
        for badge in ProgressBadge.allCases {
            XCTAssertEqual(ProgressBadge(id: badge.id), badge)
        }
        XCTAssertNil(ProgressBadge(id: "focusHours.5"))
        XCTAssertNil(ProgressBadge(id: "naps.1"))
        XCTAssertNil(ProgressBadge(id: "focusHours"))
        XCTAssertEqual(ProgressBadge(.focusHours, .gold).id, "focusHours.3")
    }

    func testProgressLabelsRoundDownAndStayShort() {
        XCTAssertEqual(ProgressTrack.focusHours.progressLabel(value: 119, goal: 600), "1/10 h")
        XCTAssertEqual(ProgressTrack.focusHours.progressLabel(value: 900, goal: 600), "10/10 h")
        XCTAssertEqual(ProgressTrack.cards.progressLabel(value: 4210, goal: 10_000), "4210/10k")
        XCTAssertEqual(ProgressTrack.cards.progressLabel(value: 12_900, goal: 50_000), "12k/50k")
        XCTAssertEqual(ProgressTrack.studyDays.progressLabel(value: -3, goal: 30), "0/30")
    }

    // MARK: Quests

    func testQuestHashIsFNV1a() {
        XCTAssertEqual(MonthlyQuests.hash(""), 0x811C_9DC5)
        XCTAssertEqual(MonthlyQuests.hash("a"), 0xE40C_292C)
        XCTAssertEqual(MonthlyQuests.hash("foobar"), 0xBF9C_F968)
    }

    func testANewUserGetsThreeFocusQuests() {
        let quests = MonthlyQuests.quests(for: MonthKey(rawValue: "2026-11")!, tally: ProgressTally())
        XCTAssertEqual(Set(quests.map(\.track)), Set(MonthlyQuests.core))
        XCTAssertEqual(quests.map(\.target), quests.map { MonthlyQuests.targets[$0.track]! })
    }

    func testExtrasJoinOnlyAfterTheUserDidThemBeforeTheMonth() {
        let cards = ActivityRecord(source: .anki, kind: .cardsReviewed, start: date(2026, 11, 5), quantity: 50, unit: .cards)
        let tally = ProgressTally(records: [cards], calendar: calendar)
        // Cards first reviewed in November: not offered in November.
        let november = MonthlyQuests.quests(for: MonthKey(rawValue: "2026-11")!, tally: tally)
        XCTAssertFalse(november.contains { $0.track == .cards })
        // In some later month they are in the pool; across a year some month picks them.
        var offered = false
        var month = MonthKey(rawValue: "2026-12")!
        for _ in 0..<12 {
            let quests = MonthlyQuests.quests(for: month, tally: tally)
            XCTAssertEqual(quests.count, 3)
            XCTAssertTrue(quests.contains { MonthlyQuests.core.contains($0.track) }, "\(month) has a focus quest")
            XCTAssertEqual(Set(quests.map(\.track)).count, 3)
            offered = offered || quests.contains { $0.track == .cards }
            month = month.next(calendar: calendar)
        }
        XCTAssertTrue(offered)
    }

    func testQuestsAreFixedForAMonth() {
        var records: [ActivityRecord] = []
        for track in [WaterTally.water(at: date(2026, 1, 3)), WaterTally.move(.stretch, at: date(2026, 1, 3))] {
            records.append(track)
        }
        let before = ProgressTally(records: records, calendar: calendar)
        records.append(ActivityRecord(source: .anki, kind: .cardsReviewed, start: date(2026, 11, 20), quantity: 9,
                                      unit: .cards))
        let after = ProgressTally(records: records, calendar: calendar)
        let november = MonthKey(rawValue: "2026-11")!
        XCTAssertEqual(MonthlyQuests.quests(for: november, tally: before), MonthlyQuests.quests(for: november, tally: after))
    }

    func testAMonthIsCompleteWhenAllThreeAreDone() {
        // A new user's November: 10 h, 10 study days and 20 sessions.
        var records: [ActivityRecord] = []
        for day in 1...10 {
            records.append(focus(30, on: date(2026, 11, day)))
            records.append(focus(30, on: date(2026, 11, day, hour: 15)))
        }
        var tally = ProgressTally(records: records, calendar: calendar)
        let november = MonthKey(rawValue: "2026-11")!
        XCTAssertTrue(MonthlyQuests.isComplete(november, tally: tally))
        XCTAssertEqual(MonthlyQuests.completedMonths(tally, through: date(2026, 11, 30), calendar: calendar), [november])
        XCTAssertEqual(MonthlyQuests.completedMonths(tally, through: date(2026, 10, 30), calendar: calendar), [],
                       "a month after today is not counted")
        // One short: 9 study days.
        tally = ProgressTally(records: records.filter { $0.end < date(2026, 11, 10, hour: 1) }, calendar: calendar)
        XCTAssertFalse(MonthlyQuests.isComplete(november, tally: tally))
        let progress = MonthlyQuests.progress(for: november, tally: tally)
        XCTAssertEqual(progress.first { $0.quest.track == .studyDays }?.value, 9)
        XCTAssertEqual(progress.first { $0.quest.track == .studyDays }?.label, "9/10")
    }

    // MARK: Progression

    func testRefreshReachesTiersOnceAndReportsOnlyNewOnes() {
        var progression = PetProgression()
        for day in 1...7 { progression.add(focus(100, on: date(2026, 11, day)), calendar: calendar) }
        let first = progression.refresh(at: date(2026, 11, 7), calendar: calendar)
        XCTAssertTrue(first.badges.contains(ProgressBadge(.focusHours, .bronze)), "700 minutes is past 10 h")
        XCTAssertTrue(first.badges.contains(ProgressBadge(.studyDays, .bronze)))
        XCTAssertTrue(first.badges.contains(ProgressBadge(.gentleStreak, .bronze)))
        XCTAssertEqual(progression.tier(of: .focusHours), .bronze)
        XCTAssertEqual(progression.nextTier(of: .focusHours), .silver)
        XCTAssertEqual(progression.value(of: .focusHours), 700)
        XCTAssertEqual(progression.progress(of: ProgressBadge(.focusHours, .silver)).label, "11/50 h")
        XCTAssertEqual(progression.refresh(at: date(2026, 11, 7), calendar: calendar), PetProgression.Change())
        XCTAssertEqual(progression.unseen, Set(first.badges))
        XCTAssertTrue(progression.markSeen())
        XCTAssertFalse(progression.markSeen())
        XCTAssertEqual(progression.unseen, [])
    }

    func testTheSaveKeepsProgressWhenTheLogIsGone() throws {
        var progression = PetProgression()
        for day in 1...30 { progression.add(focus(30, on: date(2026, 10, day)), calendar: calendar) }
        progression.refresh(at: date(2026, 10, 30), calendar: calendar)
        XCTAssertEqual(progression.tier(of: .studyDays), .silver)

        // Day files deleted: a new launch reads an empty log.
        let data = try progression.save.encoded()
        let saved = try ProgressionSave.schema.decode(ProgressionSave.self, from: data, using: Self.decoder)
        var relaunched = PetProgression(save: saved)
        relaunched.add(focus(30, on: date(2026, 11, 2)), calendar: calendar)
        relaunched.refresh(at: date(2026, 11, 2), calendar: calendar)
        XCTAssertEqual(relaunched.value(of: .studyDays), 30, "the best count stays")
        XCTAssertEqual(relaunched.tier(of: .studyDays), .silver)
        XCTAssertTrue(relaunched.isReached(ProgressBadge(.studyDays, .silver)))
    }

    func testMonthlyQuestsBadgeCountsSavedMonths() {
        var progression = PetProgression(save: ProgressionSave(completedMonths: [MonthKey(rawValue: "2026-01")!,
                                                                                MonthKey(rawValue: "2026-03")!]))
        progression.refresh(at: date(2026, 11, 1), calendar: calendar)
        XCTAssertEqual(progression.value(of: .monthlyQuests), 2)
        XCTAssertEqual(progression.tier(of: .monthlyQuests), .bronze)
    }

    func testACompletedMonthIsReportedAndSaved() {
        var progression = PetProgression()
        for day in 1...10 {
            progression.add(focus(30, on: date(2026, 11, day)), calendar: calendar)
            progression.add(focus(30, on: date(2026, 11, day, hour: 15)), calendar: calendar)
        }
        let change = progression.refresh(at: date(2026, 11, 12), calendar: calendar)
        XCTAssertEqual(change.months, [MonthKey(rawValue: "2026-11")!])
        XCTAssertTrue(change.badges.contains(ProgressBadge(.monthlyQuests, .bronze)))
        XCTAssertEqual(progression.save.completedMonths, [MonthKey(rawValue: "2026-11")!])
    }

    // MARK: Save

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func testSaveRoundTripsWithItsVersion() throws {
        let save = ProgressionSave(best: [.focusHours: 1234, .cards: 0], reached: [ProgressBadge(.focusHours, .silver):
                                                                                    Date(timeIntervalSince1970: 1_800_000_000)],
                                   completedMonths: [MonthKey(rawValue: "2026-10")!],
                                   seen: [ProgressBadge(.focusHours, .silver), ProgressBadge(.cards, .gold)])
        XCTAssertEqual(save.best, [.focusHours: 1234], "zero counts are not kept")
        XCTAssertEqual(save.seen, [ProgressBadge(.focusHours, .silver)], "only reached tiers can be seen")
        let data = try save.encoded()
        XCTAssertEqual(VersionedJSON.version(of: data), 1)
        XCTAssertEqual(try ProgressionSave.schema.decode(ProgressionSave.self, from: data, using: Self.decoder), save)
    }

    func testAFileWithoutAVersionReadsAsVersionOne() throws {
        let json = #"{"best":{"studyDays":31},"reached":{"studyDays.2":"2026-10-30T03:00:00Z"},"completedMonths":["2026-10"],"seen":[]}"#
        let save = try ProgressionSave.schema.decode(ProgressionSave.self, from: Data(json.utf8), using: Self.decoder)
        XCTAssertEqual(save.best, [.studyDays: 31])
        XCTAssertEqual(save.reached.keys.map(\.id), ["studyDays.2"])
        XCTAssertEqual(save.completedMonths, [MonthKey(rawValue: "2026-10")!])
    }

    func testANewerFileKeepsWhatThisBuildKnows() throws {
        let json = #"""
        {"schemaVersion":3,"best":{"focusHours":90,"naps":4},"reached":{"focusHours.1":"2026-10-30T03:00:00Z","naps.1":"2026-10-30T03:00:00Z","focusHours.9":"2026-10-30T03:00:00Z"},
         "completedMonths":["2026-10","2026-13","later"],"seen":["focusHours.1","naps.1"],"rooms":{"desk":true}}
        """#
        let save = try ProgressionSave.schema.decode(ProgressionSave.self, from: Data(json.utf8), using: Self.decoder)
        XCTAssertEqual(save.best, [.focusHours: 90])
        XCTAssertEqual(Set(save.reached.keys), [ProgressBadge(.focusHours, .bronze)])
        XCTAssertEqual(save.completedMonths, [MonthKey(rawValue: "2026-10")!])
        XCTAssertEqual(save.seen, [ProgressBadge(.focusHours, .bronze)])
    }

    func testBrokenFieldsReadAsEmpty() throws {
        let json = #"{"schemaVersion":1,"best":"lots","reached":[1,2],"completedMonths":{"a":1}}"#
        XCTAssertEqual(try ProgressionSave.schema.decode(ProgressionSave.self, from: Data(json.utf8), using: Self.decoder),
                       ProgressionSave())
    }

    func testLoadAndWrite() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Pet/progression.json")
        XCTAssertNil(try ProgressionSave.load(from: url))
        let save = ProgressionSave(best: [.water: 21], reached: [ProgressBadge(.water, .bronze): Date(timeIntervalSince1970: 0)])
        try save.write(to: url)
        XCTAssertEqual(try ProgressionSave.load(from: url), save)
        try Data("not json".utf8).write(to: url)
        XCTAssertThrowsError(try ProgressionSave.load(from: url))
    }

    // MARK: Mastery outfits

    func testMasteryOutfitsAreHardEarnedAndNeverSold() {
        let editions = PetLimitedEdition.mastery
        XCTAssertGreaterThanOrEqual(editions.count, 12)
        XCTAssertEqual(Set(editions.compactMap(\.masteryBadge)).count, editions.count, "one outfit per badge tier")
        for edition in editions {
            let item = edition.item
            let badge = try? XCTUnwrap(edition.masteryBadge)
            XCTAssertGreaterThanOrEqual(badge?.tier ?? .bronze, .silver, "\(item) is a long goal")
            XCTAssertTrue(item.isLimited)
            XCTAssertFalse(item.isFree)
            XCTAssertEqual(item.cost, 0)
            XCTAssertFalse(PetCloset.wardrobe.contains(item))
            XCTAssertFalse(PetCloset.limitedShelf.contains(item))
            XCTAssertTrue(PetCloset.masteryShelf.contains(item))
            XCTAssertEqual(edition.howToEarn, badge?.howToEarn)
            XCTAssertNotEqual(item, .accessory(.kingsCape))
            if case .accessory(let accessory) = item { XCTAssertNotEqual(accessory.slot, .back, "no capes or wings") }
        }
    }

    func testMasteryOutfitsUnlockWithTheirTierAndCannotBeBought() {
        var closet = PetCloset(save: PetSave(profile: PetProfile(name: "Mochi", breed: .tuxedo),
                                             ledger: PetPointsLedger(earned: 100_000)))
        let robe = PetItem.outfit(.apprenticeRobe)
        XCTAssertEqual(closet.state(of: robe), .unearned)
        XCTAssertEqual(closet.tap(robe), .notEarnedYet)
        XCTAssertFalse(closet.save.ledger.canBuy(robe))

        var progression = PetProgression()
        for index in 0..<50 { progression.add(focus(25, on: date(2026, 11, 1).addingTimeInterval(Double(index) * 3600)),
                                              calendar: calendar) }
        progression.refresh(at: date(2026, 11, 4), calendar: calendar)
        XCTAssertEqual(closet.unlockMastery(progression), [robe])
        XCTAssertEqual(closet.unlockMastery(progression), [], "an outfit unlocks once")
        XCTAssertEqual(closet.tap(robe), .wore)
        XCTAssertEqual(closet.balance, 100_000, "nothing was spent")
        XCTAssertEqual(closet.applyGrants([PetItem.outfit(.sagesRobe).id]), [], "the server never grants one")
    }

    func testTheDemoShowsAShelfPartWay() {
        let progression = PetProgression.demo(today: date(2026, 11, 20), calendar: calendar)
        XCTAssertEqual(progression.unseen, [])
        let earned = PetLimitedEdition.mastery.filter { progression.isReached($0.masteryBadge!) }.map(\.item)
        XCTAssertEqual(Set(earned), [.accessory(.littleSprout), .outfit(.apprenticeRobe), .accessory(.explorersHat)])
        XCTAssertGreaterThan(progression.reachedCount, 8)
        XCTAssertLessThan(progression.reachedCount, 24)
        XCTAssertEqual(progression.quests(at: date(2026, 11, 20), calendar: calendar).count, 3)
    }
}
