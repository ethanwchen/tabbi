import Foundation
import TabbiKitCore
import XCTest

/// Pins the break buddy's pure logic to the golden fixture
/// `shared/fixtures/break-buddy/break-buddy.json`: the moves, the planner's
/// rules (each break and preferences in, the moment and the moved-on
/// history out, including runs of breaks in a row) and the water tally's
/// counts over sample activity records.
///
/// A port replays the inputs and must plan the same moves for the same
/// breaks. Run with `TABBI_RECORD_FIXTURES=1` to rewrite it after an
/// intended change.
final class BreakBuddyGoldenTests: XCTestCase {
    private var isRecording: Bool { ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1" }

    func testBreakBuddyMatchesGoldenFixture() throws {
        let url = BreakBuddyGoldenFixture.url
        let current = BreakBuddyGoldenFixture.current()
        if isRecording {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PetGoldenFixtures.encode(current).write(to: url)
            return
        }
        let stored = try JSONDecoder().decode(BreakBuddyGoldenFixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(stored.constants, current.constants, "Break buddy constants changed")
        XCTAssertEqual(stored.plans.map(\.name), current.plans.map(\.name))
        for (old, new) in zip(stored.plans, current.plans) { XCTAssertEqual(old, new, "Plan \(old.name)") }
        XCTAssertEqual(stored.runs.map(\.name), current.runs.map(\.name))
        for (old, new) in zip(stored.runs, current.runs) { XCTAssertEqual(old, new, "Run \(old.name)") }
        XCTAssertEqual(stored.tallies.map(\.name), current.tallies.map(\.name))
        for (old, new) in zip(stored.tallies, current.tallies) { XCTAssertEqual(old, new, "Tally \(old.name)") }
        XCTAssertEqual(stored, current, "The break buddy no longer matches \(url.lastPathComponent)")
    }

    /// The fixture's own inputs, replayed: a port that reads only the inputs
    /// gets the recorded outputs.
    func testStoredInputsReplayToStoredOutputs() throws {
        try XCTSkipIf(isRecording, "Recording")
        let stored = try JSONDecoder().decode(BreakBuddyGoldenFixture.self,
                                              from: Data(contentsOf: BreakBuddyGoldenFixture.url))
        for plan in stored.plans {
            XCTAssertEqual(BreakBuddyGoldenFixture.Plan(name: plan.name, input: plan.input).output, plan.output, plan.name)
        }
        for run in stored.runs {
            XCTAssertEqual(BreakBuddyGoldenFixture.Run(name: run.name, input: run.input).moves, run.moves, run.name)
        }
        for tally in stored.tallies {
            let replayed = BreakBuddyGoldenFixture.Tally(name: tally.name, timeZone: tally.timeZone, day: tally.day,
                                                          records: tally.records)
            XCTAssertEqual(replayed, tally, tally.name)
        }
    }
}

/// The break buddy's moves, plans and water tallies.
struct BreakBuddyGoldenFixture: Codable, Equatable {
    static let schemaName = "tabbi.break-buddy.golden"

    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/break-buddy/break-buddy.json")
    }

    var schema = schemaName
    var version = 1
    var constants: Constants
    var plans: [Plan]
    var runs: [Run]
    var tallies: [Tally]

    struct Move: Codable, Equatable {
        var id: String
        var animation: String
        var length: Double
        var symbol: String
    }

    struct Constants: Codable, Equatable {
        var moves: [Move]
        var minimumBreak: Double
        var longBreak: Double
        var sipEvery: Int
        var rotation: [String]
        var preferencesKey: String
        var preferencesVersion: Int
        var waterKind: String
        var moveKind: String
        var glassUnit: String
        var source: String
    }

    /// The preferences as their saved JSON fields.
    struct Preferences: Codable, Equatable {
        var isOn: Bool
        var disabledMoves: [String]
        var tracksWater: Bool
        var lastMove: String?
        var breaksSinceSip: Int
        var lastBreakKey: String?

        init(_ preferences: BreakBuddyPreferences) {
            isOn = preferences.isOn
            disabledMoves = preferences.disabledMoves.map(\.rawValue).sorted()
            tracksWater = preferences.tracksWater
            lastMove = preferences.lastMove?.rawValue
            breaksSinceSip = preferences.breaksSinceSip
            lastBreakKey = preferences.lastBreakKey
        }

        var value: BreakBuddyPreferences {
            BreakBuddyPreferences(isOn: isOn, disabledMoves: Set(disabledMoves.compactMap(BreakMove.init(rawValue:))),
                                  tracksWater: tracksWater, lastMove: lastMove.flatMap(BreakMove.init(rawValue:)),
                                  breaksSinceSip: breaksSinceSip, lastBreakKey: lastBreakKey)
        }
    }

    /// Times are seconds since 1970.
    struct PlanInput: Codable, Equatable {
        var source: String
        var breakStartedAt: Double
        var breakLength: Double
        var now: Double
        var preferences: Preferences
    }

    struct Moment: Codable, Equatable {
        var move: String
        var source: String
        var breakStartedAt: Double
        var startedAt: Double
        var endsAt: Double
    }

    struct PlanOutput: Codable, Equatable {
        var breakKey: String
        /// Nil when the break gets no moment.
        var moment: Moment?
        /// The preferences to save; the input's when there is no moment.
        var preferences: Preferences
    }

    struct Plan: Codable, Equatable {
        var name: String
        var input: PlanInput
        var output: PlanOutput

        init(name: String, input: PlanInput) {
            self.name = name
            self.input = input
            let rest = BreakBuddyPlanner.Break(source: ModuleID(rawValue: input.source),
                                               startedAt: Date(timeIntervalSince1970: input.breakStartedAt),
                                               length: input.breakLength)
            let plan = BreakBuddyPlanner.plan(for: rest, preferences: input.preferences.value,
                                              at: Date(timeIntervalSince1970: input.now))
            output = PlanOutput(
                breakKey: BreakBuddyPlanner.breakKey(rest),
                moment: plan.map { Moment(move: $0.moment.move.rawValue, source: $0.moment.source.rawValue,
                                          breakStartedAt: $0.moment.breakStartedAt.timeIntervalSince1970,
                                          startedAt: $0.moment.startedAt.timeIntervalSince1970,
                                          endsAt: $0.moment.endsAt.timeIntervalSince1970) },
                preferences: plan.map { Preferences($0.preferences) } ?? input.preferences)
        }
    }

    struct RunInput: Codable, Equatable {
        var preferences: Preferences
        /// Each break's length in seconds; break i starts at `firstStart + i * 3600` and is planned as it starts.
        var breakLengths: [Double]
        var firstStart: Double
        var source: String
    }

    /// Breaks in a row, each planned with the history the last one left.
    struct Run: Codable, Equatable {
        var name: String
        var input: RunInput
        /// The move each break got, or nil.
        var moves: [String?]

        init(name: String, input: RunInput) {
            self.name = name
            self.input = input
            var preferences = input.preferences.value
            moves = input.breakLengths.enumerated().map { index, length in
                let start = Date(timeIntervalSince1970: input.firstStart + Double(index) * 3600)
                let rest = BreakBuddyPlanner.Break(source: ModuleID(rawValue: input.source), startedAt: start, length: length)
                guard let plan = BreakBuddyPlanner.plan(for: rest, preferences: preferences, at: start) else { return nil }
                preferences = plan.preferences
                return plan.moment.move.rawValue
            }
        }
    }

    struct Record: Codable, Equatable {
        var source: String
        var kind: String
        var end: Double
        var quantity: Double?
        var subject: String?
    }

    struct Tally: Codable, Equatable {
        var name: String
        var timeZone: String
        /// The day counted, `yyyy-MM-dd`.
        var day: String
        var records: [Record]
        var glasses: Int
        var moves: [String]

        init(name: String, timeZone: String, day: String, records: [Record]) {
            self.name = name
            self.timeZone = timeZone
            self.day = day
            self.records = records
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: timeZone) ?? .gmt
            let activity = records.map {
                ActivityRecord(source: ModuleID(rawValue: $0.source), kind: ActivityKind($0.kind),
                               start: Date(timeIntervalSince1970: $0.end), quantity: $0.quantity,
                               unit: $0.kind == WaterTally.waterKind.rawValue ? WaterTally.glass : nil, subject: $0.subject)
            }
            let key = PlannerDayKey(rawValue: day) ?? PlannerDayKey(date: .distantPast, calendar: calendar)
            glasses = WaterTally.glasses(in: activity, on: key, calendar: calendar)
            moves = WaterTally.moves(in: activity, on: key, calendar: calendar).map(\.rawValue)
        }
    }

