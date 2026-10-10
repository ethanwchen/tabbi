import Foundation
import TabbiKitCore
import XCTest

final class SeasonalEventTests: XCTestCase {
    private func calendar(_ zone: String = "America/New_York") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0,
                      in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private let halloween = SeasonalEvent(
        id: "halloween", name: "Halloween", tagline: "Spooky season.",
        start: SeasonalEventDay(month: 10, day: 17), end: SeasonalEventDay(month: 11, day: 2),
        rewards: [SeasonalEventReward(item: .accessory(.witchHat), focusMinutes: 90),
                  SeasonalEventReward(item: .accessory(.halo), focusMinutes: 300)]
    )

    private let winter = SeasonalEvent(
        id: "winter", name: "Winter Holidays", tagline: "Warm drinks, cozy focus.",
        start: SeasonalEventDay(month: 12, day: 14), end: SeasonalEventDay(month: 1, day: 3),
        rewards: [SeasonalEventReward(item: .accessory(.beanie), focusMinutes: 240)]
    )

    private let lunarNewYear = SeasonalEvent(
        id: "lunar-new-year", name: "Lunar New Year", tagline: "A fresh start.", calendar: .chinese,
        start: SeasonalEventDay(month: 1, day: 1), end: SeasonalEventDay(month: 1, day: 15),
        rewards: [SeasonalEventReward(item: .accessory(.tinyCrown), focusMinutes: 180)]
    )

    private func focus(_ minutes: Double, endingAt end: Date, source: ModuleID = "focus") -> ActivityRecord {
        ActivityRecord(source: source, kind: .focusCompleted, start: end.addingTimeInterval(-minutes * 60),
                       end: end, quantity: minutes, unit: .minutes)
    }

    // MARK: Date windows

    func testWindowRunsFromLocalMidnightOfTheFirstDayThroughTheLastDay() {
        let calendar = calendar()
        let occurrence = halloween.occurrence(containing: date(2026, 10, 20, hour: 15, in: calendar), calendar: calendar)
        XCTAssertEqual(occurrence?.start, date(2026, 10, 17, in: calendar))
        XCTAssertEqual(occurrence?.end, date(2026, 11, 3, in: calendar))

        XCTAssertNotNil(halloween.occurrence(containing: date(2026, 10, 17, in: calendar), calendar: calendar))
        XCTAssertNotNil(halloween.occurrence(containing: date(2026, 11, 2, hour: 23, minute: 59, in: calendar),
                                             calendar: calendar))
        XCTAssertNil(halloween.occurrence(containing: date(2026, 10, 16, hour: 23, minute: 59, in: calendar),
                                          calendar: calendar))
        XCTAssertNil(halloween.occurrence(containing: date(2026, 11, 3, in: calendar), calendar: calendar))
        XCTAssertNil(halloween.occurrence(containing: date(2026, 7, 1, in: calendar), calendar: calendar))
    }

    func testWindowFollowsTheLocalTimeZone() {
        // The same instant: 03:00 on October 17 in Berlin is still October
        // 16 in New York, so the event has started in one and not the other.
        let berlin = calendar("Europe/Berlin")
        let instant = date(2026, 10, 17, hour: 3, in: berlin)
        XCTAssertNotNil(halloween.occurrence(containing: instant, calendar: berlin))
        XCTAssertNil(halloween.occurrence(containing: instant, calendar: calendar()))

        let tokyo = calendar("Asia/Tokyo")
        XCTAssertEqual(halloween.occurrence(containing: date(2026, 10, 25, in: tokyo), calendar: tokyo)?.start,
                       date(2026, 10, 17, in: tokyo))
    }

    func testWindowKeepsWholeDaysAcrossADaylightSavingChange() {
        // New York falls back on November 1, 2026: that day is 25 hours long.
        let calendar = calendar()
        let occurrence = halloween.occurrence(containing: date(2026, 11, 1, hour: 12, in: calendar), calendar: calendar)
        XCTAssertEqual(occurrence?.end, date(2026, 11, 3, in: calendar))
    }

