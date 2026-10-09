import Foundation
import TabbiKitCore
import XCTest

/// Pins the study-timer state machine (`StudySession`), what the Study tab
/// shows for it, what it shares as the focus clock and what it logs, to the
/// golden fixture `shared/fixtures/study-session/study-session.json`.
///
/// The Windows port replays the same steps through its own session and
/// compares with the recorded states, so both apps run every study method
/// the same way. Run with `TABBI_RECORD_FIXTURES=1` to rewrite it after an
/// intended change.
final class StudySessionGoldenTests: XCTestCase {
    func testStudySessionMatchesGoldenFixture() throws {
        let url = StudySessionGoldenFixture.url
        let current = StudySessionGoldenFixture.current()
        if ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1" {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PetGoldenFixtures.encode(current).write(to: url)
            return
        }
        let stored = try JSONDecoder().decode(StudySessionGoldenFixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(stored.labels, current.labels, "Study labels changed")
        XCTAssertEqual(stored.sequences.map(\.name), current.sequences.map(\.name))
        for (old, new) in zip(stored.sequences, current.sequences) {
            XCTAssertEqual(old.method, new.method, old.name)
            XCTAssertEqual(old.steps.count, new.steps.count, old.name)
            for (index, (oldStep, newStep)) in zip(old.steps, new.steps).enumerated() {
                XCTAssertEqual(oldStep, newStep, "Sequence \(old.name), step \(index) (\(old.steps[index].input.action))")
            }
        }
        XCTAssertEqual(stored, current, "The study session no longer matches \(url.lastPathComponent)")
    }

    /// The fixture's own inputs, replayed: a port that reads only the inputs
    /// from the file gets the recorded outputs.
    func testStoredInputsReplayToStoredOutputs() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1", "Recording")
        let stored = try JSONDecoder().decode(StudySessionGoldenFixture.self,
                                              from: Data(contentsOf: StudySessionGoldenFixture.url))
        XCTAssertEqual(StudySessionGoldenFixture.labels(clock: stored.labels.clocks.map(\.seconds),
                                                        studied: stored.labels.studied.map(\.minutes),
                                                        points: stored.labels.points.map(\.points)),
                       stored.labels)
        for sequence in stored.sequences {
            XCTAssertEqual(StudySessionGoldenFixture.run(sequence.method.method, sequence.steps.map(\.input)),
                           sequence.steps, sequence.name)
        }
    }
}

