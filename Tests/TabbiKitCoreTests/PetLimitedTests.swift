import Foundation
import TabbiKitCore
import XCTest

final class PetLimitedTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func day(_ offset: Int, hour: Int = 10) -> Date {
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: hour))!
        return calendar.date(byAdding: .day, value: offset, to: start)!
    }

    private func focus(minutes: Double, on date: Date, source: ModuleID = .focus,
                       outcome: StudyPhaseOutcome = .completed) -> ActivityRecord {
        ActivityRecord(source: source, kind: .focusCompleted, start: date.addingTimeInterval(-minutes * 60), end: date,
                       quantity: minutes, unit: .minutes,
                       metadata: [ActivityMetadata.outcome: outcome.rawValue])
    }

    // MARK: Catalog

    private struct ServerLimitedItem: Decodable {
        var id: String
        var source: String
        var event: String?
        var milestone: String?
        var season: String?
    }

    /// The server grants exactly the limited items the app can show, with the same source, so an admin
    /// grant always lands on a real item and never on a shop item.
    func testServerGrantListMatchesTheLimitedEditions() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("backend/shared/limited-items.json")
        struct File: Decodable { var items: [ServerLimitedItem] }
        let server = try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).items
        XCTAssertEqual(server.map(\.id), PetLimitedEdition.allCases.map(\.item.id))
        for (entry, edition) in zip(server, PetLimitedEdition.allCases) {
            switch edition.source {
            case .event(let id):
                XCTAssertEqual(entry.source, "event", entry.id)
                XCTAssertEqual(entry.event, id, entry.id)
            case .milestone(let milestone):
                XCTAssertEqual(entry.source, "milestone", entry.id)
                XCTAssertEqual(entry.milestone, milestone.rawValue, entry.id)
            case .season(let id):
                XCTAssertEqual(entry.source, "season", entry.id)
                XCTAssertEqual(entry.season, id, entry.id)
            }
        }
    }

    func testLimitedItemsAreNeverSoldOrFree() {
        for edition in PetLimitedEdition.allCases {
            let item = edition.item
            XCTAssertTrue(item.isLimited)
            XCTAssertFalse(item.isFree, "\(item) must be earned, not owned from the start")
            XCTAssertFalse(PetCloset.wardrobe.contains(item))
            XCTAssertFalse(PetItemTheme.allCases.contains { $0.items.contains(item) })
            XCTAssertFalse(item.isNew)
            XCTAssertEqual(PetItem(id: item.id), item)
            XCTAssertFalse(edition.howToEarn.isEmpty)
        }
        XCTAssertEqual(PetCloset.limitedShelf, PetLimitedEdition.allCases.map(\.item))
        XCTAssertEqual(Array(PetItem.allCases.suffix(PetLimitedEdition.allCases.count)), PetCloset.limitedShelf)
        XCTAssertEqual(PetItem.shopItems + PetCloset.limitedShelf, PetItem.allCases)
    }

    func testEveryMilestoneHasOneItemAndTheCapIsTheLaunchWeekEvent() {
        let milestones = PetLimitedEdition.allCases.compactMap(\.milestone)
        XCTAssertEqual(Set(milestones), Set(PetMilestone.allCases))
        XCTAssertEqual(milestones.count, PetMilestone.allCases.count)
        XCTAssertEqual(PetLimitedEdition.launchWeekCap.source, .event(id: "launch-week"))
        XCTAssertEqual(PetLimitedEdition.launchWeekCap.item, .accessory(.backwardsCap))
    }

    func testLimitedCopyNeverMentionsPayment() {
        let words = ["buy", "pay", "price", "donat", "purchase", "$", "money", "point"]
        for edition in PetLimitedEdition.allCases {
            let text = edition.howToEarn.lowercased()
            for word in words {
                XCTAssertFalse(text.contains(word), "\(edition) mentions \(word)")
            }
        }
    }

    func testEffectsAreDeclaredForMilestoneItems() {
        XCTAssertNil(PetItem.accessory(.beanie).effect)
        XCTAssertEqual(PetItem.accessory(.flameHeadband).effect, .flicker)
        XCTAssertEqual(PetItem.accessory(.goldenLaurel).effect, .shimmer)
        XCTAssertEqual(PetItem.accessory(.teamMedal).effect, .sparkle)
        XCTAssertEqual(PetItem.accessory(.backwardsCap).effect, .sparkle)
    }

    /// The winter holidays offer reindeer antlers and, as the headline item,
    /// a scarf that snow sparkles on; both stay apart from the shop's scarf.
    func testWinterItemsAreSeasonalLimitedItems() {
        let antlers = PetItem.accessory(.reindeerAntlers)
        let scarf = PetItem.accessory(.snowScarf)
        XCTAssertEqual(PetLimitedEdition.winterAntlers.item, antlers)
        XCTAssertEqual(PetLimitedEdition.winterScarf.item, scarf)
        for item in [antlers, scarf] {
            XCTAssertEqual(item.limitedEdition?.source, .season(id: "winter-holidays"))
            XCTAssertEqual(item.theme, .seasonal)
            XCTAssertNotEqual(item, .accessory(.scarf), "the shop's scarf stays for sale")
        }
        XCTAssertEqual(PetAccessory.snowScarf.slot, PetAccessory.scarf.slot)
        XCTAssertNil(antlers.effect)
        XCTAssertEqual(scarf.effect, .sparkle)
    }

    /// Valentine's offers one item, heart glasses, so it is the headline
    /// item: a face item whose lenses glint now and then.
    func testValentinesGlassesAreASeasonalLimitedItem() {
        let glasses = PetItem.accessory(.heartGlasses)
        XCTAssertEqual(PetLimitedEdition.valentinesGlasses.item, glasses)
        XCTAssertEqual(glasses.limitedEdition?.source, .season(id: "valentines"))
        XCTAssertEqual(glasses.theme, .seasonal)
        XCTAssertEqual(PetAccessory.heartGlasses.slot, .face)
        XCTAssertEqual(glasses.effect, .sparkle)
    }

    /// Summer offers one item, sunset shades, so it is the headline item.
    /// It is its own face item, apart from the shop's cool sunglasses.
    func testSummerShadesAreASeasonalLimitedItem() {
        let shades = PetItem.accessory(.summerShades)
        XCTAssertEqual(PetLimitedEdition.summerShades.item, shades)
        XCTAssertEqual(shades.limitedEdition?.source, .season(id: "summer"))
        XCTAssertEqual(shades.theme, .seasonal)
        XCTAssertEqual(PetAccessory.summerShades.slot, PetAccessory.coolSunglasses.slot)
        XCTAssertNil(PetItem.accessory(.coolSunglasses).limitedEdition)
        XCTAssertEqual(shades.effect, .sparkle)
    }

    /// Seasonal items are limited, earned only during their event, and
    /// only the event's headline item (its last reward) carries an effect.
    func testHalloweenItemsAreSeasonalLimitedItems() {
        let hat = PetItem.accessory(.moonlitWitchHat)
        let pumpkin = PetItem.accessory(.pumpkinHat)
        XCTAssertEqual(PetLimitedEdition.halloweenWitchHat.item, hat)
        XCTAssertEqual(PetLimitedEdition.halloweenPumpkin.item, pumpkin)
        for item in [hat, pumpkin] {
            XCTAssertEqual(item.limitedEdition?.source, .season(id: "halloween"))
            XCTAssertNil(item.limitedEdition?.milestone)
            XCTAssertEqual(item.theme, .seasonal)
            XCTAssertNotEqual(item, .accessory(.witchHat), "the shop's witch hat stays for sale")
        }
        XCTAssertNil(hat.effect)
        XCTAssertEqual(pumpkin.effect, .flicker)

        var closet = PetCloset(save: PetSave(profile: PetProfile(name: "Kit", breed: .tuxedo),
                                             ledger: PetPointsLedger(earned: 5000)))
        XCTAssertEqual(closet.state(of: pumpkin), .unearned)
        XCTAssertFalse(closet.save.ledger.canBuy(pumpkin))
        XCTAssertEqual(closet.tap(pumpkin), .notEarnedYet)
    }

    // MARK: Ledger and closet

    func testPointsCannotBuyALimitedItem() {
        var ledger = PetPointsLedger(earned: 5000)
        let cap = PetItem.accessory(.backwardsCap)
        XCTAssertFalse(ledger.canBuy(cap))
        XCTAssertThrowsError(try ledger.buy(cap)) { XCTAssertEqual($0 as? PetPurchaseError, .notForSale) }
        XCTAssertEqual(ledger.balance, 5000)

        var closet = PetCloset(save: PetSave(profile: PetProfile(name: "Kit", breed: .tuxedo), ledger: ledger))
        XCTAssertEqual(closet.state(of: cap), .unearned)
        XCTAssertEqual(closet.tap(cap), .notEarnedYet)
        XCTAssertFalse(closet.profile.isWearing(cap))
        XCTAssertNotEqual(closet.nextUnlock?.item.isLimited, true)
    }

    func testGrantedItemIsOwnedWornAndKeptThroughASave() throws {
        var closet = PetCloset(save: PetSave(profile: PetProfile(name: "Kit", breed: .tuxedo)))
        let cap = PetItem.accessory(.backwardsCap)
        XCTAssertEqual(closet.applyGrants(["accessory.backwardsCap", "accessory.beanie", "accessory.fromTheFuture"]),
                       [cap])
        XCTAssertEqual(closet.applyGrants(["accessory.backwardsCap"]), [], "a grant is new only once")
        XCTAssertFalse(closet.save.ledger.owns(.accessory(.beanie)), "the server never hands out shop items")
        XCTAssertEqual(closet.state(of: cap), .owned)
        XCTAssertEqual(closet.tap(cap), .wore)
        XCTAssertEqual(closet.balance, 0)

        let reloaded = try PetSave.decode(closet.save.encoded())
        XCTAssertTrue(reloaded.ledger.owns(cap))
        XCTAssertTrue(reloaded.profile.isWearing(cap))

        // Withdrawn later: a sync without it keeps the cap.
        closet.applyGrants([])
        XCTAssertTrue(closet.save.ledger.owns(cap))
    }

    func testSaveFromBeforeLimitedItemsStillLoads() throws {
        let json = #"{"version":1,"profile":{"name":"Kit","breed":"tuxedo"},"ledger":{"earned":50,"spent":35,"purchased":["accessory.beanie"]}}"#
        let save = try PetSave.decode(Data(json.utf8))
        XCTAssertEqual(save.ledger.granted, [])
        XCTAssertTrue(save.ledger.owns(.accessory(.beanie)))
    }

    func testHandEditedSaveCannotWearAnUnearnedLimitedItem() throws {
        let json = #"{"version":1,"profile":{"name":"Kit","breed":"tuxedo","accessories":["teamMedal"]},"ledger":{"earned":0,"spent":0,"purchased":["accessory.teamMedal"]}}"#
        let save = try PetSave.decode(Data(json.utf8))
        XCTAssertFalse(save.ledger.owns(.accessory(.teamMedal)))
        XCTAssertFalse(save.profile.isWearing(.accessory(.teamMedal)))
    }

    // MARK: Milestones

    func testSevenDayStreakUnlocksTheFlameHeadband() {
        var progress = PetMilestoneProgress()
        for offset in 0..<6 { progress.add(focus(minutes: 25, on: day(offset)), calendar: calendar) }
        XCTAssertFalse(progress.isReached(.weekStreak, calendar: calendar))
        XCTAssertEqual(progress.value(of: .weekStreak, today: day(5), calendar: calendar), 6)

        var closet = PetCloset(save: PetSave(profile: PetProfile(name: "Kit", breed: .tuxedo)))
        XCTAssertEqual(closet.unlockMilestones(progress, calendar: calendar), [])

        progress.add(focus(minutes: 25, on: day(6)), calendar: calendar)
        XCTAssertTrue(progress.isReached(.weekStreak, calendar: calendar))
        XCTAssertEqual(closet.unlockMilestones(progress, calendar: calendar), [.accessory(.flameHeadband)])
        XCTAssertEqual(closet.unlockMilestones(progress, calendar: calendar), [], "unlocks once")
    }

    func testStreakNeedsConsecutiveDaysWithRealStudy() {
        var progress = PetMilestoneProgress()
        for offset in [0, 1, 2, 4, 5, 6, 7] { progress.add(focus(minutes: 30, on: day(offset)), calendar: calendar) }
        // A 3 minute session does not make day 3 a study day.
        progress.add(focus(minutes: 3, on: day(3)), calendar: calendar)
        XCTAssertEqual(progress.longestStreak(calendar: calendar), 4)
        XCTAssertFalse(progress.isReached(.weekStreak, calendar: calendar))

        // Two short sessions on one day add up.
        progress.add(focus(minutes: 3, on: day(3, hour: 15)), calendar: calendar)
        XCTAssertEqual(progress.longestStreak(calendar: calendar), 8)
        XCTAssertTrue(progress.isReached(.weekStreak, calendar: calendar))
    }

    func testCurrentStreakHoldsUntilADayIsMissed() {
        var progress = PetMilestoneProgress()
        for offset in 0..<3 { progress.add(focus(minutes: 25, on: day(offset)), calendar: calendar) }
        XCTAssertEqual(progress.currentStreak(today: day(2), calendar: calendar), 3)
        XCTAssertEqual(progress.currentStreak(today: day(3), calendar: calendar), 3, "still on in the morning")
        XCTAssertEqual(progress.currentStreak(today: day(4), calendar: calendar), 0)
    }

    func testFiftyHoursCountsEveryFocusRecordOnce() {
        var progress = PetMilestoneProgress()
        let records = (0..<59).map { focus(minutes: 50, on: day($0 / 4, hour: 8 + $0 % 4)) }
        for record in records { progress.add(record, calendar: calendar) }
        // Replaying the log (as on launch) must not count anything twice.
        for record in records { progress.add(record, calendar: calendar) }
        XCTAssertEqual(progress.focusMinutes, 2950)
        XCTAssertFalse(progress.isReached(.fiftyHours, calendar: calendar))
        XCTAssertEqual(progress.value(of: .fiftyHours, today: day(15), calendar: calendar), 2950)

        progress.add(focus(minutes: 50, on: day(15), outcome: .skipped), calendar: calendar)
        XCTAssertTrue(progress.isReached(.fiftyHours, calendar: calendar))
        XCTAssertEqual(progress.value(of: .fiftyHours, today: day(15), calendar: calendar), 3000)
    }

    func testOnlyAFinishedPartySessionEarnsTheMedal() throws {
        var progress = PetMilestoneProgress(records: [
            focus(minutes: 25, on: day(0)),
            focus(minutes: 15, on: day(0, hour: 12), source: .party, outcome: .skipped),
        ], calendar: calendar)
        XCTAssertFalse(progress.isReached(.firstParty, calendar: calendar))

        let tracker = PartySessionCompletion(
            method: "pomodoro", joinedAt: day(1).addingTimeInterval(-25 * 60), endedAt: day(1),
            friendCount: 2, hostName: "Sam", finished: true
        )
        progress.add(try XCTUnwrap(tracker.activityRecord(source: .party)), calendar: calendar)
        XCTAssertTrue(progress.isReached(.firstParty, calendar: calendar))

        var closet = PetCloset(save: PetSave(profile: PetProfile(name: "Kit", breed: .tuxedo)))
        XCTAssertEqual(closet.unlockMilestones(progress, calendar: calendar), [.accessory(.teamMedal)])
    }

    func testOtherActivityKindsDoNotCount() {
        let cards = ActivityRecord(source: .anki, kind: .cardsReviewed, start: day(0), quantity: 300, unit: .cards)
        let progress = PetMilestoneProgress(records: [cards], calendar: calendar)
        XCTAssertEqual(progress.focusMinutes, 0)
        XCTAssertEqual(progress.studyDays, [])
    }

    func testDemoProgressIsPartWayToEveryMilestone() {
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let progress = PetMilestoneProgress.demo(today: today, calendar: calendar)
        XCTAssertEqual(progress.value(of: .weekStreak, today: today, calendar: calendar), 4)
        XCTAssertEqual(progress.value(of: .fiftyHours, today: today, calendar: calendar), 31 * 60)
        XCTAssertEqual(progress.value(of: .firstParty, today: today, calendar: calendar), 0)
        XCTAssertFalse(PetMilestone.allCases.contains { progress.isReached($0, calendar: calendar) })
    }

    // MARK: Shelf progress

    func testShelfProgressCountsInEachMilestonesUnit() {
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let progress = PetMilestoneProgress.demo(today: today, calendar: calendar)
        let streak = progress.progress(of: .streakFlame, today: today, calendar: calendar)
        XCTAssertEqual(streak?.label, "4/7 days")
        XCTAssertEqual(streak?.fraction ?? 0, 4.0 / 7, accuracy: 0.001)
        XCTAssertEqual(progress.progress(of: .focusLaurel, today: today, calendar: calendar)?.label, "31/50 h")
        XCTAssertEqual(progress.progress(of: .partyMedal, today: today, calendar: calendar)?.label, "0/1 session")
        XCTAssertNil(progress.progress(of: .launchWeekCap, today: today, calendar: calendar))
    }

    func testShelfProgressNeverShowsTheGoalEarlyOrPastIt() {
        XCTAssertEqual(PetMilestone.fiftyHours.progress(value: 50 * 60 - 1).label, "49/50 h")
        XCTAssertEqual(PetMilestone.fiftyHours.progress(value: 99_999).label, "50/50 h")
        XCTAssertEqual(PetMilestone.weekStreak.progress(value: -3).fraction, 0)
        XCTAssertEqual(PetMilestone.firstParty.progress(value: 4).fraction, 1)
    }
}