    func testWindowWrapsOverNewYear() {
        let calendar = calendar()
        let december = winter.occurrence(containing: date(2026, 12, 31, hour: 22, in: calendar), calendar: calendar)
        let january = winter.occurrence(containing: date(2027, 1, 2, in: calendar), calendar: calendar)
        XCTAssertEqual(december, january)
        XCTAssertEqual(january?.start, date(2026, 12, 14, in: calendar))
        XCTAssertEqual(january?.end, date(2027, 1, 4, in: calendar))
        XCTAssertEqual(january?.id(calendar: calendar), "winter-2026")

        XCTAssertNil(winter.occurrence(containing: date(2027, 1, 4, in: calendar), calendar: calendar))
        XCTAssertNil(winter.occurrence(containing: date(2026, 12, 13, hour: 23, in: calendar), calendar: calendar))
    }

    func testLunarNewYearFollowsTheChineseCalendar() {
        let calendar = calendar()
        // Lunar New Year: February 6, 2027 and January 26, 2028.
        let first = lunarNewYear.occurrence(containing: date(2027, 2, 10, in: calendar), calendar: calendar)
        XCTAssertEqual(first?.start, date(2027, 2, 6, in: calendar))
        XCTAssertEqual(first?.end, date(2027, 2, 21, in: calendar))
        XCTAssertNil(lunarNewYear.occurrence(containing: date(2027, 2, 5, in: calendar), calendar: calendar))

        let second = lunarNewYear.nextOccurrence(after: date(2027, 3, 1, in: calendar), calendar: calendar)
        XCTAssertEqual(second?.start, date(2028, 1, 26, in: calendar))
    }

    func testNextOccurrenceComesBackNextYear() {
        let calendar = calendar()
        let next = halloween.nextOccurrence(after: date(2026, 10, 20, in: calendar), calendar: calendar)
        XCTAssertEqual(next?.start, date(2027, 10, 17, in: calendar))
        XCTAssertEqual(next?.id(calendar: calendar), "halloween-2027")
    }

    func testCatalogPutsTheEventEndingSoonestFirstAndFindsTheNextOne() {
        let calendar = calendar()
        let valentines = SeasonalEvent(
            id: "valentines", name: "Valentine's", tagline: "Love what you learn.",
            start: SeasonalEventDay(month: 2, day: 7), end: SeasonalEventDay(month: 2, day: 14),
            rewards: [SeasonalEventReward(item: .accessory(.roundGlasses), focusMinutes: 60)]
        )
        let catalog = SeasonalEventCatalog(events: [halloween, winter, lunarNewYear, valentines])
        let both = catalog.active(at: date(2027, 2, 10, in: calendar), calendar: calendar)
        XCTAssertEqual(both.map(\.event.id), ["valentines", "lunar-new-year"])
        XCTAssertEqual(catalog.active(at: date(2027, 3, 10, in: calendar), calendar: calendar), [])

        XCTAssertEqual(catalog.next(after: date(2027, 3, 10, in: calendar), calendar: calendar)?.event.id, "halloween")
        XCTAssertEqual(catalog.next(after: date(2026, 11, 10, in: calendar), calendar: calendar)?.event.id, "winter")
        XCTAssertEqual(catalog.event(offering: .accessory(.beanie))?.id, "winter")
        XCTAssertNil(catalog.event(offering: .accessory(.chefHat)))
    }

    // MARK: Earning

    func testOnlyFocusLoggedDuringTheRunCounts() throws {
        let calendar = calendar()
        let occurrence = try XCTUnwrap(halloween.occurrence(containing: date(2026, 10, 20, in: calendar),
                                                            calendar: calendar))
        let inside = focus(50, endingAt: date(2026, 10, 18, hour: 10, in: calendar))
        let records = [
            inside, inside,
            focus(45, endingAt: date(2026, 11, 2, hour: 23, in: calendar)),
            focus(200, endingAt: date(2026, 10, 16, hour: 23, in: calendar)),
            focus(200, endingAt: date(2026, 11, 3, hour: 1, in: calendar)),
            focus(30, endingAt: date(2025, 10, 20, in: calendar)),
            ActivityRecord(source: "focus", kind: .breakTaken, start: date(2026, 10, 19, in: calendar),
                           end: date(2026, 10, 19, hour: 1, in: calendar), quantity: 60, unit: .minutes),
            ActivityRecord(source: "anki", kind: .cardsReviewed, start: date(2026, 10, 19, in: calendar),
                           quantity: 80, unit: .cards),
        ]
        let progress = SeasonalEventProgress(occurrence: occurrence, records: records)
        XCTAssertEqual(progress.focusMinutes, 95)
        XCTAssertEqual(progress.earned, [.accessory(.witchHat)])
        XCTAssertEqual(progress.nextReward?.item, .accessory(.halo))
    }

