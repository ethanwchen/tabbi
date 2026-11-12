import Foundation
import TabbiKitCore
import XCTest

/// Pins the Study Level to the golden fixture
/// `shared/fixtures/progression/levels.json`: the curve, the level and
/// rank for a spread of focus totals, Roman numerals, the nameplate
/// colors, every rank emblem's pixels, how the progression save's level
/// fields read and write, and progressions replayed from a save and a
/// focus total. The Windows port replays the inputs and must agree to the
/// minute and the pixel. Run with `TABBI_RECORD_FIXTURES=1` to rewrite it
/// after an intended change.
final class StudyLevelGoldenTests: XCTestCase {
    private var isRecording: Bool { ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1" }

    func testStudyLevelMatchesGoldenFixture() throws {
        let url = StudyLevelGoldenFixture.url
        let current = try StudyLevelGoldenFixture.current()
        if isRecording {
            try PetGoldenFixtures.encode(current).write(to: url)
            return
        }
        let stored = try JSONDecoder().decode(StudyLevelGoldenFixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(stored.constants, current.constants, "Constants changed")
        XCTAssertEqual(stored.curve, current.curve, "The curve changed")
        XCTAssertEqual(stored.levels, current.levels, "Levels changed")
        XCTAssertEqual(stored.roman, current.roman)
        XCTAssertEqual(stored.nameplates, current.nameplates, "Nameplates changed")
        XCTAssertEqual(stored.emblems.map(\.rank), current.emblems.map(\.rank))
        for (old, new) in zip(stored.emblems, current.emblems) { XCTAssertEqual(old, new, "Emblem \(old.rank)") }
        for (old, new) in zip(stored.saves, current.saves) { XCTAssertEqual(old, new, "Save \(old.name)") }
        for (old, new) in zip(stored.scenarios, current.scenarios) { XCTAssertEqual(old, new, "Scenario \(old.name)") }
        XCTAssertEqual(stored, current, "The Study Level no longer matches \(url.lastPathComponent)")
    }

    /// The fixture's inputs, replayed, give its outputs.
    func testStoredInputsReplayToStoredOutputs() throws {
        try XCTSkipIf(isRecording, "Recording")
        typealias Fixture = StudyLevelGoldenFixture
        let stored = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: Fixture.url))
        XCTAssertEqual(stored.levels.map { Fixture.Level(focusMinutes: $0.focusMinutes) }, stored.levels)
        XCTAssertEqual(stored.curve.map { Fixture.Curve(level: $0.level) }, stored.curve)
        for save in stored.saves { XCTAssertEqual(try Fixture.Save(name: save.name, json: save.json), save, save.name) }
        for scenario in stored.scenarios {
            XCTAssertEqual(Fixture.Scenario(name: scenario.name, input: scenario.input), scenario, scenario.name)
        }
    }
}