    static func current() -> BreakBuddyGoldenFixture {
        let start: Double = 1_791_000_000 // 2026-10-03, a Saturday morning in Europe
        let fresh = Preferences(BreakBuddyPreferences())
        func input(_ length: Double, after offset: Double = 0, source: String = "focus",
                   preferences: Preferences = fresh) -> PlanInput {
            PlanInput(source: source, breakStartedAt: start, breakLength: length, now: start + offset,
                      preferences: preferences)
        }
        var sipDue = BreakBuddyPreferences(lastMove: .eyeRest, breaksSinceSip: 2)
        let planned = BreakBuddyPlanner.breakKey(.init(source: "focus", startedAt: Date(timeIntervalSince1970: start),
                                                       length: 300))
        sipDue.lastBreakKey = "focus@1"
        let plans = [
            Plan(name: "first-short-break", input: input(300)),
            Plan(name: "long-break-stands-up", input: input(15 * 60)),
            Plan(name: "half-of-a-one-minute-break", input: input(60)),
            Plan(name: "forty-seconds-is-the-least", input: input(40)),
            Plan(name: "under-forty-seconds-gets-none", input: input(39)),
            Plan(name: "too-late-in-the-break", input: input(300, after: 265)),
            Plan(name: "planned-a-few-seconds-in", input: input(300, after: 4)),
            Plan(name: "sip-comes-round", input: input(300, preferences: Preferences(sipDue))),
            Plan(name: "rotation-after-breathe", input: input(300, preferences: Preferences(
                BreakBuddyPreferences(lastMove: .breathe, breaksSinceSip: 1)))),
            Plan(name: "off", input: input(300, preferences: Preferences(BreakBuddyPreferences(isOn: false)))),
            Plan(name: "every-move-off", input: input(300, preferences: Preferences(
                BreakBuddyPreferences(disabledMoves: Set(BreakMove.allCases))))),
            Plan(name: "already-planned", input: input(300, preferences: Preferences(
                BreakBuddyPreferences(lastBreakKey: planned)))),
            Plan(name: "long-break-standing-up-off", input: input(15 * 60, preferences: Preferences(
                BreakBuddyPreferences(disabledMoves: [.standUp])))),
            Plan(name: "only-sip-left", input: input(300, source: "study", preferences: Preferences(
                BreakBuddyPreferences(disabledMoves: [.stretch, .eyeRest, .breathe, .standUp])))),
        ]
        let pomodoro: [Double] = [300, 300, 300, 1200, 300, 300, 300, 1200, 300]
        let runs = [
            Run(name: "pomodoro-day", input: RunInput(preferences: fresh, breakLengths: pomodoro, firstStart: start,
                                                      source: "focus")),
            Run(name: "no-sip-no-eyes", input: RunInput(
                preferences: Preferences(BreakBuddyPreferences(disabledMoves: [.sip, .eyeRest])),
                breakLengths: Array(repeating: 300, count: 6), firstStart: start, source: "study")),
            Run(name: "short-and-tiny-breaks", input: RunInput(preferences: fresh,
                                                               breakLengths: [30, 300, 45, 20, 300, 600],
                                                               firstStart: start, source: "study")),
        ]
        // 2026-10-03 in Berlin starts at 2026-10-02T22:00:00Z.
        let midnight: Double = 1_790_978_400
        let records = [
            Record(source: "closet", kind: "water.logged", end: midnight - 60, quantity: 1),
            Record(source: "closet", kind: "water.logged", end: midnight, quantity: 1),
            Record(source: "closet", kind: "water.logged", end: midnight + 3600 * 9, quantity: 1),
            Record(source: "closet", kind: "water.logged", end: midnight + 3600 * 15, quantity: 2),
            Record(source: "study", kind: "water.logged", end: midnight + 3600 * 10, quantity: 1),
            Record(source: "closet", kind: "break.move", end: midnight + 3600 * 9, subject: "stretch"),
            Record(source: "closet", kind: "break.move", end: midnight + 3600 * 11, subject: "breathe"),
            Record(source: "closet", kind: "break.move", end: midnight + 3600 * 12, subject: "cartwheel"),
            Record(source: "focus", kind: "focus.completed", end: midnight + 3600 * 9, quantity: 25),
        ]
        let tallies = [
            Tally(name: "berlin-day", timeZone: "Europe/Berlin", day: "2026-10-03", records: records),
            Tally(name: "berlin-day-before", timeZone: "Europe/Berlin", day: "2026-10-02", records: records),
            Tally(name: "utc-day", timeZone: "UTC", day: "2026-10-03", records: records),
        ]
        return BreakBuddyGoldenFixture(
            constants: Constants(
                moves: BreakMove.allCases.map { Move(id: $0.rawValue, animation: $0.animation.rawValue, length: $0.length,
                                                     symbol: $0.symbol) },
                minimumBreak: BreakBuddyPlanner.minimumBreak, longBreak: BreakBuddyPlanner.longBreak,
                sipEvery: BreakBuddyPlanner.sipEvery, rotation: BreakBuddyPlanner.rotation.map(\.rawValue),
                preferencesKey: BreakBuddyPreferencesStorage.key,
                preferencesVersion: BreakBuddyPreferencesStorage.schema.current,
                waterKind: WaterTally.waterKind.rawValue, moveKind: WaterTally.moveKind.rawValue,
                glassUnit: WaterTally.glass.rawValue, source: WaterTally.source.rawValue),
            plans: plans, runs: runs, tallies: tallies)
    }
}