    func testRewardsAreEarnedInOrderAndProgressReads() throws {
        let calendar = calendar()
        let occurrence = try XCTUnwrap(halloween.occurrence(containing: date(2026, 10, 20, in: calendar),
                                                            calendar: calendar))
        var progress = SeasonalEventProgress(occurrence: occurrence)
        XCTAssertEqual(progress.earned, [])
        XCTAssertEqual(progress.nextReward?.item, .accessory(.witchHat))
        XCTAssertEqual(progress.progress(of: halloween.rewards[0]).label, "0/90 min")

        progress.add(focus(75, endingAt: date(2026, 10, 18, hour: 9, in: calendar)))
        XCTAssertEqual(progress.progress(of: halloween.rewards[0]).label, "75/90 min")
        XCTAssertEqual(progress.progress(of: halloween.rewards[1]).label, "1/5 h")

        progress.add(focus(250, endingAt: date(2026, 10, 25, hour: 9, in: calendar)))
        XCTAssertEqual(progress.earned, [.accessory(.witchHat), .accessory(.halo)])
        XCTAssertNil(progress.nextReward)
        let headline = progress.progress(of: halloween.rewards[1])
        XCTAssertEqual(headline.label, "5/5 h")
        XCTAssertEqual(headline.fraction, 1)
        XCTAssertEqual(halloween.headline, .accessory(.halo))
    }

    func testAMissedItemStartsOverWhenTheEventReturns() throws {
        let calendar = calendar()
        let thisYear = try XCTUnwrap(halloween.occurrence(containing: date(2026, 10, 20, in: calendar),
                                                          calendar: calendar))
        let nextYear = try XCTUnwrap(halloween.nextOccurrence(after: thisYear.start, calendar: calendar))
        let records = [focus(200, endingAt: date(2026, 10, 20, in: calendar)),
                       focus(60, endingAt: date(2027, 10, 20, in: calendar))]
        XCTAssertEqual(SeasonalEventProgress(occurrence: thisYear, records: records).focusMinutes, 200)
        XCTAssertEqual(SeasonalEventProgress(occurrence: nextYear, records: records).focusMinutes, 60)
    }

    // MARK: Tally and ownership

    func testTallyKeepsEachRunApartAndEarnsAcrossRuns() {
        let calendar = calendar()
        let inHalloween = focus(100, endingAt: date(2026, 10, 20, hour: 9, in: calendar))
        let records = [inHalloween, inHalloween,
                       focus(200, endingAt: date(2026, 11, 10, in: calendar)),
                       focus(240, endingAt: date(2027, 1, 2, hour: 22, in: calendar)),
                       ActivityRecord(source: "anki", kind: .cardsReviewed, start: date(2026, 10, 21, in: calendar),
                                      end: date(2026, 10, 21, hour: 1, in: calendar), quantity: 500, unit: .minutes)]
        let tally = SeasonalEventTally(catalog: SeasonalEventCatalog(events: [halloween, winter]), calendar: calendar,
                                       records: records)

        XCTAssertEqual(Set(tally.runs.keys), ["halloween-2026", "winter-2026"])
        XCTAssertEqual(tally.runs["halloween-2026"]?.focusMinutes, 100)
        XCTAssertEqual(tally.earned, [.accessory(.witchHat), .accessory(.beanie)])
        XCTAssertEqual(tally.progress(of: .accessory(.witchHat), at: date(2026, 10, 30, in: calendar))?.label,
                       "90/90 min")
        XCTAssertEqual(tally.progress(of: .accessory(.halo), at: date(2026, 10, 30, in: calendar))?.label, "1/5 h")
        XCTAssertNil(tally.progress(of: .accessory(.halo), at: date(2026, 11, 10, in: calendar)))
        XCTAssertNil(tally.progress(of: .accessory(.beanie), at: date(2026, 10, 30, in: calendar)))

        // Next year's run starts from zero.
        let nextYear = tally.active(at: date(2027, 10, 20, in: calendar))
        XCTAssertEqual(nextYear.map(\.occurrence.event.id), ["halloween"])
        XCTAssertEqual(nextYear.first?.focusMinutes, 0)
        XCTAssertEqual(tally.progress(of: .accessory(.witchHat), at: date(2027, 10, 20, in: calendar))?.label,
                       "0/90 min")
    }

