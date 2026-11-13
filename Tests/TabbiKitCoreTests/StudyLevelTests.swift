import Foundation
import TabbiKitCore
import XCTest

/// The Study Level: its curve, ranks, nameplate colors, the save that
/// keeps it, the quiet replay of old history, and the rule that leveling
/// never pays study points. docs/design/progression.md explains the design.
final class StudyLevelTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func focus(_ minutes: Double, daysAgo: Int, now: Date, source: ModuleID = .focus) -> ActivityRecord {
        let end = now.addingTimeInterval(-Double(daysAgo) * 86_400)
        return ActivityRecord(source: source, kind: .focusCompleted, start: end.addingTimeInterval(-minutes * 60), end: end,
                              quantity: minutes, unit: .minutes)
    }

    // MARK: Curve

    func testTheCurveMatchesTheDesignTable() {
        // round(4 * n^1.6): the numbers docs/design/progression.md lists.
        let expected = [1: 4, 2: 12, 3: 23, 4: 37, 5: 53, 10: 159, 12: 213, 13: 242, 25: 690, 37: 1292, 50: 2091,
                        60: 2800, 64: 3104, 100: 6340, 999: 251_979]
        for (level, hours) in expected {
            XCTAssertEqual(StudyLevel.hoursToReach(level), hours, "level \(level)")
        }
        XCTAssertEqual(StudyLevel.hoursToReach(0), 0)
        XCTAssertEqual(StudyLevel.hoursToReach(-3), 0)
        XCTAssertEqual(StudyLevel.minutesToReach(1), 240)
    }

    func testEveryLevelAsksMoreThanTheOneBefore() {
        // Whole hours round, so neighbouring gaps can differ by one hour
        // either way; the curve itself only ever steepens.
        var previousGap = 0
        for level in 1...1000 {
            let gap = StudyLevel.hoursToReach(level) - StudyLevel.hoursToReach(level - 1)
            XCTAssertGreaterThanOrEqual(gap, previousGap - 1, "the curve never eases off at level \(level)")
            XCTAssertGreaterThan(gap, 0)
            previousGap = max(previousGap, gap)
        }
    }

    func testLevelsFromFocusMinutesLandOnTheBoundaries() {
        XCTAssertEqual(StudyLevel(focusMinutes: 0).value, 0)
        XCTAssertEqual(StudyLevel(focusMinutes: 239).value, 0)
        XCTAssertEqual(StudyLevel(focusMinutes: 240).value, 1)
        XCTAssertEqual(StudyLevel(focusMinutes: 719).value, 1)
        XCTAssertEqual(StudyLevel(focusMinutes: 720).value, 2)
        XCTAssertEqual(StudyLevel(focusMinutes: 242 * 60 - 1).value, 12)
        XCTAssertEqual(StudyLevel(focusMinutes: 242 * 60).value, 13)
        XCTAssertEqual(StudyLevel(focusMinutes: -50).value, 0)
        // Endless: a lifetime of focus keeps counting.
        XCTAssertEqual(StudyLevel(focusMinutes: 251_979 * 60).value, 999)
        XCTAssertEqual(StudyLevel(focusMinutes: 300_000 * 60).value, 1114)
    }

    func testFractionFillsWithinTheLevel() {
        let level = StudyLevel(12)
        XCTAssertEqual(level.fraction(focusMinutes: 213 * 60), 0)
        XCTAssertEqual(level.fraction(focusMinutes: 242 * 60), 1)
        XCTAssertEqual(level.fraction(focusMinutes: 227 * 60 + 30), 14.5 / 29, accuracy: 1e-9)
        XCTAssertEqual(StudyLevel(0).fraction(focusMinutes: 120), 0.5)
    }

    // MARK: Ranks

    func testRanksComeEveryTenLevelsAndThenCount() {
        let cases: [(Int, String)] = [(0, "spark"), (9, "spark"), (10, "ember"), (19, "ember"), (20, "comet"),
                                      (30, "nova"), (40, "nebula"), (49, "nebula"), (50, "galaxy"), (59, "galaxy"),
                                      (60, "galaxy-2"), (70, "galaxy-3"), (99, "galaxy-5"), (140, "galaxy-10")]
        for (level, id) in cases {
            XCTAssertEqual(StudyRank(level: level).id, id, "level \(level)")
        }
        XCTAssertEqual(StudyRank(level: 64).firstLevel, 60)
        XCTAssertEqual(StudyRank(level: 37).firstLevel, 30)
        XCTAssertEqual(StudyRank(level: 37).next.id, "nebula")
        XCTAssertEqual(StudyRank(level: 55).next.id, "galaxy-2")
        XCTAssertEqual(StudyRank(level: 3).pips, 0)
        XCTAssertEqual(StudyRank(level: 60).pips, 1)
        XCTAssertEqual(StudyRank(level: 70).pips, 2)
        XCTAssertEqual(StudyRank(level: 500).pips, RankArt.maxPips)
        XCTAssertLessThan(StudyRank(level: 49), StudyRank(level: 50))
    }

    func testRankNamesAreShortAndNumbered() {
        XCTAssertEqual(StudyRank.roman(2), "II")
        XCTAssertEqual(StudyRank.roman(4), "IV")
        XCTAssertEqual(StudyRank.roman(14), "XIV")
        XCTAssertEqual(StudyRank.roman(95), "XCV")
        XCTAssertEqual(StudyRank.roman(4000), "4000")
        XCTAssertTrue(StudyRank(level: 60).displayName.hasSuffix(" II"))
        XCTAssertTrue(StudyRank(level: 70).displayName.hasSuffix(" III"))
        for tier in StudyRank.Tier.allCases {
            XCTAssertLessThanOrEqual(tier.displayName.count, 10, "\(tier) stays short")
        }
    }

    // MARK: Emblems

    func testEveryRankHasItsOwnWholeEmblem() {
        let named = StudyRank.Tier.allCases.map { StudyRank(tier: $0) }
        let canvases = named.map(RankArt.canvas)
        XCTAssertEqual(Set(canvases.map(\.pixels)).count, named.count, "every named rank looks its own")
        for (rank, canvas) in zip(named, canvases) {
            XCTAssertEqual(canvas.width, RankArt.size)
            XCTAssertEqual(canvas.height, RankArt.size)
            XCTAssertTrue(canvas.pixels.contains(.outline), "\(rank) is outlined")
            // The emblem sits one pixel in: the outer ring stays clear but for stars.
            for x in 0..<RankArt.size {
                XCTAssertNil(canvas[x, 0], "\(rank) top edge")
                XCTAssertNil(canvas[x, RankArt.size - 1], "\(rank) bottom edge")
            }
            XCTAssertEqual(RankArt.colors(rank).count, RankArt.size * RankArt.size)
        }
    }

    func testGalaxyRanksAddAStarEach() {
        func stars(_ numeral: Int) -> Int {
            RankArt.canvas(StudyRank(tier: .galaxy, numeral: numeral)).pixels.filter { $0 == .gold }.count
        }
        let core = stars(1)
        XCTAssertEqual(stars(2) - core, 4, "one star of four gold pixels")
        XCTAssertEqual(stars(3) - core, 8)
        XCTAssertEqual(stars(5) - core, 16)
        XCTAssertEqual(stars(9), stars(5), "four stars at most; the numeral counts on")
        XCTAssertNotEqual(RankArt.canvas(StudyRank(level: 60)), RankArt.canvas(StudyRank(level: 70)))
        XCTAssertEqual(RankArt.image(StudyRank(level: 64), scale: 4)?.width, RankArt.size * 4)
    }

    // MARK: Nameplates

    func testANewNameplateEveryFiveLevels() {
        XCTAssertEqual(Nameplate.unlocked(at: StudyLevel(0)), [.plain])
        XCTAssertEqual(Nameplate.unlocked(at: StudyLevel(4)), [.plain])
        XCTAssertEqual(Nameplate.unlocked(at: StudyLevel(5)), [.plain, .peach])
        XCTAssertEqual(Nameplate.unlocked(at: StudyLevel(12)).count, 3)
        XCTAssertEqual(Nameplate.unlocked(at: StudyLevel(60)), Nameplate.allCases)
        XCTAssertEqual(Nameplate.next(after: StudyLevel(12)), .honey)
        XCTAssertNil(Nameplate.next(after: StudyLevel(60)))
        XCTAssertEqual(Nameplate(unlockedAt: 15), .honey)
        XCTAssertNil(Nameplate(unlockedAt: 16))
        XCTAssertNil(Nameplate(unlockedAt: 65))
        XCTAssertTrue(StudyLevel(5).unlocksNameplate)
        XCTAssertFalse(StudyLevel(65).unlocksNameplate, "the palette ends at 60")
        XCTAssertTrue(StudyLevel(10).startsRank)
        XCTAssertFalse(StudyLevel(0).startsRank)
        XCTAssertEqual(Nameplate.allCases.filter(\.glows), [.nebula, .coral, .gold, .aurora, .starlight])
    }

    func testEveryNameplateReadsOnTheBlackNotch() {
        let black = PetColor(red: 0, green: 0, blue: 0)
        for nameplate in Nameplate.allCases {
            XCTAssertGreaterThanOrEqual(nameplate.color.contrast(with: black), 7, "\(nameplate) on black")
        }
        XCTAssertEqual(Set(Nameplate.allCases.map(\.color)).count, Nameplate.allCases.count, "every color its own")
    }

    // MARK: Progression

    func testLongHistoryLandsAtTheRealLevelQuietlyWithADot() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        // 40 days of 6 hours: 240 hours, level 12.
        let records = (1...40).map { focus(360, daysAgo: $0, now: now) }
        var progression = PetProgression(tally: ProgressTally(records: records, calendar: calendar))
        let change = progression.refresh(at: now, calendar: calendar)
        XCTAssertEqual(progression.studyLevel, StudyLevel(12))
        XCTAssertEqual(change.levels.map(\.value), Array(1...12), "every level counted once, lowest first")
        XCTAssertTrue(change.unlocksSomething)
        XCTAssertTrue(progression.hasUnseenLevel, "the Goals pill's dot")
        XCTAssertTrue(progression.markSeen())
        XCTAssertFalse(progression.hasUnseenLevel)
        XCTAssertFalse(progression.markSeen())
        // A second refresh with nothing new gains nothing.
        XCTAssertTrue(progression.refresh(at: now, calendar: calendar).levels.isEmpty)
    }

    func testDeletingDayFilesNeverLowersTheLevel() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var progression = PetProgression(tally: ProgressTally(records: (1...40).map { focus(360, daysAgo: $0, now: now) },
                                                              calendar: calendar))
        progression.refresh(at: now, calendar: calendar)
        let saved = try ProgressionSave.load(from: write(progression.save))
        // The log is gone; only the save is left.
        var reread = PetProgression(save: try XCTUnwrap(saved))
        reread.refresh(at: now, calendar: calendar)
        XCTAssertEqual(reread.studyLevel, StudyLevel(12))
        XCTAssertEqual(reread.focusMinutes, 240 * 60)
        // Even a save whose minutes were lost keeps the level it reached.
        var lostMinutes = PetProgression(save: ProgressionSave(level: 12, levelSeen: 12))
        lostMinutes.refresh(at: now, calendar: calendar)
        XCTAssertEqual(lostMinutes.studyLevel, StudyLevel(12))
    }

    func testANameplateIsPickedOnlyOnceUnlocked() {
        var progression = PetProgression(save: ProgressionSave(best: [.focusHours: 242 * 60], level: 13))
        XCTAssertEqual(progression.nameplate, .plain)
        XCTAssertFalse(progression.pick(.honey), "level 15 not reached yet")
        XCTAssertTrue(progression.pick(.ember))
        XCTAssertEqual(progression.nameplate, .ember)
        XCTAssertEqual(progression.standing, StudyStanding(level: StudyLevel(13), nameplate: .ember))
        XCTAssertFalse(progression.pick(.ember), "already picked")
        XCTAssertTrue(progression.pick(.plain))
        XCTAssertNil(progression.save.nameplate, "plain is stored as none")
    }

    // MARK: Save

    func testAVersion1SaveMigratesToNoLevelYet() throws {
        let v1 = #"{"schemaVersion":1,"best":{"focusHours":15000},"reached":{},"completedMonths":[],"seen":[]}"#
        let save = try ProgressionSave.schema.decode(ProgressionSave.self, from: Data(v1.utf8))
        XCTAssertEqual(save.level, 0)
        XCTAssertEqual(save.levelSeen, 0)
        XCTAssertNil(save.nameplate)
        XCTAssertEqual(save.best[.focusHours], 15000)
        var progression = PetProgression(save: save)
        let change = progression.refresh(at: Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(progression.studyLevel, StudyLevel(13), "250 hours")
        XCTAssertEqual(change.levels.count, 13)
        XCTAssertTrue(progression.hasUnseenLevel)
        let written = try XCTUnwrap(String(data: progression.save.encoded(), encoding: .utf8))
        XCTAssertTrue(written.contains(#""schemaVersion" : 2"#))
        XCTAssertTrue(written.contains(#""level" : 13"#))
        XCTAssertTrue(written.contains(#""levelSeen" : 0"#))
    }

    func testTheSaveReadsLeniently() throws {
        let odd = #"{"schemaVersion":2,"level":-4,"levelSeen":"x","nameplate":"neon"}"#
        let save = try ProgressionSave.schema.decode(ProgressionSave.self, from: Data(odd.utf8))
        XCTAssertEqual(save.level, 0)
        XCTAssertEqual(save.levelSeen, 0)
        XCTAssertNil(save.nameplate, "an unknown color reads as plain")
        let seenAbove = ProgressionSave(level: 3, levelSeen: 9, nameplate: .plain)
        XCTAssertEqual(seenAbove.levelSeen, 3, "never seen above what was reached")
        XCTAssertNil(seenAbove.nameplate)
        let round = try ProgressionSave.schema.decode(
            ProgressionSave.self, from: ProgressionSave(level: 37, levelSeen: 30, nameplate: .lilac).encoded())
        XCTAssertEqual(round, ProgressionSave(level: 37, levelSeen: 30, nameplate: .lilac))
    }

    // MARK: Points

    /// Levels pay nothing: a block that crosses a level earns exactly the
    /// points the same block earns anywhere else, and the progression,
    /// which owns the level, never sees the ledger at all.
    func testLevelingNeverChangesThePointsLedger() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        // 3 h 50 min of history, then one 25 minute block crosses level 1.
        let history = (1...23).map { focus(10, daysAgo: $0, now: now) }
        let end = now.addingTimeInterval(-60)
        let crossing = ActivityRecord(source: .focus, kind: .focusCompleted, start: end.addingTimeInterval(-25 * 60),
                                      end: end, quantity: 25, unit: .minutes,
                                      metadata: [ActivityMetadata.outcome: StudyPhaseOutcome.skipped.rawValue])
        var progression = PetProgression(tally: ProgressTally(records: history, calendar: calendar))
        progression.refresh(at: now, calendar: calendar)
        XCTAssertEqual(progression.studyLevel, StudyLevel(0))

        var leveling = PetCloset(save: PetSave(profile: .starter(.cat)))
        let before = leveling.save.ledger
        let award = leveling.credit(crossing)
        progression.add(crossing, calendar: calendar)
        let change = progression.refresh(at: now, calendar: calendar)
        XCTAssertEqual(change.levels, [StudyLevel(1)], "the block reached level 1")

        let expected = PetPointsRules.points(forMinutes: 25, completed: false)
        XCTAssertEqual(award?.points, expected)
        XCTAssertEqual(leveling.save.ledger.earned - before.earned, expected, "no bonus for the level")
        XCTAssertEqual(leveling.save.ledger.spent, before.spent)
        XCTAssertEqual(leveling.save.ledger.granted, before.granted)
    }

    // MARK: Party

    func testPartyProfilesReadTheLevelAndOlderOnesReadNone() throws {
        func decode(_ extra: String) throws -> PartyProfile {
            let json = #"{"code":"K7QW2MZD","name":"Ana","petName":"Mochi","species":"cat","breed":"tabby","colors":[],"costume":"none","accessories":[],"points":0,"level":1"# + extra + "}"
            return try JSONDecoder().decode(PartyProfile.self, from: Data(json.utf8))
        }
        let current = try decode(#","studyLevel":37,"nameplate":"lilac""#)
        XCTAssertEqual(current.standing, StudyStanding(level: StudyLevel(37), nameplate: .lilac))
        XCTAssertEqual(current.standing?.rank.id, "nova")
        XCTAssertNil(try decode("").standing, "an older app or server shows no level")
        XCTAssertEqual(try decode(#","studyLevel":12,"nameplate":"neon-from-the-future""#).standing?.nameplate, .plain)
        XCTAssertNil(try decode(#","studyLevel":"12""#).standing, "garbage is left out, not an error")
        XCTAssertNil(try decode(#","studyLevel":5000"#).standing, "out of range is left out")
        XCTAssertNil(try decode(#","studyLevel":null,"nameplate":null"#).standing)
    }

    func testProfileUpdatesShareTheLevelAndDropItForOlderServers() throws {
        let update = PartyProfileUpdate(petName: "Mochi")
            .sharing(StudyStanding(level: StudyLevel(1200), nameplate: .gold))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(update)) as? [String: Any])
        XCTAssertEqual(body["studyLevel"] as? Int, StudyLevel.maxShared, "capped at what the server keeps")
        XCTAssertEqual(body["nameplate"] as? String, "gold")
        let older = update.withoutStudyLevel()
        let olderBody = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(older)) as? [String: Any])
        XCTAssertNil(olderBody["studyLevel"])
        XCTAssertNil(olderBody["nameplate"])
        XCTAssertEqual(olderBody["petName"] as? String, "Mochi")
        let plain = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(PartyProfileUpdate(name: "A")))
            as? [String: Any])
        XCTAssertNil(plain["studyLevel"], "nothing sent until the level is known")
    }

    private func write(_ save: ProgressionSave) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("study-level-\(UUID().uuidString).json")
        try save.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
