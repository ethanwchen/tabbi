import Foundation
import XCTest
@testable import TabbiKitCore

final class CrewsTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    // MARK: Catalog

    /// Every frame and emblem name in crew.json is a translated catalog key,
    /// so the builder's tooltips read in every language; a new emblem set
    /// gets its names through `scripts/crews-import-art.py`.
    func testEveryCrestNameIsTranslated() throws {
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(
            "Sources/TabbiKitCore/Localization/Localizable.xcstrings"))) as? [String: Any])
        let strings = try XCTUnwrap(catalog["strings"] as? [String: [String: Any]])
        let names = CrewCatalog.frames.map { CrewCrestArt.art.frame($0).name } + CrewCatalog.emblems.map { CrewCrestArt.art.emblem($0).name }
        for name in names {
            let localized = strings[name]?["localizations"] as? [String: Any] ?? [:]
            XCTAssertEqual(Set(localized.keys).count, 11, "\(name) needs a translation in every language (scripts/crews-import-art.py)")
        }
        XCTAssertNotEqual(CrewCatalog.emblemTitle("bird"), "", "titles read from the data")
    }

    /// The app's frames, emblems, colors and limits are the server's
    /// (`backend/shared/crews.json`), in the same order.
    func testCatalogMatchesServer() throws {
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appendingPathComponent("backend/shared/crews.json"))) as? [String: Any])
        XCTAssertEqual(catalog["version"] as? Int, CrewCatalog.version)
        XCTAssertEqual(catalog["frames"] as? [String], CrewCatalog.frames, "crew.json and crews.json list different frames")
        XCTAssertEqual(catalog["emblems"] as? [String], CrewCatalog.emblems, "crew.json and crews.json list different emblems")
        let colors = try XCTUnwrap(catalog["colors"] as? [String: String])
        XCTAssertEqual(colors, Dictionary(uniqueKeysWithValues: CrewCatalog.colors.map { ($0.id, $0.hex) }))
        let limits = try XCTUnwrap(catalog["limits"] as? [String: Int])
        XCTAssertEqual(limits["nameMaxLength"], CrewCatalog.nameMaxLength)
        XCTAssertEqual(limits["descriptionMaxLength"], CrewCatalog.descriptionMaxLength)
        XCTAssertEqual(limits["maxMembers"], CrewCatalog.maxMembers)
        XCTAssertEqual(limits["searchPageSize"], CrewCatalog.searchPageSize)
        XCTAssertEqual(limits["maxSessionsPerReport"], CrewCatalog.maxSessionsPerReport)
        XCTAssertEqual(limits["maxSessionMinutes"], CrewCatalog.maxSessionMinutes)
        XCTAssertEqual(limits["dailyCapMinutes"], CrewCatalog.dailyCapMinutes)
        XCTAssertEqual(limits["weeklyCapMinutes"], CrewCatalog.weeklyCapMinutes)
        XCTAssertEqual(catalog["visibilities"] as? [String], CrewVisibility.allCases.map(\.rawValue))
        XCTAssertEqual(catalog["laurels"] as? [String], CrewLaurel.allCases.map(\.rawValue))
    }

    func testUnknownIdsFallBackToTheDefaultCrest() {
        let crest = CrewCrest(frame: "castle", emblem: "dragon", color: "ultraviolet").resolved
        XCTAssertEqual(crest, .default)
        XCTAssertEqual(CrewCatalog.frame(CrewCatalog.frames.last!), CrewCatalog.frames.last!)
        XCTAssertEqual(CrewCatalog.emblem(CrewCatalog.emblems.last!), CrewCatalog.emblems.last!)
        XCTAssertEqual(CrewCrestArt.colors(CrewCrest(frame: "castle", emblem: "dragon", color: "ultraviolet"), laurel: nil),
                       CrewCrestArt.colors(.default, laurel: nil))
        for id in CrewCatalog.frames { XCTAssertFalse(CrewCatalog.frameTitle(id).isEmpty) }
        for id in CrewCatalog.emblems { XCTAssertFalse(CrewCatalog.emblemTitle(id).isEmpty) }
    }

    // MARK: Crest art

    func testEveryCombinationComposes() {
        let art = CrewCrestArt.art
        for frame in CrewCatalog.frames {
            for emblem in CrewCatalog.emblems {
                for laurel in [nil] + CrewLaurel.allCases.map(Optional.some) {
                    let crest = CrewCrest(frame: frame, emblem: emblem, color: CrewCatalog.colors[0].id)
                    let characters = CrewCrestArt.canvas(crest, laurel: laurel, pips: 3)
                    let pixels = CrewCrestArt.colors(crest, laurel: laurel, pips: 3)
                    XCTAssertEqual(pixels.count, art.grid * art.grid)
                    XCTAssertEqual(pixels.compactMap { $0 }.count, characters.compactMap { $0 }.count,
                                   "a character without a color in \(frame) \(emblem) \(String(describing: laurel))")
                }
            }
        }
    }

    /// The crew color fills the frame; the laurel and the pips only add pixels
    /// and the emblem sits on top of the frame.
    func testLayers() {
        let crest = CrewCrest.default
        XCTAssertNotEqual(CrewCrestArt.colors(crest, laurel: nil),
                          CrewCrestArt.colors(CrewCrest(frame: crest.frame, emblem: crest.emblem, color: CrewCatalog.colors[4].id), laurel: nil))
        let plain = CrewCrestArt.canvas(crest, laurel: nil)
        let crowned = CrewCrestArt.canvas(crest, laurel: .gold, pips: 3)
        XCTAssertGreaterThan(crowned.compactMap { $0 }.count, plain.compactMap { $0 }.count)
        for (index, character) in plain.enumerated() where character != nil {
            XCTAssertEqual(crowned[index], character, "the laurel or pips cover the crest at \(index)")
        }
        XCTAssertNotEqual(CrewCrestArt.colors(crest, laurel: .gold), CrewCrestArt.colors(crest, laurel: .bronze))
        XCTAssertEqual(CrewCrestArt.canvas(crest, laurel: nil, pips: 9), CrewCrestArt.canvas(crest, laurel: nil, pips: 3))
    }

    /// A small emblem sits in the middle of the frame's slot.
    func testSmallEmblemsAreCentered() throws {
        let shipped = try Data(contentsOf: root.appendingPathComponent("Sources/TabbiKitCore/Pets/PetArt/crew.json"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: shipped) as? [String: Any])
        var emblems = json["emblems"] as! [[String: Any]]
        emblems[0]["grid"] = ["WW", "WW"]
        json["emblems"] = emblems
        let art = try CrewCrestSet.decode(JSONSerialization.data(withJSONObject: json))
        let frame = art.frames[0]
        let crest = CrewCrest(frame: frame.id, emblem: art.emblems[0].id, color: art.colorIDs[0])
        let pixels = CrewCrestArt.canvas(crest, laurel: nil, in: art)
        let x = frame.slot.x + (art.slot - 2) / 2, y = frame.slot.y + (art.slot - 2) / 2
        for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
            XCTAssertEqual(pixels[(y + dy) * art.grid + x + dx], "W")
        }
    }

    func testShuffleAlwaysChangesTheCrest() {
        var generator = SystemRandomNumberGenerator()
        var form = CrewCrest.default
        for _ in 0..<50 {
            let next = CrewCrest.random(using: &generator).resolved
            XCTAssertEqual(next, next.resolved)
            form = next
        }
        XCTAssertNotNil(form)
    }

    func testCrestSetRejectsBrokenFiles() throws {
        let shipped = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appendingPathComponent("Sources/TabbiKitCore/Pets/PetArt/crew.json"))) as? [String: Any])
        func load(_ change: (inout [String: Any]) -> Void) -> Bool {
            var copy = shipped
            change(&copy)
            return (try? CrewCrestSet.decode(try! JSONSerialization.data(withJSONObject: copy))) != nil
        }
        XCTAssertTrue(load { _ in })
        XCTAssertFalse(load { $0["schema"] = "crewCrests.v2" })
        XCTAssertFalse(load { $0["frames"] = [] }, "no frames")
        XCTAssertFalse(load {
            var frames = $0["frames"] as! [[String: Any]]
            frames[0]["slot"] = [30, 30]
            $0["frames"] = frames
        }, "slot outside the grid")
        XCTAssertFalse(load {
            var emblems = $0["emblems"] as! [[String: Any]]
            emblems[0]["grid"] = Array(repeating: String(repeating: ".", count: 40), count: 40)
            $0["emblems"] = emblems
        }, "an emblem larger than the slot")
        XCTAssertTrue(load {
            var emblems = $0["emblems"] as! [[String: Any]]
            emblems[0]["grid"] = [".oo.", "oWWo", "oWWo", ".oo."]
            $0["emblems"] = emblems
        }, "a small emblem is fine")
        XCTAssertFalse(load {
            var emblems = $0["emblems"] as! [[String: Any]]
            emblems[0]["grid"] = ["...", "...."]
            $0["emblems"] = emblems
        }, "ragged rows")
        XCTAssertFalse(load {
            var emblems = $0["emblems"] as! [[String: Any]]
            var grid = emblems[0]["grid"] as! [String]
            grid[0] = "?" + grid[0].dropFirst()
            emblems[0]["grid"] = grid
            $0["emblems"] = emblems
        }, "unknown character")
        XCTAssertFalse(load {
            var emblems = $0["emblems"] as! [[String: Any]]
            emblems.append(emblems[0])
            $0["emblems"] = emblems
        }, "duplicate ids")
        XCTAssertFalse(load { $0["ranks"] = ["gold": ["leaf": "#F2C14E", "shade": "#C98A2A"]] }, "missing rank")
        XCTAssertFalse(load { $0["laurel"] = ["...."] }, "laurel size")
    }

    // MARK: Models

    func testDecodesOlderAndNewerReplies() throws {
        let decoder = PartyClient.makeDecoder()
        let summary = try decoder.decode(CrewSummary.self, from: Data(#"""
            {"id":"NGHTQWLS2K","name":"Night Owls","frame":"x","emblem":"z","color":"y","visibility":"unlisted","laurel":"platinum","memberCount":2}
            """#.utf8))
        XCTAssertEqual(summary.visibility, .private, "an unknown visibility offers no Join")
        XCTAssertNil(summary.laurel)
        XCTAssertEqual(summary.maxMembers, CrewCatalog.maxMembers)
        XCTAssertEqual(summary.description, "")
        XCTAssertEqual(summary.crest.resolved, .default)
        let member = try decoder.decode(CrewMember.self, from: Data(#"{"ref":"R","name":"N","pet":null}"#.utf8))
        XCTAssertNil(member.partyProfile)
        XCTAssertEqual(member.weekMinutes, 0)
        XCTAssertEqual(CrewSessionStatus(rawValue: "brand_new"), .other("brand_new"))
    }

    func testCrewDetailRoundTrips() throws {
        let now = Date(timeIntervalSince1970: 1_794_300_000)
        let detail = CrewDemoData(now: now, week: .containing(now)).mine(requests: true)
        XCTAssertFalse(detail.requests.isEmpty)
        XCTAssertFalse(detail.history.isEmpty)
        let data = try PartyClient.makeEncoder().encode(detail)
        XCTAssertEqual(try PartyClient.makeDecoder().decode(CrewDetail.self, from: data), detail)
    }

    func testLaurelForRank() {
        XCTAssertEqual(CrewLaurel(rank: 1), .gold)
        XCTAssertEqual(CrewLaurel(rank: 3), .bronze)
        XCTAssertNil(CrewLaurel(rank: 4))
    }

    // MARK: Week and formats

    func testWeekIsMondayToMondayUTC() {
        let week = CrewWeek.containing(Date(timeIntervalSince1970: 1_794_700_000))
        XCTAssertEqual(week.id, "2026-W46")
        XCTAssertEqual(week.startsAt.timeIntervalSince1970, 1_794_182_400, "Monday 9 November 2026, 00:00 UTC")
        XCTAssertEqual(week.endsAt.timeIntervalSince(week.startsAt), 7 * 86_400)
        XCTAssertEqual(CrewWeek.containing(week.endsAt).id, "2026-W47")
        XCTAssertEqual(CrewWeek.containing(week.endsAt.addingTimeInterval(-1)).id, "2026-W46")
    }

    func testHoursAndCountdown() {
        XCTAssertEqual(CrewFormat.tenths(minutes: 59), 9)
        XCTAssertEqual(CrewFormat.tenths(minutes: 600), 100)
        XCTAssertEqual(CrewFormat.tenths(minutes: -5), 0)
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(CrewFormat.hours(minutes: 600, locale: en), String(localized: "\("10.0") h", bundle: .tabbi))
        XCTAssertEqual(CrewFormat.hours(minutes: 59, locale: Locale(identifier: "de_DE")),
                       String(localized: "\("0,9") h", bundle: .tabbi), "always one decimal, in the locale's numbers")
        let end = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(CrewFormat.remainingValue(until: end, now: end.addingTimeInterval(-59)), .lessThanAMinute)
        XCTAssertEqual(CrewFormat.remainingValue(until: end, now: end.addingTimeInterval(-3_660)), .hoursMinutes(1, 1))
        XCTAssertEqual(CrewFormat.remainingValue(until: end, now: end.addingTimeInterval(-(2 * 86_400 + 5 * 3600 + 59))),
                       .daysHours(2, 5))
        XCTAssertEqual(CrewFormat.remainingValue(until: end, now: end.addingTimeInterval(10)), .lessThanAMinute)
    }

    /// Long names get soft hyphens so a tile wraps them at a syllable, even
    /// when the app's language has no hyphenation (a German name in Arabic).
    func testLongNamesBreakAtSyllables() {
        for language in ["en", "de", "ar", "ja"] {
            let name = CrewHyphenation.hyphenated("Bibliotheksratten", locale: Locale(identifier: language))
            XCTAssertTrue(name.contains("\u{AD}"), language)
            XCTAssertEqual(name.replacingOccurrences(of: "\u{AD}", with: ""), "Bibliotheksratten")
        }
        XCTAssertEqual(CrewHyphenation.hyphenated("Night Owls"), "Night Owls", "short words stay whole")
    }

    func testCountdownTicksWhenItsTextChanges() {
        let week = CrewWeek(id: "w", startsAt: Date(timeIntervalSince1970: 0), endsAt: Date(timeIntervalSince1970: 1_000_000))
        let now = Date(timeIntervalSince1970: 1_000_000 - 3 * 86_400 - 1_800)
        XCTAssertEqual(CrewFormat.nextChange(week, now: now).timeIntervalSince(now), 1_800)
        let close = Date(timeIntervalSince1970: 1_000_000 - 90)
        XCTAssertEqual(CrewFormat.nextChange(week, now: close).timeIntervalSince(close), 30)
        XCTAssertEqual(CrewFormat.nextChange(week, now: week.endsAt.addingTimeInterval(5)), week.endsAt)
    }

    // MARK: Session queue

    func testQueueKeepsEachStretchOnceAndPersists() throws {
        let t = Date(timeIntervalSince1970: 1_794_300_000)
        var queue = CrewSessionQueue()
        queue.add(CrewSession(start: t, end: t.addingTimeInterval(1500), minutes: 25))
        queue.add(CrewSession(start: t.addingTimeInterval(1200), end: t.addingTimeInterval(2400), minutes: 20))
        XCTAssertEqual(queue.pending, [CrewSession(start: t, end: t.addingTimeInterval(2400), minutes: 40)])
        for i in 0..<30 {
            queue.add(CrewSession(start: t.addingTimeInterval(Double(10_000 + i * 4000)),
                                  end: t.addingTimeInterval(Double(11_000 + i * 4000)), minutes: 10))
        }
        XCTAssertEqual(queue.nextBatch.count, CrewCatalog.maxSessionsPerReport)
        XCTAssertEqual(queue.nextBatch.first?.start, t)
        queue.didSend(queue.nextBatch)
        XCTAssertEqual(queue.pending.count, 11)
        queue.prune(now: t.addingTimeInterval(CrewSessionQueue.maxAge + 200_000))
        XCTAssertLessThan(queue.pending.count, 11)

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("crews-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = CrewSessionQueueFile(folder: folder)
        XCTAssertEqual(file.load(), CrewSessionQueue())
        try file.save(queue)
        XCTAssertEqual(file.load(), queue)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file.url)) as? [String: Any])
        XCTAssertEqual(saved[VersionedJSON.versionKey] as? Int, 1)
        try Data("not json".utf8).write(to: file.url)
        XCTAssertEqual(file.load(), CrewSessionQueue(), "a broken file starts over")
    }

    func testOnlyFinishedFocusIsReported() {
        let t = Date(timeIntervalSince1970: 1_794_300_000)
        XCTAssertNil(CrewSessionQueue.session(for: ActivityRecord(source: .focus, kind: .breakTaken, start: t,
                                                                  end: t.addingTimeInterval(300), quantity: 5, unit: .minutes)))
        XCTAssertNil(CrewSessionQueue.session(for: ActivityRecord(source: .anki, kind: .cardsReviewed, start: t,
                                                                  end: t.addingTimeInterval(300), quantity: 40, unit: .cards)))
        XCTAssertEqual(CrewSessionQueue.session(for: ActivityRecord(source: .focus, kind: .focusCompleted, start: t,
                                                                    end: t.addingTimeInterval(60 * 800), quantity: 800, unit: .minutes))?
            .minutes, CrewCatalog.maxSessionMinutes)
    }

    // MARK: State and checks

    func testStateNavigation() {
        let now = Date()
        var state = CrewsState.demo(.crew, now: now)
        XCTAssertEqual(state.pushed?.from, .week)
        state.pop()
        XCTAssertNil(state.pushed)
        XCTAssertEqual(state.section, .week)
        state = CrewsState.demo(.edit, now: now)
        state.didLoadMine(nil, week: state.week)
        XCTAssertNil(state.pushed, "leaving closes the edit form")
        XCTAssertFalse(state.inCrew)
        state.show(.find)
        XCTAssertEqual(state.section, .find)

        state = CrewsState.demo(.week, now: now)
        XCTAssertNotNil(state.myWeekEntry, "my crew is on the demo board")
        XCTAssertFalse(state.isQuietWeek)
        XCTAssertTrue(CrewsState.demo(.quietWeek, now: now).isQuietWeek)
        var page = try! XCTUnwrap(state.board)
        let before = state.weekEntries.count
        page.rows = [page.rows[0]]
        state.didLoadBoard(page, appending: true)
        XCTAssertEqual(state.weekEntries.count, before, "a row already loaded is not repeated")
    }

    func testRequestsFollowMine() {
        let now = Date()
        var state = CrewsState.demo(.requested, now: now)
        let crew = try! XCTUnwrap(state.myRequest?.crew.id)
        XCTAssertTrue(state.hasRequested(crew))
        let mine = CrewsState.demo(.mine, now: now).mine
        state.didLoadMine(mine, week: state.week, request: state.myRequest)
        XCTAssertNil(state.myRequest, "a request ends once I am in a crew")
    }

    func testDraftChecks() {
        XCTAssertEqual(CrewDraftCheck.problem(name: "  ", description: ""), .nameEmpty)
        XCTAssertEqual(CrewDraftCheck.problem(name: String(repeating: "x", count: 25), description: ""), .nameTooLong)
        XCTAssertNil(CrewDraftCheck.problem(name: "Scunthorpe Scholars", description: ""))
        XCTAssertEqual(CrewDraftCheck.clean(" two\nlines "), "two lines")
    }

    func testCrewErrorsReadFriendly() {
        XCTAssertNotEqual(CrewErrorText.message(.server(code: "in_crew", status: 409)),
                          PartyError.server(code: "in_crew", status: 409).message)
        XCTAssertEqual(CrewErrorText.message(.unreachable), PartyError.unreachable.message)
    }

    func testCrewLinksAreAppLinks() throws {
        let link = try XCTUnwrap(AppLink(url: URL(string: "tabbi://crew/W4LNUT7")!))
        XCTAssertEqual(link, .crew(CrewInvite(code: "W4LNUT7")!))
        XCTAssertEqual(CrewInvite(code: "w4ln-ut7")?.webURL.absoluteString, "https://tabbinotch.com/crew/W4LNUT7")
        XCTAssertEqual(CrewInvite(code: "W4LNUT7")?.appURL.absoluteString, "tabbi://crew/W4LNUT7")
        // Party links still read as Party links.
        XCTAssertEqual(AppLink(url: URL(string: "tabbi://join/Q4RT8M")!), .invite(.joinParty(code: "Q4RT8M")))
    }
}
