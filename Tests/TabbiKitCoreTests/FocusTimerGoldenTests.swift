import Foundation
import TabbiKitCore
import XCTest

/// Pins the Pomodoro state machine (`FocusTimer`), what it shows, what it
/// shares as the focus clock and what it logs, to the golden fixture
/// `shared/fixtures/focus-timer/focus-timer.json`.
///
/// The Windows port replays the same steps through its own timer and
/// compares with the recorded states, so both apps run the same Pomodoro.
/// Run with `TABBI_RECORD_FIXTURES=1` to rewrite it after an intended change.
final class FocusTimerGoldenTests: XCTestCase {
    func testFocusTimerMatchesGoldenFixture() throws {
        let url = FocusTimerGoldenFixture.url
        let current = FocusTimerGoldenFixture.current()
        if ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1" {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PetGoldenFixtures.encode(current).write(to: url)
            return
        }
        let stored = try JSONDecoder().decode(FocusTimerGoldenFixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(stored.clocks, current.clocks, "Clock strings changed")
        XCTAssertEqual(stored.sequences.map(\.name), current.sequences.map(\.name))
        for (old, new) in zip(stored.sequences, current.sequences) {
            XCTAssertEqual(old.steps.count, new.steps.count, old.name)
            for (index, (oldStep, newStep)) in zip(old.steps, new.steps).enumerated() {
                XCTAssertEqual(oldStep, newStep, "Sequence \(old.name), step \(index) (\(old.steps[index].input.action))")
            }
        }
        XCTAssertEqual(stored, current, "The focus timer no longer matches \(url.lastPathComponent)")
    }

    /// The fixture's own inputs, replayed: a port that reads only the inputs
    /// from the file gets the recorded outputs.
    func testStoredInputsReplayToStoredOutputs() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1", "Recording")
        let stored = try JSONDecoder().decode(FocusTimerGoldenFixture.self, from: Data(contentsOf: FocusTimerGoldenFixture.url))
        for clock in stored.clocks {
            XCTAssertEqual(FocusTimerFormat.clock(clock.seconds), clock.text, "\(clock.seconds)")
        }
        for sequence in stored.sequences {
            XCTAssertEqual(FocusTimerGoldenFixture.run(sequence.steps.map(\.input)), sequence.steps, sequence.name)
        }
    }
}