struct StudyLevelGoldenFixture: Codable, Equatable {
    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/progression/levels.json")
    }

    var schema = "tabbi.levels.golden"
    var version = 1
    var constants: Constants
    var curve: [Curve]
    var levels: [Level]
    var roman: [String: String]
    var nameplates: [NameplateEntry]
    var emblems: [Emblem]
    var saves: [Save]
    var scenarios: [Scenario]

    struct Constants: Codable, Equatable {
        var curveScale: Double
        var curveExponent: Double
        var levelsPerNameplate: Int
        var levelsPerRank: Int
        var maxShared: Int
        var rankTiers: [String]
        var emblemSize: Int
        var canvasSize: Int
        var maxPips: Int
        var saveSchemaVersion: Int
    }

    struct Curve: Codable, Equatable {
        var level: Int
        var hours: Int
        var minutes: Int

        init(level: Int) {
            self.level = level
            hours = StudyLevel.hoursToReach(level)
            minutes = StudyLevel.minutesToReach(level)
        }
    }

    struct Level: Codable, Equatable {
        var focusMinutes: Int
        var level: Int
        var rank: String
        var numeral: Int
        var pips: Int
        var rankFirstLevel: Int
        var fraction: Double
        var nameplates: [String]
        var nextNameplate: String?

        init(focusMinutes: Int) {
            self.focusMinutes = focusMinutes
            let level = StudyLevel(focusMinutes: focusMinutes)
            self.level = level.value
            rank = level.rank.id
            numeral = level.rank.numeral
            pips = level.rank.pips
            rankFirstLevel = level.rank.firstLevel
            fraction = level.fraction(focusMinutes: focusMinutes)
            nameplates = Nameplate.unlocked(at: level).map(\.rawValue)
            nextNameplate = Nameplate.next(after: level)?.rawValue
        }
    }

    struct NameplateEntry: Codable, Equatable {
        var id: String
        var unlockLevel: Int
        var color: String
        var glows: Bool
    }

    /// An emblem's colors in the pets fixture's `rendered.json` encoding.
    struct Emblem: Codable, Equatable {
        var rank: String
        var colors: [String]
        var rle: String
    }

    struct Save: Codable, Equatable {
        struct Output: Codable, Equatable {
            var level: Int
            var levelSeen: Int
            var nameplate: String?
            var bestFocusMinutes: Int?
            var encoded: String
        }

        var name: String
        var json: String
        var output: Output?

        init(name: String, json: String) throws {
            self.name = name
            self.json = json
            guard let save = try? ProgressionSave.schema.decode(ProgressionSave.self, from: Data(json.utf8)) else {
                output = nil
                return
            }
            output = try Output(level: save.level, levelSeen: save.levelSeen, nameplate: save.nameplate?.rawValue,
                                bestFocusMinutes: save.best[.focusHours],
                                encoded: String(decoding: save.encoded(), as: UTF8.self))
        }
    }

    struct Scenario: Codable, Equatable {
        struct Input: Codable, Equatable {
            /// The progression save JSON to start from, if any.
            var save: String?
            /// One focus record of this many minutes, if any.
            var focusMinutes: Double?
            /// Nameplate ids picked in order after the refresh.
            var picks: [String]
            /// Whether the Goals shelf was opened after the picks.
            var markSeen: Bool
        }

        struct Output: Codable, Equatable {
            var level: Int
            var rank: String
            /// How many levels the refresh gained, and the lowest and highest.
            var levelsGained: Int
            var firstLevelGained: Int?
            var lastLevelGained: Int?
            var unlocksSomething: Bool
            var picked: [Bool]
            var nameplate: String
            var hasUnseenLevel: Bool
            var savedLevel: Int
            var savedLevelSeen: Int
            var sharedLevel: Int
            var sharedNameplate: String
        }

        var name: String
        var input: Input
        var output: Output

        init(name: String, input: Input) {
            self.name = name
            self.input = input
            let save = input.save.flatMap { try? ProgressionSave.schema.decode(ProgressionSave.self, from: Data($0.utf8)) }
            var tally = ProgressTally()
            if let minutes = input.focusMinutes {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: "UTC")!
                tally.add(ActivityRecord(id: UUID(uuidString: "6F1C2A4E-0000-4000-8000-000000000001")!, source: .focus,
                                         kind: .focusCompleted, start: Date(timeIntervalSince1970: 1_790_000_000),
                                         end: Date(timeIntervalSince1970: 1_790_000_000 + minutes * 60),
                                         quantity: minutes, unit: .minutes), calendar: calendar)
            }
            var progression = PetProgression(save: save ?? ProgressionSave(), tally: tally)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let change = progression.refresh(at: Date(timeIntervalSince1970: 1_800_000_000), calendar: calendar)
            let picked = input.picks.map { id in Nameplate(rawValue: id).map { progression.pick($0) } ?? false }
            if input.markSeen { progression.markSeen() }
            let shared = PartyProfileUpdate().sharing(progression.standing)
            output = Output(level: progression.studyLevel.value, rank: progression.studyLevel.rank.id,
                            levelsGained: change.levels.count, firstLevelGained: change.levels.first?.value,
                            lastLevelGained: change.levels.last?.value, unlocksSomething: change.unlocksSomething,
                            picked: picked, nameplate: progression.nameplate.rawValue,
                            hasUnseenLevel: progression.hasUnseenLevel, savedLevel: progression.save.level,
                            savedLevelSeen: progression.save.levelSeen, sharedLevel: shared.studyLevel ?? -1,
                            sharedNameplate: shared.nameplate ?? "")
        }
    }

    static let emblemRanks: [StudyRank] = StudyRank.Tier.allCases.map { StudyRank(tier: $0) }
        + (2...6).map { StudyRank(tier: .galaxy, numeral: $0) }

    static func current() throws -> StudyLevelGoldenFixture {
        let constants = Constants(curveScale: StudyLevel.curveScale, curveExponent: StudyLevel.curveExponent,
                                  levelsPerNameplate: StudyLevel.levelsPerNameplate,
                                  levelsPerRank: StudyLevel.levelsPerRank, maxShared: StudyLevel.maxShared,
                                  rankTiers: StudyRank.Tier.allCases.map(\.rawValue), emblemSize: RankArt.emblemSize,
                                  canvasSize: RankArt.size, maxPips: RankArt.maxPips,
                                  saveSchemaVersion: ProgressionSave.schema.current)
        let curveLevels = Array(0...120) + [150, 200, 250, 300, 400, 500, 750, 999, 1000, 1426, 2000]
        let minutes = [0, 1, 59, 60, 239, 240, 241, 719, 720, 1379, 1380, 3179, 3180, 9540, 12_779, 12_780, 13_500,
                       14_519, 14_520, 41_400, 77_580, 125_460, 150_000, 168_000, 186_240, 186_300, 214_980, 240_000,
                       380_400, 1_000_000, 15_118_740, 15_118_800, 20_000_000]
        var romans: [String: String] = [:]
        for n in [1, 2, 3, 4, 5, 9, 10, 14, 40, 49, 90, 95, 400, 1994, 3999, 4000] { romans["\(n)"] = StudyRank.roman(n) }
        let nameplates = Nameplate.allCases.map {
            NameplateEntry(id: $0.rawValue, unlockLevel: $0.unlockLevel, color: $0.color.hex, glows: $0.glows)
        }
        let saves = try [
            Save(name: "version 1, no level yet",
                 json: #"{"schemaVersion":1,"best":{"focusHours":15000},"reached":{},"completedMonths":[],"seen":[]}"#),
            Save(name: "version 2, picked lilac",
                 json: #"{"schemaVersion":2,"best":{"focusHours":77580},"level":37,"levelSeen":30,"nameplate":"lilac"}"#),
            Save(name: "unknown nameplate and wrong types",
                 json: #"{"schemaVersion":2,"level":"9","levelSeen":-2,"nameplate":"neon"}"#),
            Save(name: "seen above reached, plain picked",
                 json: #"{"schemaVersion":2,"level":4,"levelSeen":12,"nameplate":"plain"}"#),
            Save(name: "negative level", json: #"{"level":-7}"#),
            Save(name: "not an object", json: "[]"),
        ]
        let scenarios = [
            Scenario(name: "fresh, no focus", input: .init(save: nil, focusMinutes: nil, picks: [], markSeen: false)),
            Scenario(name: "first four hours", input: .init(save: nil, focusMinutes: 240, picks: ["peach"], markSeen: false)),
            Scenario(name: "long history lands quietly", input: .init(
                save: #"{"schemaVersion":1,"best":{"focusHours":186300}}"#, focusMinutes: nil,
                picks: ["gold", "lilac", "plain", "nebula"], markSeen: true)),
            Scenario(name: "deleted logs keep the level", input: .init(
                save: #"{"schemaVersion":2,"best":{"focusHours":100},"level":12,"levelSeen":12,"nameplate":"ember"}"#,
                focusMinutes: nil, picks: [], markSeen: false)),
            Scenario(name: "a locked pick in the save draws plain", input: .init(
                save: #"{"schemaVersion":2,"level":3,"levelSeen":3,"nameplate":"gold"}"#, focusMinutes: 30,
                picks: ["sky"], markSeen: false)),
            Scenario(name: "past the shared cap", input: .init(
                save: #"{"schemaVersion":2,"best":{"focusHours":20000000}}"#, focusMinutes: nil, picks: ["starlight"],
                markSeen: true)),
        ]
        return StudyLevelGoldenFixture(constants: constants, curve: curveLevels.map(Curve.init(level:)),
                                       levels: minutes.map(Level.init(focusMinutes:)), roman: romans,
                                       nameplates: nameplates, emblems: emblemRanks.map(emblem), saves: saves,
                                       scenarios: scenarios)
    }

    static func emblem(_ rank: StudyRank) -> Emblem {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        let colors = RankArt.colors(rank)
        var seen: [PetColor] = []
        var rows: [String] = []
        for y in 0..<RankArt.size {
            var row = ""
            for x in 0..<RankArt.size {
                guard let color = colors[y * RankArt.size + x] else { row.append("."); continue }
                let index = seen.firstIndex(of: color) ?? { seen.append(color); return seen.count - 1 }()
                row.append(letters[index])
            }
            rows.append(row)
        }
        return Emblem(rank: rank.id, colors: seen.map(\.hex), rle: PetGoldenFixtures.runLength(rows))
    }
}
