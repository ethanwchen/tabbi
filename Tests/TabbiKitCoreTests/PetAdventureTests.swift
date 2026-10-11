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
}