    func testEarnedSeasonalItemsAreGrantedOnceAndStayOwned() {
        let calendar = calendar()
        var closet = PetCloset(save: PetSave(profile: .starter(.cat)))
        let witchHat = PetLimitedEdition.halloweenWitchHat.item
        let pumpkin = PetLimitedEdition.halloweenPumpkin.item

        var tally = SeasonalEventTally(calendar: calendar)
        tally.add(focus(60, endingAt: date(2026, 10, 18, hour: 9, in: calendar)))
        XCTAssertEqual(closet.unlockSeasonal(tally), [])
        XCTAssertFalse(closet.state(of: witchHat).isOwned)

        tally.add(focus(45, endingAt: date(2026, 10, 19, hour: 9, in: calendar)))
        XCTAssertEqual(closet.unlockSeasonal(tally), [witchHat])
        XCTAssertEqual(closet.unlockSeasonal(tally), [], "an item is granted once")
        XCTAssertTrue(closet.state(of: witchHat).isOwned)
        XCTAssertFalse(closet.state(of: pumpkin).isOwned)

        // After the event the hat is still owned, and next year the pumpkin
        // can be earned from a fresh start.
        let nextYear = SeasonalEventTally(calendar: calendar)
        XCTAssertEqual(closet.unlockSeasonal(nextYear), [])
        XCTAssertTrue(closet.state(of: witchHat).isOwned)
        XCTAssertEqual(nextYear.progress(of: pumpkin, at: date(2027, 10, 20, in: calendar))?.label, "0/5 h")
    }

    // MARK: Catalog file

