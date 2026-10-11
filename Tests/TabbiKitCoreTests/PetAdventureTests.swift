import XCTest
import TabbiKitCore

final class PetAdventureTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 813_000_000)

    private func focus(minutes: Double, phase: FocusPhase = .focus) -> ProvidedFocus {
        ProvidedFocus(source: .focus, phase: phase,
                      clock: .countdown(endsAt: start.addingTimeInterval(minutes * 60)), phaseLength: minutes * 60)
    }

    // MARK: Trigger rules

    func testLongFocusBlockPlansAnAdventure() throws {
        let plan = try XCTUnwrap(PetAdventure.plan(for: focus(minutes: 25), reduceMotion: false))
        let length: TimeInterval = 25 * 60
        let departs = plan.departsAt.timeIntervalSince(start) / length
        XCTAssertTrue(PetAdventure.departureRange.contains(departs), "leaves partway through, got \(departs)")
        XCTAssertEqual(plan.endsAt, start.addingTimeInterval(length))
        XCTAssertEqual(plan.returnsAt, plan.endsAt.addingTimeInterval(-PetAdventure.walkDuration))
    }

    func testThePetStaysHome() {
        XCTAssertNil(PetAdventure.plan(for: focus(minutes: 14), reduceMotion: false), "short block")
        XCTAssertNotNil(PetAdventure.plan(for: focus(minutes: 15), reduceMotion: false))
        XCTAssertNil(PetAdventure.plan(for: focus(minutes: 25), reduceMotion: true), "Reduce Motion")
        XCTAssertNil(PetAdventure.plan(for: focus(minutes: 25, phase: .rest), reduceMotion: false), "break")
        XCTAssertNil(PetAdventure.plan(for: nil, reduceMotion: false), "no clock")
        let paused = ProvidedFocus(source: .focus, phase: .focus, clock: .paused(shown: 600), phaseLength: 1500)
        XCTAssertNil(PetAdventure.plan(for: paused, reduceMotion: false), "paused: the pet comes home")
        let open = ProvidedFocus(source: .study, phase: .focus, clock: .countUp(since: start), phaseLength: nil)
        XCTAssertNil(PetAdventure.plan(for: open, reduceMotion: false), "open-ended: no end to come back for")
    }

    func testDepartureIsStableForTheSameBlockAndVariesAcrossBlocks() throws {
        let first = try XCTUnwrap(PetAdventure.plan(for: focus(minutes: 25), reduceMotion: false))
        let again = try XCTUnwrap(PetAdventure.plan(for: focus(minutes: 25), reduceMotion: false))
        XCTAssertEqual(first, again)
        let departures = Set((0..<10).compactMap { offset -> Date? in
            let block = ProvidedFocus(source: .focus, phase: .focus,
                                      clock: .countdown(endsAt: start.addingTimeInterval(Double(offset) * 3600 + 1500)),
                                      phaseLength: 1500)
            return PetAdventure.plan(for: block, reduceMotion: false)
                .map { $0.departsAt.addingTimeInterval(-Double(offset) * 3600) }
        })
        XCTAssertGreaterThan(departures.count, 1)
    }

    func testPhasesThroughTheBlock() throws {
        let block = focus(minutes: 25)
        let plan = try XCTUnwrap(PetAdventure.plan(for: block, reduceMotion: false))
        let walk = PetAdventure.walkDuration
        XCTAssertEqual(plan.phase(at: start), .home)
        XCTAssertEqual(plan.phase(at: plan.departsAt.addingTimeInterval(-1)), .home)
        XCTAssertEqual(plan.phase(at: plan.departsAt), .leaving(progress: 0))
        XCTAssertEqual(plan.phase(at: plan.departsAt.addingTimeInterval(walk / 2)), .leaving(progress: 0.5))
        XCTAssertEqual(plan.phase(at: plan.departsAt.addingTimeInterval(walk)), .away)
        XCTAssertEqual(plan.phase(at: plan.returnsAt.addingTimeInterval(-1)), .away)
        XCTAssertEqual(plan.phase(at: plan.returnsAt), .returning(progress: 0))
        XCTAssertEqual(plan.phase(at: plan.endsAt), .home)
        XCTAssertTrue(PetAdventure.Phase.away.isOut)
        XCTAssertFalse(PetAdventure.Phase.home.isOut)
        XCTAssertEqual(PetAdventure.phase(for: block, at: plan.departsAt.addingTimeInterval(60), reduceMotion: true),
                       .home)
    }

    func testNextChangeWalksThroughEveryBoundary() throws {
        let plan = try XCTUnwrap(PetAdventure.plan(for: focus(minutes: 25), reduceMotion: false))
        XCTAssertEqual(plan.nextChange(after: start), plan.departsAt)
        XCTAssertEqual(plan.nextChange(after: plan.departsAt),
                       plan.departsAt.addingTimeInterval(PetAdventure.walkDuration))
        XCTAssertEqual(plan.nextChange(after: plan.departsAt.addingTimeInterval(60)), plan.returnsAt)
        XCTAssertEqual(plan.nextChange(after: plan.returnsAt), plan.endsAt)
        XCTAssertNil(plan.nextChange(after: plan.endsAt))
    }

    func testDistanceAndExploringFollowTheWalk() throws {
        let plan = try XCTUnwrap(PetAdventure.plan(for: focus(minutes: 25), reduceMotion: false))
        let walk = PetAdventure.walkDuration
        XCTAssertEqual(PetAdventure.Phase.home.distance, 0)
        XCTAssertEqual(PetAdventure.Phase.leaving(progress: 0.25).distance, 0.25)
        XCTAssertEqual(PetAdventure.Phase.away.distance, 1)
        XCTAssertEqual(PetAdventure.Phase.returning(progress: 0.25).distance, 0.75)
        XCTAssertFalse(plan.isExploring(at: plan.departsAt.addingTimeInterval(-1)))
        XCTAssertTrue(plan.isExploring(at: plan.departsAt), "the label shows as it sets off")
        XCTAssertTrue(plan.isExploring(at: plan.departsAt.addingTimeInterval(walk + 60)))
        XCTAssertFalse(plan.isExploring(at: plan.returnsAt), "coming back reads as the finish")
        XCTAssertFalse(plan.isExploring(at: plan.endsAt))
    }

    // MARK: Closed notch

    func testTheTickerPetCarriesTheBlocksAdventure() throws {
        let profile = PetProfile.starter(.cat)
        let presence = PetPresence(profile: profile, lastActive: start)
        let long = focus(minutes: 25)
        let plan = try XCTUnwrap(PetAdventure.plan(for: long, reduceMotion: false))
        for date in [start, plan.departsAt.addingTimeInterval(60), plan.returnsAt] {
            let item = TickerSources(focus: long, pet: presence).items(at: date, enabled: [.pet]).first
            guard case .pet(let pet) = item else { return XCTFail("no pet at \(date)") }
            XCTAssertEqual(pet.adventure, plan, "one value for the whole block, so the item stays put")
        }
        for clock in [focus(minutes: 10), focus(minutes: 25, phase: .rest)] {
            let item = TickerSources(focus: clock, pet: presence).items(at: start, enabled: [.pet]).first
            guard case .pet(let pet) = item else { return XCTFail("no pet") }
            XCTAssertNil(pet.adventure, "short blocks and breaks keep the pet home")
        }
    }

    func testTheTooltipSaysThePetIsOutExploring() throws {
        var profile = PetProfile.starter(.cat)
        profile.rename("Mochi")
        let plan = try XCTUnwrap(PetAdventure.plan(for: focus(minutes: 25), reduceMotion: false))
        let pet = TickerPet(profile: profile, mood: .studying, adventure: plan)
        XCTAssertEqual(TickerFormat.petSummary(pet, at: start), "Mochi is studying with you")
        XCTAssertEqual(TickerFormat.petSummary(pet, at: plan.departsAt.addingTimeInterval(60)),
                       "Mochi is off on a little adventure and will be back as your session ends")
        XCTAssertEqual(TickerFormat.petSummary(pet, at: plan.returnsAt), "Mochi is studying with you")
    }

    // MARK: Journal

    func testJournalHasAboutTwentyDistinctShortLines() {
        let ids = PetJournal.lines.map(\.id)
        XCTAssertEqual(ids.count, 20)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(Set(PetJournal.lines.map(\.phrase)).count, ids.count)
        XCTAssertTrue(PetJournal.lines.allSatisfy { $0.phrase.count <= 36 }, "fits the Closet card")
    }

    func testEntryReadsWithThePetsName() {
        var journal = PetJournal(seed: 7)
        let entry = journal.record(at: start)
        let text = try? XCTUnwrap(entry.text(petName: "Mochi"))
        XCTAssertTrue(text?.hasPrefix("Mochi ") ?? false)
        XCTAssertNil(PetJournal.Entry(line: "moon", date: start).text(petName: "Mochi"), "unknown line")
        XCTAssertEqual(journal.latest, entry)
    }

    func testTheSurpriseGiftGoesOnTheAdventureItCameHomeFrom() throws {
        var journal = PetJournal(seed: 7)
        let first = journal.record(at: start)
        let second = journal.record(at: start.addingTimeInterval(3600))
        XCTAssertNil(second.gift)
        XCTAssertEqual(second.detail(petName: "Mochi"), second.text(petName: "Mochi"), "no gift, no tail")

        let fur = try XCTUnwrap(RareFur.named("mint"))
        let carried = try XCTUnwrap(journal.attach(.rareFur(fur), to: second))
        XCTAssertEqual(carried.gift, .rareFur(fur))
        XCTAssertEqual(journal.latest, carried)
        XCTAssertNil(journal.entries.first?.gift, "only that adventure")
        let text = try XCTUnwrap(second.text(petName: "Mochi"))
        XCTAssertEqual(carried.detail(petName: "Mochi"), "\(text) and brought back the rare Mint fur")
        XCTAssertEqual(carried.text(petName: "Mochi"), text, "the card's line stays short")

        XCTAssertNil(journal.attach(.bonusPoints(10), to: second), "one gift per adventure")
        XCTAssertNil(journal.attach(.bonusPoints(10), to: PetJournal.Entry(line: first.line, date: .distantPast)),
                     "an adventure no longer kept")
        XCTAssertEqual(try PetJournal.decode(journal.encoded()), journal, "the gift is saved")
    }

    func testAnUnknownGiftIsDroppedAndTheEntryStillLoads() throws {
        let json = #"{"line":"leaf","date":0,"gift":{"kind":"rareFur","value":"plaid"}}"#
        let entry = try JSONDecoder().decode(PetJournal.Entry.self, from: Data(json.utf8))
        XCTAssertEqual(entry.line, "leaf")
        XCTAssertNil(entry.gift)
        let plain = try JSONDecoder().decode(PetJournal.Entry.self, from: Data(#"{"line":"leaf","date":0}"#.utf8))
        XCTAssertNil(plain.gift, "entries written before gifts load as before")
    }

    func testNoRepeatsUntilEveryLineIsUsed() {
        var journal = PetJournal(seed: 42)
        let count = PetJournal.lines.count
        for deck in 0..<4 {
            let lines = (0..<count).map { journal.record(at: start.addingTimeInterval(Double(deck * count + $0))).line }
            XCTAssertEqual(Set(lines).count, count, "deck \(deck) uses every line once")
        }
    }

    func testDecksReshuffleAndNeverRepeatAcrossTheSeam() {
        var journal = PetJournal(seed: 3)
        let count = PetJournal.lines.count
        let all = (0..<(count * 6)).map { journal.record(at: start.addingTimeInterval(Double($0))).line }
        for index in 1..<all.count { XCTAssertNotEqual(all[index], all[index - 1], "no line twice in a row") }
        let decks = stride(from: 0, to: all.count, by: count).map { Array(all[$0..<($0 + count)]) }
        XCTAssertGreaterThan(Set(decks).count, 1, "the order changes from deck to deck")
    }

    func testRotationIsDeterministicForASeed() {
        var first = PetJournal(seed: 11)
        var second = PetJournal(seed: 11)
        var other = PetJournal(seed: 12)
        let a = (0..<30).map { first.record(at: start.addingTimeInterval(Double($0))).line }
        let b = (0..<30).map { second.record(at: start.addingTimeInterval(Double($0))).line }
        let c = (0..<30).map { other.record(at: start.addingTimeInterval(Double($0))).line }
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testJournalKeepsTheNewestEntries() {
        var journal = PetJournal(seed: 1)
        for index in 0..<(PetJournal.maxEntries + 5) { journal.record(at: start.addingTimeInterval(Double(index))) }
        XCTAssertEqual(journal.entries.count, PetJournal.maxEntries)
        XCTAssertEqual(journal.entries.last?.date, start.addingTimeInterval(Double(PetJournal.maxEntries + 4)))
    }

    func testJournalRoundTripsAndKeepsItsPlaceInTheDeck() throws {
        var journal = PetJournal(seed: 9)
        for index in 0..<5 { journal.record(at: start.addingTimeInterval(Double(index))) }
        let decoded = try JSONDecoder().decode(PetJournal.self, from: JSONEncoder().encode(journal))
        XCTAssertEqual(decoded, journal)
        XCTAssertEqual(decoded.nextLine, journal.nextLine)
    }

    func testDecodingDropsUnknownAndDuplicateDeckLines() throws {
        let json = #"{"seed": 5, "deck": ["bookshelf", "moon", "bookshelf"], "decksFinished": -2}"#
        let journal = try JSONDecoder().decode(PetJournal.self, from: Data(json.utf8))
        XCTAssertEqual(journal.deck, ["bookshelf"])
        XCTAssertEqual(journal.decksFinished, 0)
        XCTAssertNotEqual(journal.nextLine, "bookshelf")
    }

    // MARK: Finishing an adventure

    private func running(_ minutes: Double, done: Int = 0) -> ProvidedFocus {
        ProvidedFocus(source: .focus, phase: .focus, clock: .countdown(endsAt: start.addingTimeInterval(minutes * 60)),
                      phaseLength: minutes * 60, completedFocusCount: done)
    }

    private func onBreak(done: Int, source: ModuleID = .focus) -> ProvidedFocus {
        ProvidedFocus(source: source, phase: .rest, clock: .countdown(endsAt: start.addingTimeInterval(30 * 60)),
                      phaseLength: 5 * 60, completedFocusCount: done)
    }

    func testABlockThatRunsOutBringsThePetBack() throws {
        let end = start.addingTimeInterval(25 * 60)
        let adventure = try XCTUnwrap(PetAdventure.finished(from: running(25), to: onBreak(done: 1), at: end,
                                                            reduceMotion: false))
        XCTAssertEqual(adventure, PetAdventure.plan(for: running(25), reduceMotion: false))
        XCTAssertEqual(adventure.endsAt, end)
        let later = end.addingTimeInterval(3600)
        XCTAssertNotNil(PetAdventure.finished(from: running(25), to: onBreak(done: 1), at: later, reduceMotion: false),
                        "noticed late, after the Mac slept through the end")
    }

    func testOnlyAFinishedLongBlockWithTheWalkHomeCounts() {
        let end = start.addingTimeInterval(25 * 60)
        let idle = ProvidedFocus(source: .focus, phase: .focus, clock: .idle, phaseLength: 25 * 60)
        XCTAssertNil(PetAdventure.finished(from: running(25), to: idle, at: start.addingTimeInterval(600),
                                           reduceMotion: false), "stopped early")
        XCTAssertNil(PetAdventure.finished(from: running(25), to: onBreak(done: 1), at: start.addingTimeInterval(600),
                                           reduceMotion: false), "skipped before the walk home")
        XCTAssertNil(PetAdventure.finished(from: running(10), to: onBreak(done: 1), at: start.addingTimeInterval(600),
                                           reduceMotion: false), "too short to leave")
        XCTAssertNil(PetAdventure.finished(from: running(25), to: onBreak(done: 1), at: end, reduceMotion: true),
                     "Reduce Motion: the pet stayed home")
        XCTAssertNil(PetAdventure.finished(from: running(25), to: onBreak(done: 1, source: .study), at: end,
                                           reduceMotion: false), "another clock")
        XCTAssertNil(PetAdventure.finished(from: running(25), to: nil, at: end, reduceMotion: false), "clock gone")
        XCTAssertNil(PetAdventure.finished(from: running(25, done: 1), to: running(25, done: 1), at: end,
                                           reduceMotion: false), "nothing finished")
    }

    func testTheJournalFileIsVersionedAndRoundTrips() throws {
        var journal = PetJournal(seed: .max)
        for index in 0..<3 { journal.record(at: start.addingTimeInterval(Double(index) * 60)) }
        let data = try journal.encoded()
        XCTAssertEqual(VersionedJSON.version(of: data), PetJournal.schema.current)
        XCTAssertEqual(try PetJournal.decode(data), journal)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("journal.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertNil(try PetJournal.load(from: url), "no journal yet")
        try journal.write(to: url)
        XCTAssertEqual(try PetJournal.load(from: url), journal)
        try Data("not json".utf8).write(to: url)
        XCTAssertThrowsError(try PetJournal.load(from: url), "a corrupt file is reported, not replaced")
    }

    func testDemoJournalHasRecentVariedAdventures() throws {
        let now = start
        let journal = PetJournal.demo(now: now)
        XCTAssertEqual(Set(journal.entries.map(\.line)).count, journal.entries.count)
        XCTAssertEqual(try XCTUnwrap(journal.latest).date, now.addingTimeInterval(-3600))
        XCTAssertEqual(journal, PetJournal.demo(now: now), "the same every run")
    }
}