/// Study tab labels for sample values, and study sessions as a list of steps
/// (start, pause, skip, stop a Flowtime stretch, reset, switch or retune the
/// method, feed Anki's card count, advance the clock, collect the log), each
/// with the session, what the tab shows, the shared focus clock and the
/// phases it logged.
struct StudySessionGoldenFixture: Codable, Equatable {
    static let schemaName = "tabbi.study-session.golden"

    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/study-session/study-session.json")
    }

    /// The module id the shared clock and activity records carry.
    static let source: ModuleID = "study"

    /// A `StudyMethod` in neutral form. Lengths are seconds; building the
    /// method clamps them, so a step's `state.method` can differ from its input.
    struct Method: Codable, Equatable {
        /// `duration` (with `seconds`), `openEnded` or `cards` (with `cards`).
        struct Focus: Codable, Equatable {
            var kind: String
            var seconds: Double?
            var cards: Int?
        }

        /// `fixed` (with `seconds`), `proportional` (with `scheme`) or `none`.
        struct Break: Codable, Equatable {
            var kind: String
            var seconds: Double?
            var scheme: String?
        }

        struct LongBreak: Codable, Equatable {
            var duration: Double
            var every: Int
        }

        var kind: String
        var focus: Focus
        var breakRule: Break
        var longBreak: LongBreak?
        var review: Double?
        var questionCount: Int?
        var rhythmLabel: String?

        init(_ method: StudyMethod) {
            kind = method.kind.rawValue
            focus = switch method.focus {
            case .duration(let seconds): Focus(kind: "duration", seconds: seconds)
            case .openEnded: Focus(kind: "openEnded")
            case .cards(let cards): Focus(kind: "cards", cards: cards)
            }
            breakRule = switch method.breakRule {
            case .fixed(let seconds): Break(kind: "fixed", seconds: seconds)
            case .proportional(let scheme): Break(kind: "proportional", scheme: scheme.rawValue)
            case .none: Break(kind: "none")
            }
            longBreak = method.longBreak.map { LongBreak(duration: $0.duration, every: $0.every) }
            review = method.review
            questionCount = method.questionCount
            rhythmLabel = method.rhythmLabel
        }

        /// An input method, built as written (the label is an output only).
        init(_ kind: StudyMethodKind, focus: Focus, breakRule: Break, longBreak: LongBreak? = nil,
             review: Double? = nil, questionCount: Int? = nil) {
            self.kind = kind.rawValue
            self.focus = focus
            self.breakRule = breakRule
            self.longBreak = longBreak
            self.review = review
            self.questionCount = questionCount
        }

        var method: StudyMethod {
            let focusTarget: StudyFocusTarget = switch focus.kind {
            case "duration": .duration(focus.seconds ?? 0)
            case "cards": .cards(focus.cards ?? 0)
            default: .openEnded
            }
            let rule: StudyBreakRule = switch breakRule.kind {
            case "fixed": .fixed(breakRule.seconds ?? 0)
            case "proportional": .proportional(FlowtimeBreakScheme(rawValue: breakRule.scheme ?? "") ?? .tiered)
            default: .none
            }
            return StudyMethod(
                kind: StudyMethodKind(rawValue: kind) ?? .custom, focus: focusTarget, breakRule: rule,
                longBreak: longBreak.map { StudyLongBreak(duration: $0.duration, every: $0.every) },
                review: review, questionCount: questionCount
            )
        }
    }

    /// What a step does at `at` (seconds since 1970): `start`, `pause`,
    /// `skip`, `stopFocus`, `reset`, `switchMethod` or `retune` (with
    /// `method`), `reviewed` (Anki's reviewed-today `count`), `advance`
    /// (apply every phase end up to `at`) or `takeLog`.
    struct Input: Codable, Equatable {
        var action: String
        var at: Double
        var method: Method?
        var count: Int?

        static func start(_ at: Double) -> Input { Input(action: "start", at: at) }
        static func pause(_ at: Double) -> Input { Input(action: "pause", at: at) }
        static func skip(_ at: Double) -> Input { Input(action: "skip", at: at) }
        static func stopFocus(_ at: Double) -> Input { Input(action: "stopFocus", at: at) }
        static func reset(_ at: Double) -> Input { Input(action: "reset", at: at) }
        static func advance(_ at: Double) -> Input { Input(action: "advance", at: at) }
        static func takeLog(_ at: Double) -> Input { Input(action: "takeLog", at: at) }
        static func reviewed(_ at: Double, _ count: Int) -> Input { Input(action: "reviewed", at: at, count: count) }
        static func switchMethod(_ at: Double, _ method: StudyMethod) -> Input {
            Input(action: "switchMethod", at: at, method: Method(method).asInput)
        }
        static func switchMethod(_ at: Double, _ method: Method) -> Input {
            Input(action: "switchMethod", at: at, method: method)
        }
        static func retune(_ at: Double, _ method: StudyMethod) -> Input {
            Input(action: "retune", at: at, method: Method(method).asInput)
        }
    }

    /// One phase that ran (`StudyPhaseRecord`), with the activity record the
    /// app logs for it (nil for a phase under a minute).
    struct Record: Codable, Equatable {
        var method: String
        var phase: String
        var startedAt: Double
        var endedAt: Double
        var activeDuration: Double
        var outcome: String
        var cards: Int?
        var activity: FocusTimerGoldenFixture.Completion.Activity?
    }

    /// The session at the step's `at`. `run` is `idle`, `running` or `paused`.
    struct State: Codable, Equatable {
        var method: Method
        var phase: String
        var run: String
        var phaseDuration: Double?
        var completedFocusCount: Int
        var cardsDone: Int
        var lastFocusWorked: Double
        var elapsed: Double
        var remaining: Double?
        var runningSince: Double?
        var endsAt: Double?
        var progress: Double?
        var suggestsSprintBreak: Bool
        /// Phases logged and not yet collected with `takeLog`.
        var log: [Record]
    }

    /// What the Study tab shows at `at`: the dial's value and caption, the
    /// round label, the primary button, whether the pet dozes and the pet
    /// events this step caused, and what the session asks of focus mode with
    /// deep focus on.
    struct View: Codable, Equatable {
        var value: String
        var caption: String
        var countsDown: Bool
        var round: String?
        var primaryAction: String
        var petDozing: Bool
        var petEvents: [String]
        var deepFocus: String
    }

    struct Step: Codable, Equatable {
        var input: Input
        /// What `stopFocus` or `retune` returned.
        var accepted: Bool?
        /// The phases `advance` or `reviewed` ended during the step.
        var ended: [Record]?
        /// The log `takeLog` handed over.
        var taken: [Record]?
        var state: State
        var view: View
        /// The session as the shared focus clock, nil while idle.
        var provided: FocusTimerGoldenFixture.Provided?
    }

    struct Sequence: Codable, Equatable {
        var name: String
        var method: Method
        var steps: [Step]
    }

    struct Labels: Codable, Equatable {
        struct Clock: Codable, Equatable {
            var seconds: Double
            var text: String
        }

        struct Studied: Codable, Equatable {
            var minutes: Int
            var text: String
        }

        struct Points: Codable, Equatable {
            var points: Int
            var text: String
        }

        var clocks: [Clock]
        var studied: [Studied]
        var points: [Points]
    }

    var schema = Self.schemaName
    var version = 1
    var minimumLoggedDuration = StudyPhaseRecord.minimumLoggedDuration
    var labels: Labels
    var sequences: [Sequence]

    static func current() -> StudySessionGoldenFixture {
        StudySessionGoldenFixture(
            labels: labels(clock: sampleClockSeconds, studied: sampleStudiedMinutes, points: samplePoints),
            sequences: sampleSequences.map { name, method, inputs in
                Sequence(name: name, method: Method(method).asInput, steps: run(method, inputs))
            }
        )
    }

    static func labels(clock: [Double], studied: [Int], points: [Int]) -> Labels {
        Labels(
            clocks: clock.map { Labels.Clock(seconds: $0, text: StudyTimerFormat.clock($0)) },
            studied: studied.map { Labels.Studied(minutes: $0, text: StudyTimerFormat.studied(minutes: $0)) },
            points: points.map { Labels.Points(points: $0, text: StudyTimerFormat.points($0)) }
        )
    }

    /// Feeds `inputs` to a fresh session on `method` and records it after each one.
    static func run(_ method: StudyMethod, _ inputs: [Input]) -> [Step] {
        var session = StudySession(method: method)
        return inputs.map { input in
            let now = Date(timeIntervalSince1970: input.at)
            let before = session
            var accepted: Bool?
            var ended: [StudyPhaseRecord]?
            var taken: [StudyPhaseRecord]?
            switch input.action {
            case "start": session.start(at: now)
            case "pause": session.pause(at: now)
            case "skip": session.skip(at: now)
            case "stopFocus": accepted = session.stopFocus(at: now)
            case "reset": session.reset(at: now)
            case "switchMethod": session.switchMethod(to: input.method?.method ?? method, at: now)
            case "retune": accepted = session.retune(to: input.method?.method ?? method, at: now)
            case "reviewed": ended = session.recordReviewedToday(input.count ?? 0, at: now)
            case "advance": ended = session.advance(to: now)
            case "takeLog": taken = session.takeLog()
            default: XCTFail("Unknown action \(input.action)")
            }
            let readout = StudyTimerFormat.readout(session, at: now)
            return Step(
                input: input,
                accepted: accepted,
                ended: ended.map { $0.map(record) },
                taken: taken.map { $0.map(record) },
                state: state(of: session, at: now),
                view: View(
                    value: readout.value, caption: readout.caption, countsDown: readout.countsDown,
                    round: StudyTimerFormat.roundLabel(session),
                    primaryAction: StudyTimerFormat.primaryAction(session),
                    petDozing: StudyPetCue.isDozing(session),
                    petEvents: StudyPetCue.events(from: before, to: session).map { String(describing: $0) },
                    deepFocus: String(describing: FocusActivity(session, deepFocus: true))
                ),
                provided: session.sharedFocus(by: source, at: now).map { FocusTimerGoldenFixture.provided($0, at: now) }
            )
        }
    }

    private static func state(of session: StudySession, at now: Date) -> State {
        State(
            method: Method(session.method),
            phase: session.phase.rawValue,
            run: session.runState.rawValue,
            phaseDuration: session.phaseDuration,
            completedFocusCount: session.completedFocusCount,
            cardsDone: session.cardsDone,
            lastFocusWorked: session.lastFocusWorked,
            elapsed: session.elapsed(at: now),
            remaining: session.remaining(at: now),
            runningSince: session.runningSince?.timeIntervalSince1970,
            endsAt: session.endsAt?.timeIntervalSince1970,
            progress: session.progress(at: now),
            suggestsSprintBreak: session.suggestsSprintBreak(at: now),
            log: session.log.map(record)
        )
    }

    private static func record(_ record: StudyPhaseRecord) -> Record {
        Record(
            method: record.method.rawValue,
            phase: record.phase.rawValue,
            startedAt: record.startedAt.timeIntervalSince1970,
            endedAt: record.endedAt.timeIntervalSince1970,
            activeDuration: record.activeDuration,
            outcome: record.outcome.rawValue,
            cards: record.cards,
            activity: record.activityRecord(source: source).map {
                FocusTimerGoldenFixture.Completion.Activity(
                    kind: $0.kind.rawValue, start: $0.start.timeIntervalSince1970, end: $0.end.timeIntervalSince1970,
                    quantity: $0.quantity, unit: $0.unit?.rawValue, metadata: $0.metadata
                )
            }
        )
    }

    // MARK: - Inputs

    /// Dial readouts, including the round-up edges and the hour field.
    static let sampleClockSeconds: [Double] = [
        -5, 0, 0.25, 1, 59.5, 60, 245, 3120, 3599.25, 3600, 3760, 14_400,
    ]

    static let sampleStudiedMinutes: [Int] = [-3, 0, 1, 45, 59, 60, 65, 120, 125, 600]

    /// Below 1,000, so the locale's grouping separator never shows.
    static let samplePoints: [Int] = [-4, 0, 1, 2, 79, 999]

    /// A fixed start, in seconds since 1970.
    static let t0: Double = 1_790_000_000

    private static let minute: Double = 60

    /// A method exactly as written, so the session's clamping shows.
    static let unclampedCustom = Method(
        .custom, focus: .init(kind: "duration", seconds: 0), breakRule: .init(kind: "fixed", seconds: 99_999),
        longBreak: .init(duration: -10, every: 1)
    )

    static let sampleSequences: [(String, StudyMethod, [Input])] = [
        ("fresh-session", .pomodoro, [
            .advance(t0),
        ]),
        // Four Pomodoros, each break running on its own and ending idle, then the long break.
        ("pomodoro-full-set", .pomodoro, [
            .start(t0),
            .advance(t0 + 1499),
            .advance(t0 + 1500),
            .advance(t0 + 1800),
            .start(t0 + 1810),
            .advance(t0 + 3310),
            .advance(t0 + 3610),
            .start(t0 + 3700),
            .advance(t0 + 5200),
            .advance(t0 + 5500),
            .start(t0 + 5600),
            .advance(t0 + 7100),
            .advance(t0 + 8000),
            .takeLog(t0 + 8000),
            .start(t0 + 8100),
        ]),
        ("pause-and-resume", .pomodoro, [
            .start(t0),
            .advance(t0 + 600),
            .pause(t0 + 600),
            .advance(t0 + 900),
            .start(t0 + 900),
            .advance(t0 + 1799),
            .advance(t0 + 1800),
            .pause(t0 + 1900),
            .start(t0 + 2000),
            .advance(t0 + 2200),
        ]),
        ("asleep-through-focus-and-break", .pomodoro, [
            .start(t0),
            .advance(t0 + 100_000),
        ]),
        ("skips", .pomodoro, [
            .skip(t0),
            .start(t0 + 10),
            .skip(t0 + 40),
            .skip(t0 + 100),
            .pause(t0 + 400),
            .skip(t0 + 500),
            .start(t0 + 600),
            .advance(t0 + 2100),
        ]),
        // Three Pomodoros finish; skipping the fourth earns a short break, not the long one.
        ("skipped-focus-never-earns-long-break", .pomodoro, [
            .start(t0),
            .advance(t0 + 1800),
            .start(t0 + 1800),
            .advance(t0 + 3600),
            .start(t0 + 3600),
            .advance(t0 + 5400),
            .start(t0 + 5400),
            .skip(t0 + 6000),
            .advance(t0 + 6300),
            .start(t0 + 6300),
            .advance(t0 + 7800),
        ]),
        ("flowtime-tiered", .flowtime(scheme: .tiered), [
            .stopFocus(t0),
            .start(t0),
            .advance(t0 + 20 * minute),
            .stopFocus(t0 + 30 * minute),
            .stopFocus(t0 + 31 * minute),
            .advance(t0 + 38 * minute),
            .start(t0 + 40 * minute),
            .pause(t0 + 50 * minute),
            .stopFocus(t0 + 55 * minute),
            .advance(t0 + 60 * minute),
            .start(t0 + 70 * minute),
            .stopFocus(t0 + 135 * minute),
            .skip(t0 + 136 * minute),
        ]),
        ("flowtime-fifth", .flowtime(scheme: .fifth), [
            .start(t0),
            .stopFocus(t0 + 50 * minute),
            .advance(t0 + 60 * minute),
            .start(t0 + 60 * minute),
            .stopFocus(t0 + 62 * minute),
            .advance(t0 + 63 * minute),
            .start(t0 + 63 * minute),
            .stopFocus(t0 + 63 * minute + 30),
            .takeLog(t0 + 64 * minute),
        ]),
        // The first count after a start only sets the baseline; paused and break cards don't count.
        ("anki-sprint", .ankiSprint(cards: 20), [
            .reviewed(t0, 90),
            .start(t0),
            .reviewed(t0, 100),
            .reviewed(t0 + 120, 110),
            .reviewed(t0 + 130, 105),
            .pause(t0 + 200),
            .reviewed(t0 + 250, 115),
            .start(t0 + 300),
            .reviewed(t0 + 300, 118),
            .reviewed(t0 + 400, 126),
            .reviewed(t0 + 500, 130),
            .reviewed(t0 + 600, 140),
            .advance(t0 + 900),
            .reviewed(t0 + 950, 150),
            .start(t0 + 1000),
            .reviewed(t0 + 1000, 0),
            .reviewed(t0 + 1100, 4),
        ]),
        ("anki-sprint-suggests-break", .ankiSprint(cards: 300), [
            .start(t0),
            .reviewed(t0, 0),
            .reviewed(t0 + 600, 199),
            .reviewed(t0 + 660, 200),
            .reset(t0 + 700),
            .start(t0 + 800),
            .reviewed(t0 + 800, 10),
            .advance(t0 + 800 + 30 * minute - 1),
            .advance(t0 + 800 + 30 * minute),
        ]),
        ("question-block", .questionBlock, [
            .start(t0),
            .advance(t0 + 60 * minute),
            .advance(t0 + 90 * minute),
            .advance(t0 + 120 * minute),
            .advance(t0 + 130 * minute),
            .start(t0 + 131 * minute),
            .skip(t0 + 140 * minute),
            .skip(t0 + 141 * minute),
        ]),
        ("timer", .timer(10 * minute), [
            .start(t0),
            .advance(t0 + 300),
            .pause(t0 + 300),
            .start(t0 + 360),
            .advance(t0 + 660),
            .start(t0 + 700),
            .skip(t0 + 760),
            .stopFocus(t0 + 770),
            .takeLog(t0 + 780),
        ]),
        ("reset-and-switch", .pomodoro, [
            .start(t0),
            .advance(t0 + 1500),
            .reset(t0 + 1600),
            .start(t0 + 1700),
            .switchMethod(t0 + 1720, .fiftyTwoSeventeen),
            .start(t0 + 1800),
            .switchMethod(t0 + 2400, .ultradian),
            .switchMethod(t0 + 2500, .flowtime(scheme: .tiered)),
            .takeLog(t0 + 2500),
        ]),
        // New lengths mid-phase: a phase already past its new length gets at least a minute more.
        ("retune-custom", .custom(focus: 45 * minute, breakLength: 10 * minute,
                                  longBreak: StudyLongBreak(duration: 20 * minute, every: 3)), [
            .retune(t0, .custom(focus: 40 * minute, breakLength: 10 * minute)),
            .start(t0),
            .advance(t0 + 1200),
            .retune(t0 + 1200, .custom(focus: 15 * minute, breakLength: 5 * minute)),
            .advance(t0 + 1259),
            .advance(t0 + 1260),
            .retune(t0 + 1300, .custom(focus: 15 * minute, breakLength: 2 * minute)),
            .retune(t0 + 1300, .pomodoro),
            .advance(t0 + 1560),
            .start(t0 + 1600),
            .pause(t0 + 1660),
            .retune(t0 + 1700, .custom(focus: 50 * minute, breakLength: 5 * minute)),
        ]),
        ("retune-timer", .timer(25 * minute), [
            .start(t0),
            .advance(t0 + 600),
            .retune(t0 + 600, .timer(5 * minute)),
            .retune(t0 + 600, .timer(60 * minute)),
            .pause(t0 + 900),
            .retune(t0 + 900, .timer(10 * minute)),
            .start(t0 + 1000),
            .advance(t0 + 1060),
        ]),
        ("clamped-method", .pomodoro, [
            .switchMethod(t0, unclampedCustom),
            .start(t0),
            .advance(t0 + 60),
            .switchMethod(t0 + 100, Method(.ankiSprint, focus: .init(kind: "cards", cards: 0),
                                            breakRule: .init(kind: "fixed", seconds: 5 * 60))),
            .start(t0 + 100),
            .reviewed(t0 + 100, 3),
            .reviewed(t0 + 200, 4),
        ]),
        ("no-ops", .pomodoro, [
            .pause(t0),
            .takeLog(t0),
            .stopFocus(t0),
            .start(t0),
            .start(t0 + 100),
            .reset(t0 + 30),
            .reset(t0 + 200),
            .advance(t0 + 5000),
        ]),
        // Quarter seconds, which a double holds exactly: `Date` counts from
        // 2001, so other fractions round differently than seconds since 1970.
        ("fractional-seconds", .pomodoro, [
            .start(t0 + 0.25),
            .pause(t0 + 1499.5),
            .start(t0 + 1500),
            .advance(t0 + 1500.5),
            .advance(t0 + 1500.75),
        ]),
    ]
}

private extension StudySessionGoldenFixture.Method {
    /// The method as an input: the label is an output, so inputs leave it out.
    var asInput: Self {
        var input = self
        input.rhythmLabel = nil
        return input
    }
}