    private func file(_ events: String, schema: String = "events.v1") -> Data {
        Data(#"{"schema": "\#(schema)", "events": [\#(events)]}"#.utf8)
    }

    private func event(id: String = "halloween", calendar: String = "gregorian",
                       start: String = #"{"month": 10, "day": 17}"#, end: String = #"{"month": 11, "day": 2}"#,
                       rewards: String = #"[{"item": "accessory.witchHat", "focusMinutes": 90}]"#) -> String {
        #"{"id": "\#(id)", "name": "Halloween", "tagline": "Spooky season.", "calendar": "\#(calendar)", "start": \#(start), "end": \#(end), "rewards": \#(rewards)}"#
    }

    func testDecodesAValidFile() throws {
        let catalog = try SeasonalEventCatalog.decode(file(event() + "," + event(
            id: "lunar-new-year", calendar: "chinese", start: #"{"month": 1, "day": 1}"#,
            end: #"{"month": 1, "day": 15}"#,
            rewards: #"[{"item": "accessory.beanie", "focusMinutes": 60}, {"item": "accessory.halo", "focusMinutes": 180}]"#
        )))
        XCTAssertEqual(catalog.events.map(\.id), ["halloween", "lunar-new-year"])
        XCTAssertEqual(catalog.events[0].rewards, [SeasonalEventReward(item: .accessory(.witchHat), focusMinutes: 90)])
        XCTAssertEqual(catalog.events[1].calendar, .chinese)
        XCTAssertEqual(catalog.events[1].headline, .accessory(.halo))
    }

    func testRejectsBadFiles() {
        func rejects(_ data: Data, _ path: String, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertThrowsError(try SeasonalEventCatalog.decode(data), file: file, line: line) { error in
                guard case .invalidValue(let found, _) = error as? SeasonalEventCatalog.LoadError else {
                    return XCTFail("Unexpected error \(error)", file: file, line: line)
                }
                XCTAssertEqual(found, path, file: file, line: line)
            }
        }
        XCTAssertThrowsError(try SeasonalEventCatalog.decode(file(event(), schema: "events.v2"))) { error in
            XCTAssertEqual(error as? SeasonalEventCatalog.LoadError, .unsupportedSchema("events.v2"))
        }
        rejects(file(event(id: "Halloween")), "events[0].id")
        rejects(file(event() + "," + event(rewards: #"[{"item": "accessory.beanie", "focusMinutes": 60}]"#)),
                "events[1].id")
        rejects(file(event(start: #"{"month": 2, "day": 29}"#)), "events[0].start")
        rejects(file(event(end: #"{"month": 13, "day": 1}"#)), "events[0].end")
        rejects(file(event(calendar: "chinese", end: #"{"month": 1, "day": 30}"#)), "events[0].end")
        rejects(file(event(rewards: "[]")), "events[0].rewards")
        rejects(file(event(rewards: #"[{"item": "accessory.nope", "focusMinutes": 60}]"#)), "events[0].rewards[0].item")
        rejects(file(event(rewards: #"[{"item": "accessory.beanie", "focusMinutes": 0}]"#)),
                "events[0].rewards[0].focusMinutes")
        rejects(file(event(rewards: #"[{"item": "accessory.beanie", "focusMinutes": 150}]"#)),
                "events[0].rewards[0].focusMinutes")
        rejects(file(event(rewards: #"[{"item": "accessory.beanie", "focusMinutes": 60}, {"item": "accessory.halo", "focusMinutes": 60}]"#)),
                "events[0].rewards[1].focusMinutes")
        rejects(file(event() + "," + event(id: "fall")), "events[1].rewards[0].item")
    }

    // MARK: Bundled year

    func testBundledYearOffersEverySeasonalItemOnce() {
        let catalog = SeasonalEventCatalog.bundled
        XCTAssertEqual(Set(catalog.events.map(\.id)),
                       ["lunar-new-year", "valentines", "spring", "exam-season", "summer", "halloween", "winter-holidays"])
        let seasonal = PetLimitedEdition.allCases.filter {
            if case .season = $0.source { true } else { false }
        }
        for edition in seasonal {
            guard case .season(let id) = edition.source else { continue }
            let event = catalog.event(offering: edition.item)
            XCTAssertEqual(event?.id, id, "\(edition) is offered by its own event")
            XCTAssertNotNil(edition.seasonalReward, "\(edition)")
        }
        let offered = catalog.events.flatMap { $0.rewards.map(\.item) }
        XCTAssertEqual(Set(offered), Set(seasonal.map(\.item)), "every event item is a seasonal limited edition")
        for event in catalog.events {
            for reward in event.rewards {
                XCTAssertEqual(reward.item.effect != nil, reward.item == event.headline,
                               "only \(event.id)'s headline item has an effect")
            }
        }
        XCTAssertNil(PetLimitedEdition.streakFlame.seasonalReward)
    }

    func testBundledYearRunsOnTheExpectedLocalDays() {
        let catalog = SeasonalEventCatalog.bundled
        let newYork = calendar()
        func active(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> [String] {
            catalog.active(at: date(year, month, day, hour: hour, in: newYork), calendar: newYork).map(\.event.id)
        }
        XCTAssertEqual(active(2026, 10, 10), [])
        XCTAssertEqual(active(2026, 10, 17, hour: 0), ["halloween"])
        XCTAssertEqual(catalog.active(at: date(2026, 10, 31, hour: 23, minute: 59, in: newYork), calendar: newYork)
            .map(\.event.id), ["halloween"])
        XCTAssertEqual(active(2026, 11, 1, hour: 0), [])
        XCTAssertEqual(active(2027, 1, 6), ["winter-holidays"])
        XCTAssertEqual(active(2027, 1, 7), [])
        XCTAssertEqual(active(2027, 2, 6), ["lunar-new-year"], "Lunar New Year 2027 falls on February 6")
        XCTAssertEqual(active(2027, 2, 10), ["valentines", "lunar-new-year"], "the shorter run shows first")
        XCTAssertEqual(active(2027, 5, 15), ["exam-season"])
        XCTAssertEqual(active(2027, 7, 15), ["summer"])
        XCTAssertEqual(catalog.next(after: date(2026, 10, 10, in: newYork), calendar: newYork)?.id(calendar: newYork), "halloween-2026")
    }

    func testLimitedShelvesFeatureTheCurrentOrNextEventThenTheYearAhead() {
        let catalog = SeasonalEventCatalog.bundled
        let newYork = calendar()
        func shelves(_ year: Int, _ month: Int, _ day: Int) -> [PetLimitedShelf] {
            catalog.limitedShelves(at: date(year, month, day, hour: 12, in: newYork), calendar: newYork)
        }
        let milestones = PetLimitedShelf(kind: .milestones, items: [
            .accessory(.backwardsCap), .accessory(.flameHeadband), .accessory(.goldenLaurel), .accessory(.teamMedal),
        ])
        for shelves in [shelves(2026, 10, 10), shelves(2026, 10, 20), shelves(2027, 2, 10)] {
            XCTAssertEqual(shelves.flatMap(\.items).sorted { $0.id < $1.id }, PetCloset.limitedShelf.sorted { $0.id < $1.id },
                           "every limited item sits on one shelf")
            XCTAssertEqual(shelves.count, 3)
            XCTAssertEqual(shelves[1], milestones)
        }

        // Before Halloween, it is upcoming; the rest follow in the order they come back.
        let october = shelves(2026, 10, 10)
        guard case .event(let upcoming, let isActive) = october[0].kind else { return XCTFail("no featured event") }
        XCTAssertEqual(upcoming.id(calendar: newYork), "halloween-2026")
        XCTAssertFalse(isActive)
        XCTAssertEqual(october[0].items, [.accessory(.moonlitWitchHat), .accessory(.pumpkinHat)])
        XCTAssertEqual(october[2].kind, .laterEvents)
        XCTAssertEqual(october[2].items, [
            .accessory(.reindeerAntlers), .accessory(.snowScarf), .accessory(.lionDanceHat), .accessory(.heartGlasses),
            .accessory(.sakuraSprig), .outfit(.studyHoodie), .accessory(.summerShades),
        ])

        // During it, it is active.
        guard case .event(let running, true) = shelves(2026, 10, 20)[0].kind else { return XCTFail("not active") }
        XCTAssertEqual(running.event.id, "halloween")

        // When two overlap, the one ending soonest is featured and the
        // other, already running, leads the rest.
        let february = shelves(2027, 2, 10)
        guard case .event(let valentines, true) = february[0].kind else { return XCTFail("not active") }
        XCTAssertEqual(valentines.event.id, "valentines")
        XCTAssertEqual(february[2].items.first, .accessory(.lionDanceHat))
        XCTAssertEqual(february[2].items.suffix(2), [.accessory(.reindeerAntlers), .accessory(.snowScarf)])
    }

    func testRewardGoalLabelsUseTheProgressUnits() {
        XCTAssertEqual(SeasonalEventReward(item: .accessory(.halo), focusMinutes: 90).goalLabel, "90 min")
        XCTAssertEqual(SeasonalEventReward(item: .accessory(.halo), focusMinutes: 300).goalLabel, "5 h")
    }

    func testSeasonalCopyStatesTheCatalogGoal() {
        XCTAssertEqual(PetLimitedEdition.halloweenWitchHat.howToEarn, "Focus for 90 minutes during Halloween.")
        XCTAssertEqual(PetLimitedEdition.halloweenPumpkin.howToEarn, "Focus for 5 hours during Halloween.")
        XCTAssertEqual(PetLimitedEdition.valentinesGlasses.howToEarn, "Focus for 3 hours during Valentine's week.")
    }

    /// The schema accepts every id and calendar the bundled file and Swift
    /// use, so a port validating with it accepts what the Mac app ships.
    func testSchemaMatchesTheBundledYear() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("shared/schemas/events.v1.schema.json"))
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let defs = try XCTUnwrap(schema["$defs"] as? [String: [String: Any]])
        func property(_ def: String, _ key: String) throws -> [String: Any] {
            try XCTUnwrap((defs[def]?["properties"] as? [String: [String: Any]])?[key], "\(def).\(key)")
        }
        XCTAssertEqual(try property("event", "calendar")["enum"] as? [String],
                       SeasonalEventCalendar.allCases.map(\.rawValue))
        let itemPattern = try XCTUnwrap(try property("reward", "item")["pattern"] as? String)
        let idPattern = try XCTUnwrap(try property("event", "id")["pattern"] as? String)
        for event in SeasonalEventCatalog.bundled.events {
            XCTAssertNotNil(event.id.range(of: idPattern, options: .regularExpression), event.id)
            for reward in event.rewards {
                XCTAssertNotNil(reward.item.id.range(of: itemPattern, options: .regularExpression), reward.item.id)
            }
        }
    }
}
