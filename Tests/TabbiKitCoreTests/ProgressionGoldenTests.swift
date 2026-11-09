import Foundation
import TabbiKitCore
import XCTest

/// Pins the Goals section's logic to the golden fixture
/// `shared/fixtures/progression/progression.json`: every badge's tiers, the
/// tally read from sample activity logs (each track's count, the tiers
/// reached, the mastery outfits unlocked), the gentle streak with freezes,
/// monthly quests and their hash, short labels, and how the progression
/// save reads and writes.
///
/// The Windows port replays the inputs through its own progression and
/// must count, pick quests and unlock exactly like the Mac. Run with
/// `TABBI_RECORD_FIXTURES=1` to rewrite it after an intended change.
final class ProgressionGoldenTests: XCTestCase {
    private var isRecording: Bool { ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1" }

    func testProgressionMatchesGoldenFixture() throws {
        let url = ProgressionGoldenFixture.url
        let current = ProgressionGoldenFixture.current()
        if isRecording {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PetGoldenFixtures.encode(current).write(to: url)
            return
        }
        let stored = try JSONDecoder().decode(ProgressionGoldenFixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(stored.constants, current.constants, "Progression constants changed")
        XCTAssertEqual(stored.tracks, current.tracks, "Badge tiers changed")
        XCTAssertEqual(stored.mastery, current.mastery, "Mastery outfits changed")
        XCTAssertEqual(stored.hashes, current.hashes, "Quest hash changed")
        XCTAssertEqual(stored.labels, current.labels, "Labels changed")
        XCTAssertEqual(stored.streaks.map(\.name), current.streaks.map(\.name))
        for (old, new) in zip(stored.streaks, current.streaks) { XCTAssertEqual(old, new, "Streak \(old.name)") }
        XCTAssertEqual(stored.scenarios.map(\.name), current.scenarios.map(\.name))
        for (old, new) in zip(stored.scenarios, current.scenarios) { XCTAssertEqual(old, new, "Scenario \(old.name)") }
        XCTAssertEqual(stored.saves.map(\.name), current.saves.map(\.name))
        for (old, new) in zip(stored.saves, current.saves) { XCTAssertEqual(old, new, "Save \(old.name)") }
        XCTAssertEqual(stored, current, "The progression no longer matches \(url.lastPathComponent)")
    }

    /// The fixture's own inputs, replayed: a port that reads only the inputs
    /// gets the recorded outputs.
    func testStoredInputsReplayToStoredOutputs() throws {
        try XCTSkipIf(isRecording, "Recording")
        typealias Fixture = ProgressionGoldenFixture
        let stored = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: Fixture.url))
        XCTAssertEqual(stored.hashes.map { Fixture.Hash(text: $0.text) }, stored.hashes)
        XCTAssertEqual(stored.labels.map { Fixture.Label(track: $0.track, value: $0.value, goal: $0.goal) }, stored.labels)
        for streak in stored.streaks {
            XCTAssertEqual(Fixture.Streak(name: streak.name, input: streak.input), streak, streak.name)
        }
        for scenario in stored.scenarios {
            XCTAssertEqual(Fixture.Scenario(name: scenario.name, input: scenario.input), scenario, scenario.name)
        }
        for save in stored.saves {
            XCTAssertEqual(Fixture.Save(name: save.name, json: save.json), save, save.name)
        }
    }
}