/// Countdown strings for sample times, and Pomodoro sequences as a list of
/// steps (start, pause, skip, reset, advance the clock, change the lengths),
/// each with the timer, its readout, its shared focus clock and the phases
/// it finished.
struct FocusTimerGoldenFixture: Codable, Equatable {
    static let schemaName = "tabbi.focus-timer.golden"

    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/focus-timer/focus-timer.json")
    }

    /// The module id the shared clock and activity records carry.
    static let source: ModuleID = "focus"

    struct Clock: Codable, Equatable {
        var seconds: Double
        var text: String
    }

    /// What a step does at `at` (seconds since 1970): `start`, `pause`,
    /// `reset`, `skip`, `advance` (apply every phase end up to `at`), or
    /// `configure` (set `focusDuration` and `restDuration`, in seconds).
    struct Input: Codable, Equatable {
        var action: String
        var at: Double
        var focusDuration: Double?
        var restDuration: Double?

        static func start(_ at: Double) -> Input { Input(action: "start", at: at) }
        static func pause(_ at: Double) -> Input { Input(action: "pause", at: at) }
        static func reset(_ at: Double) -> Input { Input(action: "reset", at: at) }
        static func skip(_ at: Double) -> Input { Input(action: "skip", at: at) }
        static func advance(_ at: Double) -> Input { Input(action: "advance", at: at) }
        static func configure(_ at: Double, focus: Double, rest: Double) -> Input {
            Input(action: "configure", at: at, focusDuration: focus, restDuration: rest)
        }
    }

    /// The timer itself: `run` is `idle`, `running` (with `endsAt`) or
    /// `paused` (with `pausedRemaining`), and the lengths after clamping.
    struct State: Codable, Equatable {
        var phase: String
        var run: String
        var endsAt: Double?
        var pausedRemaining: Double?
        var focusDuration: Double
        var restDuration: Double
        var completedFocusCount: Int
    }

    /// What the focus card shows at the step's `at`.
    struct View: Codable, Equatable {
        var remaining: Double
        var progress: Double
        var clock: String
        var phaseName: String
        var status: String
    }

    /// The timer as the shared focus clock (`ProvidedFocus`), read at `at`.
    /// `clock.kind` is `idle`, `countdown` (with `endsAt`) or `paused` (with
    /// `shown`); `countUp` (with `since`) is Study's and never comes from here.
    struct Provided: Codable, Equatable {
        struct Clock: Codable, Equatable {
            var kind: String
            var endsAt: Double?
            var since: Double?
            var shown: Double?
        }

        var phase: String
        var label: String
        var clock: Clock
        var phaseLength: Double?
        var focusLength: Double?
        var completedFocusCount: Int
        var isRunning: Bool
        var isActive: Bool
        var remaining: Double?
        var elapsed: Double
        var shownTime: Double
    }

    /// A phase that ran out during the step, with its notification copy and
    /// the activity record the app logs for it.
    struct Completion: Codable, Equatable {
        struct Activity: Codable, Equatable {
            var kind: String
            var start: Double
            var end: Double
            var quantity: Double?
            var unit: String?
            var metadata: [String: String]
        }

        var phase: String
        var endedAt: Double
        var title: String
        var body: String
        var activity: Activity
    }

    struct Step: Codable, Equatable {
        var input: Input
        var completions: [Completion]
        var state: State
        var view: View
        var provided: Provided
    }

    struct Sequence: Codable, Equatable {
        var name: String
        var steps: [Step]
    }

    var schema = Self.schemaName
    var version = 1
    var clocks: [Clock]
    var sequences: [Sequence]

    static func current() -> FocusTimerGoldenFixture {
        FocusTimerGoldenFixture(
            clocks: sampleClockSeconds.map { Clock(seconds: $0, text: FocusTimerFormat.clock($0)) },
            sequences: sampleSequences.map { Sequence(name: $0.0, steps: run($0.1)) }
        )
    }

    /// Feeds `inputs` to a fresh 25/5 timer and records it after each one.
    static func run(_ inputs: [Input]) -> [Step] {
        var timer = FocusTimer()
        return inputs.map { input in
            let now = Date(timeIntervalSince1970: input.at)
            var completions: [FocusPhaseCompletion] = []
            switch input.action {
            case "start": timer.start(at: now)
            case "pause": timer.pause(at: now)
            case "reset": timer.reset()
            case "skip": timer.skip(at: now)
            case "advance": completions = timer.advance(to: now)
            case "configure":
                timer.config = FocusTimerConfig(focusDuration: input.focusDuration ?? 0, restDuration: input.restDuration ?? 0)
            default: XCTFail("Unknown action \(input.action)")
            }
            return Step(
                input: input,
                completions: completions.map { completion(of: $0, config: timer.config) },
                state: state(of: timer),
                view: View(
                    remaining: timer.remaining(at: now),
                    progress: timer.progress(at: now),
                    clock: FocusTimerFormat.clock(timer.remaining(at: now)),
                    phaseName: FocusTimerFormat.phaseName(timer.phase),
                    status: FocusTimerFormat.status(timer)
                ),
                provided: provided(timer.provided(by: source), at: now)
            )
        }
    }

    private static func state(of timer: FocusTimer) -> State {
        var state = State(phase: timer.phase.rawValue, run: "idle", focusDuration: timer.config.focusDuration,
                          restDuration: timer.config.restDuration, completedFocusCount: timer.completedFocusCount)
        switch timer.runState {
        case .idle: break
        case .running(let endsAt):
            state.run = "running"
            state.endsAt = endsAt.timeIntervalSince1970
        case .paused(let remaining):
            state.run = "paused"
            state.pausedRemaining = remaining
        }
        return state
    }

    static func provided(_ focus: ProvidedFocus, at now: Date) -> Provided {
        let clock: Provided.Clock = switch focus.clock {
        case .idle: Provided.Clock(kind: "idle")
        case .countdown(let endsAt): Provided.Clock(kind: "countdown", endsAt: endsAt.timeIntervalSince1970)
        case .countUp(let since): Provided.Clock(kind: "countUp", since: since.timeIntervalSince1970)
        case .paused(let shown): Provided.Clock(kind: "paused", shown: shown)
        }
        return Provided(
            phase: focus.phase.rawValue, label: focus.label, clock: clock, phaseLength: focus.phaseLength,
            focusLength: focus.focusLength, completedFocusCount: focus.completedFocusCount,
            isRunning: focus.isRunning, isActive: focus.isActive, remaining: focus.remaining(at: now),
            elapsed: focus.elapsed(at: now), shownTime: focus.shownTime(at: now)
        )
    }

    private static func completion(of completion: FocusPhaseCompletion, config: FocusTimerConfig) -> Completion {
        let message = FocusTimerFormat.completionMessage(completion, config: config)
        let record = completion.activityRecord(config: config, source: source)
        return Completion(
            phase: completion.phase.rawValue,
            endedAt: completion.endedAt.timeIntervalSince1970,
            title: message.title,
            body: message.body,
            activity: Completion.Activity(
                kind: record.kind.rawValue, start: record.start.timeIntervalSince1970,
                end: record.end.timeIntervalSince1970, quantity: record.quantity,
                unit: record.unit?.rawValue, metadata: record.metadata
            )
        )
    }

    // MARK: - Inputs

    /// Countdown readouts, including the round-up edges and an hour-long phase.
    static let sampleClockSeconds: [Double] = [
        -5, 0, 0.001, 0.6, 1, 1.5, 59, 59.4, 60, 60.2, 299.9, 300, 1499.25, 1500, 3000, 3599.5, 3600, 5400,
    ]

    /// A fixed start, in seconds since 1970.
    static let t0: Double = 1_790_000_000

    static let sampleSequences: [(String, [Input])] = [
        ("fresh-timer", [
            .advance(t0),
        ]),
        ("full-cycle-with-pause", [
            .start(t0),
            .advance(t0 + 600),
            .pause(t0 + 600),
            .advance(t0 + 700),
            .start(t0 + 700),
            .advance(t0 + 1599),
            .advance(t0 + 1600),
            .advance(t0 + 1750),
            .advance(t0 + 1900),
            .start(t0 + 2000),
        ]),
        ("asleep-through-focus-and-break", [
            .start(t0),
            .advance(t0 + 5000),
        ]),
        ("asleep-through-focus-only", [
            .start(t0),
            .advance(t0 + 1700),
        ]),
        ("asleep-through-several-cycles", [
            .start(t0),
            .advance(t0 + 1800),
            .start(t0 + 1810),
            .advance(t0 + 100_000),
        ]),
        ("skip-while-running", [
            .start(t0),
            .skip(t0 + 300),
            .skip(t0 + 400),
            .advance(t0 + 1900),
        ]),
        ("skip-while-idle", [
            .skip(t0),
            .start(t0 + 10),
            .advance(t0 + 310),
            .skip(t0 + 320),
            .skip(t0 + 330),
        ]),
        ("skip-while-paused", [
            .start(t0),
            .pause(t0 + 100),
            .skip(t0 + 200),
        ]),
        ("reset-keeps-count", [
            .start(t0),
            .advance(t0 + 1500),
            .reset(t0 + 1600),
            .start(t0 + 1700),
            .reset(t0 + 1800),
        ]),
        ("no-ops", [
            .pause(t0),
            .start(t0),
            .start(t0 + 100),
            .pause(t0 + 200),
            .pause(t0 + 300),
            .advance(t0 + 5000),
            .reset(t0 + 5000),
            .reset(t0 + 5001),
        ]),
        ("pause-after-end-without-advance", [
            .start(t0),
            .pause(t0 + 2000),
            .advance(t0 + 2000),
            .start(t0 + 2100),
            .advance(t0 + 2100),
        ]),
        // Quarter seconds, which a double holds exactly: `Date` counts from
        // 2001, so other fractions round differently than seconds since 1970.
        ("fractional-seconds", [
            .start(t0 + 0.25),
            .pause(t0 + 1499.5),
            .start(t0 + 1500),
            .advance(t0 + 1500.5),
            .advance(t0 + 1500.75),
        ]),
        ("custom-lengths", [
            .configure(t0, focus: 50 * 60, rest: 10 * 60),
            .start(t0),
            .advance(t0 + 3000),
            .advance(t0 + 3600),
        ]),
        ("lengths-clamped-to-one-second", [
            .configure(t0, focus: 0, rest: -5),
            .start(t0),
            .advance(t0 + 1),
            .advance(t0 + 2),
        ]),
        ("lengths-changed-mid-phase", [
            .start(t0),
            .advance(t0 + 600),
            .configure(t0 + 600, focus: 10 * 60, rest: 2 * 60),
            .configure(t0 + 600, focus: 45 * 60, rest: 15 * 60),
            .advance(t0 + 1500),
            .pause(t0 + 1600),
            .configure(t0 + 1600, focus: 25 * 60, rest: 5 * 60),
        ]),
    ]
}