/// The Goals section's rules and sample evaluations.
struct ProgressionGoldenFixture: Codable, Equatable {
    static let schemaName = "tabbi.progression.golden"

    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/progression/progression.json")
    }

    var schema = schemaName
    var version = 1
    var constants: Constants
    var tracks: [Track]
    var mastery: [Mastery]
    var hashes: [Hash]
    var labels: [Label]
    var streaks: [Streak]
    var scenarios: [Scenario]
    var saves: [Save]

    struct Constants: Codable, Equatable {
        var tiers: [String]
        var namedMethods: [String]
        var steadyWeekDays: Int
        var minutesForStudyDay: Double
        var questCount: Int
        var questCore: [String]
        var questExtras: [String]
        var questTargets: [String: Int]
        var saveSchemaVersion: Int
    }

    struct Track: Codable, Equatable {
        var id: String
        var thresholds: [Int]
    }

    struct Mastery: Codable, Equatable {
        var item: String
        var edition: String
        var badge: String
        var goal: Int
    }

    struct Hash: Codable, Equatable {
        var text: String
        var hash: UInt32

        init(text: String) {
            self.text = text
            hash = MonthlyQuests.hash(text)
        }
    }

    struct Label: Codable, Equatable {
        var track: String
        var value: Int
        var goal: Int
        var label: String

        init(track: String, value: Int, goal: Int) {
            self.track = track
            self.value = value
            self.goal = goal
            label = ProgressTrack(rawValue: track)!.progressLabel(value: value, goal: goal)
        }
    }

    // MARK: Records

    struct Record: Codable, Equatable {
        var id: String
        var source: String
        var kind: String
        var unit: String?
        var start: Double
        var end: Double
        var quantity: Double?
        var subject: String?
        var metadata: [String: String]

        var activityRecord: ActivityRecord {
            ActivityRecord(id: UUID(uuidString: id)!, source: ModuleID(rawValue: source), kind: ActivityKind(kind),
                           start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end),
                           quantity: quantity, unit: unit.map(ActivityUnit.init(rawValue:)), subject: subject,
                           metadata: metadata)
        }
    }

    static func calendar(_ timeZone: String, firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    // MARK: Streaks

    struct StreakInput: Codable, Equatable {
        var timeZone: String
        var firstWeekday: Int
        var studyDays: [String]
        var freezePurchases: [Double]
        var today: Double
    }

    struct Streak: Codable, Equatable {
        var name: String
        var input: StreakInput
        var longest: Int

        init(name: String, input: StreakInput) {
            self.name = name
            self.input = input
            let calendar = ProgressionGoldenFixture.calendar(input.timeZone, firstWeekday: input.firstWeekday)
            longest = GentleStreak.longest(studyDays: input.studyDays.compactMap(PlannerDayKey.init(rawValue:)),
                                           freezePurchases: input.freezePurchases.map(Date.init(timeIntervalSince1970:)),
                                           today: Date(timeIntervalSince1970: input.today), calendar: calendar)
        }
    }

    // MARK: Scenarios

    struct ScenarioInput: Codable, Equatable {
        var timeZone: String
        var firstWeekday: Int
        var today: Double
        var freezePurchases: [Double]
        /// A progression save to start from (`ProgressionSave` JSON), or
        /// none for a fresh one.
        var save: String?
        var records: [Record]
    }

    struct QuestRow: Codable, Equatable {
        var track: String
        var target: Int
        var value: Int
        var isDone: Bool
        var label: String
    }

    struct ScenarioOutput: Codable, Equatable {
        /// Each track's count, in its unit.
        var values: [String: Int]
        /// Each track's highest tier reached, absent below Bronze.
        var tiers: [String: String]
        /// What the first refresh reported: badges and months reached.
        var reachedBadges: [String]
        var completedMonths: [String]
        /// This month's quests at `today`.
        var quests: [QuestRow]
        /// Mastery outfits a closet that owned none gets.
        var unlocked: [String]
        /// Every badge's progress label toward its goal.
        var progress: [String: String]
    }

    struct Scenario: Codable, Equatable {
        var name: String
        var input: ScenarioInput
        var output: ScenarioOutput

        init(name: String, input: ScenarioInput) {
            self.name = name
            self.input = input
            let calendar = ProgressionGoldenFixture.calendar(input.timeZone, firstWeekday: input.firstWeekday)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let save = input.save.flatMap {
                try? ProgressionSave.schema.decode(ProgressionSave.self, from: Data($0.utf8), using: decoder)
            } ?? ProgressionSave()
            var progression = PetProgression(save: save)
            for record in input.records { progression.add(record.activityRecord, calendar: calendar) }
            let today = Date(timeIntervalSince1970: input.today)
            let change = progression.refresh(at: today, freezePurchases: input.freezePurchases.map(Date.init(timeIntervalSince1970:)),
                                             calendar: calendar)
            var closet = PetCloset(save: PetSave(profile: PetProfile(name: "Mochi", breed: .tuxedo)))
            let unlocked = closet.unlockMastery(progression)
            output = ScenarioOutput(
                values: Dictionary(uniqueKeysWithValues: ProgressTrack.allCases.map { ($0.rawValue, progression.value(of: $0)) }),
                tiers: Dictionary(uniqueKeysWithValues: ProgressTrack.allCases.compactMap { track in
                    progression.tier(of: track).map { (track.rawValue, ProgressionGoldenFixture.tierName($0)) }
                }),
                reachedBadges: change.badges.sorted().map(\.id),
                completedMonths: progression.save.completedMonths.sorted().map(\.rawValue),
                quests: progression.quests(at: today, calendar: calendar).map {
                    QuestRow(track: $0.quest.track.rawValue, target: $0.quest.target, value: $0.value, isDone: $0.isDone,
                             label: $0.label)
                },
                unlocked: unlocked.map(\.id),
                progress: Dictionary(uniqueKeysWithValues: ProgressBadge.allCases.map { ($0.id, progression.progress(of: $0).label) })
            )
        }
    }

    static func tierName(_ tier: ProgressTier) -> String {
        switch tier {
        case .bronze: "bronze"
        case .silver: "silver"
        case .gold: "gold"
        case .starlight: "starlight"
        }
    }

    // MARK: Saves

    struct SaveOutput: Codable, Equatable {
        var best: [String: Int]
        var reached: [String: Double]
        var completedMonths: [String]
        var seen: [String]
        /// The save written back (sorted keys, ISO 8601 dates, pretty printed).
        var encoded: String
    }

    struct Save: Codable, Equatable {
        var name: String
        var json: String
        var output: SaveOutput?

        init(name: String, json: String) {
            self.name = name
            self.json = json
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let save = try? ProgressionSave.schema.decode(ProgressionSave.self, from: Data(json.utf8), using: decoder),
                  let encoded = try? save.encoded() else {
                output = nil
                return
            }
            output = SaveOutput(
                best: Dictionary(uniqueKeysWithValues: save.best.map { ($0.key.rawValue, $0.value) }),
                reached: Dictionary(uniqueKeysWithValues: save.reached.map { ($0.key.id, $0.value.timeIntervalSince1970) }),
                completedMonths: save.completedMonths.map(\.rawValue).sorted(),
                seen: save.seen.map(\.id).sorted(),
                encoded: String(decoding: encoded, as: UTF8.self)
            )
        }
    }

    // MARK: The fixture

    static func current() -> ProgressionGoldenFixture {
        ProgressionGoldenFixture(
            constants: Constants(
                tiers: ProgressTier.allCases.map(tierName),
                namedMethods: ProgressTally.namedMethods.map(\.rawValue),
                steadyWeekDays: ProgressTrack.steadyWeekDays,
                minutesForStudyDay: PetMilestoneProgress.minutesForStudyDay,
                questCount: MonthlyQuests.count,
                questCore: MonthlyQuests.core.map(\.rawValue),
                questExtras: MonthlyQuests.extras.map(\.rawValue),
                questTargets: Dictionary(uniqueKeysWithValues: MonthlyQuests.targets.map { ($0.key.rawValue, $0.value) }),
                saveSchemaVersion: ProgressionSave.schema.current
            ),
            tracks: ProgressTrack.allCases.map { Track(id: $0.rawValue, thresholds: $0.thresholds) },
            mastery: PetLimitedEdition.mastery.map {
                Mastery(item: $0.item.id, edition: $0.rawValue, badge: $0.masteryBadge!.id, goal: $0.masteryBadge!.goal)
            },
            hashes: ["", "a", "foobar", "2026-11|focusHours", "2026-11|cards", "2027-02|water", "2026-12|studyDays"]
                .map(Hash.init(text:)),
            labels: [
                ("focusHours", 0, 600), ("focusHours", 659, 3000), ("focusHours", 40_000, 30_000), ("cards", 4210, 10_000),
                ("cards", 12_999, 50_000), ("studyDays", -2, 30), ("methods", 3, 4), ("water", 1000, 1000),
            ].map { Label(track: $0.0, value: $0.1, goal: $0.2) },
            streaks: streakCases(),
            scenarios: scenarioCases(),
            saves: saveCases()
        )
    }

    // MARK: Sample inputs

    private static func record(_ index: Int, kind: String, source: String, end: Double, minutes: Double? = nil,
                               unit: String? = nil, quantity: Double? = nil, subject: String? = nil,
                               metadata: [String: String] = [:]) -> Record {
        let id = String(format: "00000000-0000-4000-8000-%012d", index)
        let start = minutes.map { end - $0 * 60 } ?? end
        return Record(id: id, source: source, kind: kind, unit: unit ?? (minutes == nil ? nil : "min"), start: start,
                      end: end, quantity: quantity ?? minutes, subject: subject, metadata: metadata)
    }

    private static func streakCases() -> [Streak] {
        // 2026-11-01 is a Sunday.
        func days(_ list: [Int]) -> [String] { list.map { String(format: "2026-11-%02d", $0) } }
        let noonNov15UTC = 1_794_744_000.0 // 2026-11-15 12:00 UTC
        return [
            Streak(name: "a free freeze a week", input: StreakInput(
                timeZone: "UTC", firstWeekday: 1, studyDays: days(Array(1...14).filter { $0 != 4 && $0 != 11 }),
                freezePurchases: [], today: noonNov15UTC)),
            Streak(name: "two misses in a week end the run", input: StreakInput(
                timeZone: "UTC", firstWeekday: 1, studyDays: days([1, 2, 3, 6, 7, 8, 9, 10]), freezePurchases: [],
                today: noonNov15UTC)),
            Streak(name: "a bought freeze covers the second miss", input: StreakInput(
                timeZone: "UTC", firstWeekday: 1, studyDays: days([1, 2, 3, 6, 7, 8, 9, 10]),
                freezePurchases: [1_793_620_800], today: noonNov15UTC)),
            Streak(name: "a Monday week moves the free freeze", input: StreakInput(
                timeZone: "UTC", firstWeekday: 2, studyDays: days([1, 2, 3, 4, 6, 7, 9, 10, 11]), freezePurchases: [],
                today: noonNov15UTC)),
            Streak(name: "today counts once studied", input: StreakInput(
                timeZone: "Asia/Tokyo", firstWeekday: 1, studyDays: days([13, 14, 15]), freezePurchases: [],
                today: noonNov15UTC)),
            Streak(name: "no study", input: StreakInput(timeZone: "UTC", firstWeekday: 1, studyDays: [], freezePurchases: [],
                                                        today: noonNov15UTC)),
        ]
    }

    private static func scenarioCases() -> [Scenario] {
        let day = 86_400.0
        // 2026-11-02 00:00 in Tokyo is 2026-11-01 15:00 UTC.
        let tokyoNov2 = 1_793_458_800.0
        var index = 0
        func next() -> Int { index += 1; return index }

        // A heavy October in Tokyo: three hours of Pomodoro a day, Anki,
        // tasks, break moves and water on every day.
        var heavy: [Record] = []
        let tokyoOct1 = tokyoNov2 - 32 * day
        for offset in 0..<31 {
            let base = tokyoOct1 + Double(offset) * day + 9 * 3600
            for block in 0..<7 {
                heavy.append(record(next(), kind: "focus.completed", source: "study", end: base + Double(block) * 1800,
                                    minutes: 25, metadata: ["outcome": "completed",
                                                            "method": block == 6 ? "fiftyTwoSeventeen" : "pomodoro"]))
            }
            heavy.append(record(next(), kind: "focus.completed", source: "focus", end: base + 4 * 3600, minutes: 5,
                                metadata: ["outcome": "skipped", "method": "pomodoro"]))
            heavy.append(record(next(), kind: "cards.reviewed", source: "anki", end: base + 5 * 3600, unit: "cards",
                                quantity: 400))
            heavy.append(record(next(), kind: "task.completed", source: "planner", end: base + 6 * 3600, quantity: 1,
                                subject: "task-\(offset)"))
            heavy.append(record(next(), kind: "task.completed", source: "planner", end: base + 6 * 3600 + 60, quantity: 1,
                                subject: "task-\(offset)"))
            heavy.append(record(next(), kind: "break.move", source: "closet", end: base + 7 * 3600, subject: "stretch"))
            heavy.append(record(next(), kind: "water.logged", source: "closet", end: base + 7 * 3600, unit: "glass",
                                quantity: 1))
        }
        // November so far: two days in, a bit of everything.
        for offset in 0..<2 {
            let base = tokyoNov2 - day + Double(offset) * day + 10 * 3600
            heavy.append(record(next(), kind: "focus.completed", source: "study", end: base, minutes: 50,
                                metadata: ["outcome": "completed", "method": "flowtime"]))
            heavy.append(record(next(), kind: "cards.reviewed", source: "anki", end: base + 60, unit: "cards", quantity: 120))
        }

        // Party: finished with friends, alone, and cut short; methods from
        // several modules, a custom timer and the plain countdown.
        var party: [Record] = []
        let utcNov10 = 1_794_268_800.0 // 2026-11-10 00:00 UTC
        let partyRows: [(String, [String: String])] = [
            ("party", ["outcome": "completed", "friends": "2", "method": "pomodoro"]),
            ("party", ["outcome": "completed", "friends": "0", "method": "pomodoro"]),
            ("party", ["outcome": "skipped", "friends": "3", "method": "pomodoro"]),
            ("study", ["outcome": "completed", "method": "ultradian"]),
            ("study", ["outcome": "stopped", "method": "flowtime"]),
            ("study", ["outcome": "completed", "method": "questionBlock"]),
            ("study", ["outcome": "completed", "method": "custom"]),
            ("study", ["outcome": "completed", "method": "timer"]),
            ("study", ["outcome": "abandoned", "method": "ankiSprint"]),
        ]
        for (offset, row) in partyRows.enumerated() {
            party.append(record(next(), kind: "focus.completed", source: row.0, end: utcNov10 + Double(offset) * 3600,
                                minutes: 25, metadata: row.1))
        }
        party.append(party[0])

        // Records around a month boundary: they count toward the day (and
        // month) they end in the user's time zone.
        var boundary: [Record] = []
        let utcNov1 = 1_793_491_200.0 // 2026-11-01 00:00 UTC
        for minutesBefore in [30.0, -30.0] {
            boundary.append(record(next(), kind: "focus.completed", source: "focus", end: utcNov1 - minutesBefore * 60,
                                   minutes: 20, metadata: ["outcome": "completed"]))
        }

        // A save from before the log was cleared.
        let save = #"{"best":{"cards":12000,"sessions":180},"completedMonths":["2026-08","2026-09"],"reached":{"cards.3":"2026-09-30T12:00:00Z","sessions.2":"2026-09-10T08:00:00Z"},"schemaVersion":1,"seen":["sessions.2"]}"#

        return [
            Scenario(name: "a new pet", input: ScenarioInput(timeZone: "UTC", firstWeekday: 1, today: utcNov10,
                                                             freezePurchases: [], save: nil, records: [])),
            Scenario(name: "a heavy month in Tokyo", input: ScenarioInput(
                timeZone: "Asia/Tokyo", firstWeekday: 2, today: tokyoNov2 + day + 12 * 3600, freezePurchases: [],
                save: nil, records: heavy)),
            Scenario(name: "party and methods", input: ScenarioInput(
                timeZone: "UTC", firstWeekday: 1, today: utcNov10 + day, freezePurchases: [], save: nil, records: party)),
            Scenario(name: "a month boundary in New York", input: ScenarioInput(
                timeZone: "America/New_York", firstWeekday: 1, today: utcNov1 + day, freezePurchases: [], save: nil,
                records: boundary)),
            Scenario(name: "a month boundary in London", input: ScenarioInput(
                timeZone: "Europe/London", firstWeekday: 2, today: utcNov1 + day, freezePurchases: [], save: nil,
                records: boundary)),
            Scenario(name: "progress kept after the log was cleared", input: ScenarioInput(
                timeZone: "UTC", firstWeekday: 1, today: utcNov10, freezePurchases: [], save: save,
                records: Array(party.prefix(2)))),
        ]
    }

    private static func saveCases() -> [Save] {
        [
            Save(name: "current", json: #"{"best":{"focusHours":3200},"completedMonths":["2026-10"],"reached":{"focusHours.1":"2026-10-03T09:30:00Z","focusHours.2":"2026-10-28T20:00:00Z"},"schemaVersion":1,"seen":["focusHours.1"]}"#),
            Save(name: "no version", json: #"{"best":{"water":25},"reached":{"water.1":"2026-10-03T09:30:00Z"}}"#),
            Save(name: "a newer build", json: #"{"best":{"focusHours":90,"naps":4},"completedMonths":["2026-10","2026-13"],"reached":{"focusHours.1":"2026-10-03T09:30:00Z","naps.1":"2026-10-03T09:30:00Z"},"rooms":{"desk":true},"schemaVersion":4,"seen":["naps.1","focusHours.1"]}"#),
            Save(name: "seen without reached", json: #"{"best":{},"reached":{},"seen":["cards.1"]}"#),
            Save(name: "broken fields", json: #"{"best":"lots","reached":[1],"completedMonths":{"a":1}}"#),
            Save(name: "not an object", json: #"[1,2,3]"#),
        ]
    }
}
