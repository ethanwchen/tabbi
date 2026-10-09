import Foundation
import TabbiKitCore
import XCTest

/// Pins the closed-notch ticker, which item each kind of live activity
/// becomes, when the ticker next has to wake, and which item the rotation
/// shows, to the golden fixture `shared/fixtures/ticker/ticker.json`.
///
/// The Windows port feeds the same sources through its own ticker and
/// compares with the recorded items, so both apps show the same line beside
/// the notch. Run with `TABBI_RECORD_FIXTURES=1` to rewrite it after an
/// intended change.
final class TickerGoldenTests: XCTestCase {
    func testTickerMatchesGoldenFixture() throws {
        let url = TickerGoldenFixture.url
        let current = TickerGoldenFixture.current()
        if ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1" {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PetGoldenFixtures.encode(current).write(to: url)
            return
        }
        let stored = try JSONDecoder().decode(TickerGoldenFixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(stored.constants, current.constants, "Ticker constants changed")
        XCTAssertEqual(stored.kinds, current.kinds, "Ticker kinds changed")
        XCTAssertEqual(stored.selections.map(\.name), current.selections.map(\.name))
        for (old, new) in zip(stored.selections, current.selections) {
            XCTAssertEqual(old.sources, new.sources, old.name)
            XCTAssertEqual(old.reads.count, new.reads.count, old.name)
            for (index, (oldRead, newRead)) in zip(old.reads, new.reads).enumerated() {
                XCTAssertEqual(oldRead, newRead, "Selection \(old.name), read \(index)")
            }
        }
        XCTAssertEqual(stored.rotations.map(\.name), current.rotations.map(\.name))
        for (old, new) in zip(stored.rotations, current.rotations) {
            XCTAssertEqual(old, new, "Rotation \(old.name)")
        }
        XCTAssertEqual(stored, current, "The ticker no longer matches \(url.lastPathComponent)")
    }

    /// The fixture's own inputs, replayed: a port that reads only the inputs
    /// from the file gets the recorded outputs.
    func testStoredInputsReplayToStoredOutputs() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1", "Recording")
        let stored = try JSONDecoder().decode(TickerGoldenFixture.self, from: Data(contentsOf: TickerGoldenFixture.url))
        for selection in stored.selections {
            let reads = selection.reads.map { TickerGoldenFixture.Query(at: $0.at, enabled: $0.enabled) }
            XCTAssertEqual(TickerGoldenFixture.select(selection.sources, reads: reads), selection.reads, selection.name)
        }
        for rotation in stored.rotations {
            let steps = rotation.steps.map {
                TickerGoldenFixture.RotationInput(at: $0.at, interval: $0.interval, items: $0.items)
            }
            XCTAssertEqual(TickerGoldenFixture.rotate(interval: rotation.interval, steps: steps), rotation.steps, rotation.name)
        }
    }
}

/// Ticker sources read at given moments with given kinds turned on, and
/// rotation sequences over lists of available items.
struct TickerGoldenFixture: Codable, Equatable {
    static let schemaName = "tabbi.ticker.golden"

    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/ticker/ticker.json")
    }

    struct Constants: Codable, Equatable {
        var pinLeadTime: Double
        var meetingHorizon: Double
        var petSleepAfter: Double
        var maxPartyPets: Int
    }

    /// A built-in kind: whether it leads or trails the module highlights,
    /// and the module it needs (nil for kinds any module can provide).
    struct Kind: Codable, Equatable {
        var kind: String
        var position: String
        var module: String?
    }

    // MARK: Sources

    struct Link: Codable, Equatable {
        var provider: String
        var url: String
    }

    struct Event: Codable, Equatable {
        var id: String
        var title: String
        var start: Double
        var end: Double
        var isAllDay: Bool = false
        var meetingLink: Link?
    }

    /// The shared focus clock: `clock.kind` is `idle`, `countdown` (with
    /// `endsAt`), `countUp` (with `since`) or `paused` (with `shown`).
    struct Focus: Codable, Equatable {
        struct Clock: Codable, Equatable {
            var kind: String
            var endsAt: Double?
            var since: Double?
            var shown: Double?
        }

        var source: String
        var phase: String
        var label: String
        var clock: Clock
        var phaseLength: Double?
    }

    struct Action: Codable, Equatable {
        var id: String
        var title: String
    }

    struct Progress: Codable, Equatable {
        var id: String
        var source: String
        var title: String
        var completed: Int
        var target: Int
        var unit: String
        var action: Action?
        var waitsForStart: Bool = false
    }

    struct Highlight: Codable, Equatable {
        var id: String
        var source: String
        var symbol: String?
        var text: String
        var summary: String
        var tone: String
        var priority: Int
        var isPinned: Bool
        var expiresAt: Double?
    }

    /// A pet's look as far as the ticker cares. An empty `name` makes the
    /// pet go by its breed's name.
    struct Pet: Codable, Equatable {
        var name: String
        var breed: String
    }

    struct Presence: Codable, Equatable {
        var pet: Pet
        var lastActive: Double
    }

    struct PartyPet: Codable, Equatable {
        var id: String
        var name: String
        var pet: Pet
        var isAway: Bool = false
    }

    struct Sources: Codable, Equatable {
        var events: [Event] = []
        var isMusicPlaying = false
        var focus: Focus?
        var tasksRemaining = 0
        var progress: [Progress] = []
        var highlights: [Highlight] = []
        var pet: Presence?
        /// Everyone in the party, the user's pet first.
        var party: [PartyPet]?
    }

    // MARK: Items

    struct Timing: Codable, Equatable {
        var kind: String
        var minutes: Int?
    }

    struct Meeting: Codable, Equatable {
        var title: String
        var timing: Timing
        var canJoin: Bool
        var countdown: String
        var summary: String
    }

    struct FocusItem: Codable, Equatable {
        var phase: String
        var label: String
        var time: Double
        var countsUp: Bool
        var isRunning: Bool
        var source: String
        var clock: String
        var summary: String
    }

    struct Tasks: Codable, Equatable {
        var remaining: Int
        var text: String
    }

    struct ProgressItem: Codable, Equatable {
        var id: String
        var source: String
        var title: String
        var remaining: Int
        var unit: String
        var text: String
    }

    struct PetItem: Codable, Equatable {
        var name: String
        var breed: String
        var mood: String
        var moodSince: Double?
        var label: String?
        var summary: String
    }

    struct PartyItem: Codable, Equatable {
        var pets: [PartyPet]
        var memberCount: Int
        var size: String
    }

    /// One item the ticker can show: its kind, the module a click opens, the
    /// action a click runs, whether it pins, and the case's own fields.
    struct Item: Codable, Equatable {
        var kind: String
        var module: String
        var isPinned: Bool
        var action: Action?
        var meeting: Meeting?
        var focus: FocusItem?
        var tasks: Tasks?
        var progress: ProgressItem?
        var highlight: Highlight?
        var pet: PetItem?
        var party: PartyItem?
    }

    /// `items(at:enabled:)` and `nextChange(after:enabled:)` at `at`, with
    /// only the kinds in `enabled` turned on (every kind when absent).
    struct Read: Codable, Equatable {
        var at: Double
        var enabled: [String]?
        var items: [Item]
        var nextChange: Double?
    }

    struct Query {
        var at: Double
        var enabled: [String]?
    }

    struct Selection: Codable, Equatable {
        var name: String
        var sources: Sources
        var reads: [Read]
    }

    // MARK: Rotation

    /// An available item, reduced to what the rotation reads. Only a
    /// `meeting` or a module highlight can be `pinned`.
    struct RotationItem: Codable, Equatable {
        var kind: String
        var pinned: Bool = false
    }

    struct RotationInput {
        var at: Double
        var interval: Double?
        var items: [RotationItem]
    }

    /// One `update(items:at:)`, after setting the interval when `interval`
    /// is given, with the kind it returned and the state it left.
    struct RotationStep: Codable, Equatable {
        var at: Double
        var interval: Double?
        var items: [RotationItem]
        var shown: String?
        var currentKind: String?
        var shownSince: Double?
    }

    struct Rotation: Codable, Equatable {
        var name: String
        /// As constructed; the rotation holds each item at least one second.
        var interval: Double
        var steps: [RotationStep]
    }

    var schema = Self.schemaName
    var version = 1
    var constants: Constants
    var kinds: [Kind]
    var selections: [Selection]
    var rotations: [Rotation]

    static func current() -> TickerGoldenFixture {
        let leading = TickerKind.leading.map { Kind(kind: $0.rawValue, position: "leading", module: $0.module?.rawValue) }
        let trailing = TickerKind.trailing.map { Kind(kind: $0.rawValue, position: "trailing", module: $0.module?.rawValue) }
        return TickerGoldenFixture(
            constants: Constants(pinLeadTime: TickerSources.pinLeadTime, meetingHorizon: TickerSources.meetingHorizon,
                                 petSleepAfter: PetPresence.sleepAfter, maxPartyPets: TickerParty.maxPets),
            kinds: leading + trailing,
            selections: sampleSelections.map { name, sources, queries in
                Selection(name: name, sources: sources, reads: select(sources, reads: queries))
            },
            rotations: sampleRotations.map { name, interval, steps in
                Rotation(name: name, interval: interval, steps: rotate(interval: interval, steps: steps))
            }
        )
    }

    // MARK: Running

    static func select(_ sources: Sources, reads: [Query]) -> [Read] {
        let ticker = tickerSources(sources)
        return reads.map { query in
            let now = date(query.at)
            let items: [TickerItem]
            let next: Date?
            if let enabled = query.enabled {
                let kinds = Set(enabled.map(TickerKind.init(rawValue:)))
                items = ticker.items(at: now, enabled: kinds)
                next = ticker.nextChange(after: now, enabled: kinds)
            } else {
                items = ticker.items(at: now)
                next = ticker.nextChange(after: now)
            }
            return Read(at: query.at, enabled: query.enabled, items: items.map(item),
                        nextChange: next?.timeIntervalSince1970)
        }
    }

    static func rotate(interval: Double, steps: [RotationInput]) -> [RotationStep] {
        var rotation = TickerRotation(interval: interval)
        return steps.map { step in
            if let interval = step.interval { rotation.interval = interval }
            let shown = rotation.update(items: step.items.map(tickerItem), at: date(step.at))
            return RotationStep(at: step.at, interval: step.interval, items: step.items, shown: shown?.kind.rawValue,
                                currentKind: rotation.currentKind?.rawValue,
                                shownSince: rotation.shownSince?.timeIntervalSince1970)
        }
    }

    private static func date(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }

    private static func tickerSources(_ sources: Sources) -> TickerSources {
        let events = sources.events.map { event in
            UpcomingEvent(
                id: event.id, title: event.title, start: date(event.start), end: date(event.end), isAllDay: event.isAllDay,
                meetingLink: event.meetingLink.map {
                    MeetingLink(provider: MeetingLink.Provider(rawValue: $0.provider)!, url: URL(string: $0.url)!)
                }
            )
        }
        let progress = sources.progress.map { goal in
            TabbiKitCore.ProgressItem(
                id: goal.id, source: ModuleID(goal.source), title: goal.title, completed: goal.completed,
                target: goal.target, unit: goal.unit, action: goal.action.map { ProvidedAction(id: $0.id, title: $0.title) },
                waitsForStart: goal.waitsForStart
            )
        }
        let highlights = sources.highlights.map { line in
            TickerHighlight(
                id: line.id, source: ModuleID(line.source), symbol: line.symbol, text: line.text, summary: line.summary,
                tone: TickerHighlight.Tone(rawValue: line.tone)!, priority: line.priority, isPinned: line.isPinned,
                expiresAt: line.expiresAt.map(date)
            )
        }
        let party = sources.party.map { members in
            ProvidedParty(pets: members.map {
                ProvidedPartyPet(id: $0.id, name: $0.name, pet: profile($0.pet), isAway: $0.isAway)
            })
        }
        return TickerSources(
            events: events, isMusicPlaying: sources.isMusicPlaying, focus: sources.focus.map(providedFocus),
            tasksRemaining: sources.tasksRemaining, progress: progress, highlights: highlights,
            pet: sources.pet.map { PetPresence(profile: profile($0.pet), lastActive: date($0.lastActive)) },
            party: party
        )
    }

    private static func profile(_ pet: Pet) -> PetProfile {
        PetProfile(name: pet.name, breed: PetBreed(rawValue: pet.breed)!)
    }

    private static func providedFocus(_ focus: Focus) -> ProvidedFocus {
        let clock: ProvidedFocus.Clock = switch focus.clock.kind {
        case "countdown": .countdown(endsAt: date(focus.clock.endsAt ?? 0))
        case "countUp": .countUp(since: date(focus.clock.since ?? 0))
        case "paused": .paused(shown: focus.clock.shown ?? 0)
        default: .idle
        }
        return ProvidedFocus(source: ModuleID(focus.source), phase: FocusPhase(rawValue: focus.phase)!,
                             label: focus.label, clock: clock, phaseLength: focus.phaseLength)
    }

    private static func pet(_ profile: PetProfile) -> Pet {
        Pet(name: profile.name, breed: profile.breed.rawValue)
    }

    private static func item(_ item: TickerItem) -> Item {
        var result = Item(kind: item.kind.rawValue, module: item.module.rawValue, isPinned: item.isPinned,
                          action: item.action.map { Action(id: $0.id, title: $0.title) })
        switch item {
        case .meeting(let meeting):
            let timing: Timing = switch meeting.timing {
            case .now: Timing(kind: "now")
            case .startsIn(let minutes): Timing(kind: "startsIn", minutes: minutes)
            }
            result.meeting = Meeting(title: meeting.title, timing: timing, canJoin: meeting.canJoin,
                                     countdown: TickerFormat.meetingCountdown(meeting.timing),
                                     summary: TickerFormat.meetingSummary(meeting))
        case .nowPlaying:
            break
        case .focus(let focus):
            result.focus = FocusItem(phase: focus.phase.rawValue, label: focus.label, time: focus.time,
                                     countsUp: focus.countsUp, isRunning: focus.isRunning, source: focus.source.rawValue,
                                     clock: TickerFormat.focusClock(focus.time), summary: TickerFormat.focusSummary(focus))
        case .tasks(let remaining):
            result.tasks = Tasks(remaining: remaining, text: TickerFormat.tasksLeft(remaining))
        case .progress(let goal):
            result.progress = ProgressItem(id: goal.id, source: goal.source.rawValue, title: goal.title,
                                           remaining: goal.remaining, unit: goal.unit,
                                           text: TickerFormat.progressLeft(goal))
        case .highlight(let line):
            result.highlight = Highlight(id: line.id, source: line.source.rawValue, symbol: line.symbol, text: line.text,
                                         summary: line.summary, tone: line.tone.rawValue, priority: line.priority,
                                         isPinned: line.isPinned, expiresAt: line.expiresAt?.timeIntervalSince1970)
        case .pet(let tickerPet):
            result.pet = PetItem(name: tickerPet.profile.name, breed: tickerPet.profile.breed.rawValue,
                                 mood: tickerPet.mood.rawValue, moodSince: tickerPet.moodSince?.timeIntervalSince1970,
                                 label: TickerFormat.petLabel(tickerPet), summary: TickerFormat.petSummary(tickerPet))
        case .party(let party):
            result.party = PartyItem(
                pets: party.pets.map { PartyPet(id: $0.id, name: $0.name, pet: pet($0.pet), isAway: $0.isAway) },
                memberCount: party.memberCount, size: TickerFormat.partySize(party.memberCount)
            )
        }
        return result
    }

    /// A stand-in item of `kind`; the rotation reads only kinds and pins.
    private static func tickerItem(_ rotationItem: RotationItem) -> TickerItem {
        let kind = TickerKind(rawValue: rotationItem.kind)
        let item: TickerItem = switch kind {
        case .meeting:
            .meeting(TickerMeeting(title: "Standup", timing: rotationItem.pinned ? .now : .startsIn(minutes: 30),
                                   canJoin: false))
        case .nowPlaying: .nowPlaying
        case .focus: .focus(TickerFocus(phase: .focus, time: 600, isRunning: true))
        case .tasks: .tasks(remaining: 2)
        case .progress:
            .progress(TabbiKitCore.ProgressItem(id: "reviews", source: .anki, title: "Reviews", completed: 1,
                                                target: 2, unit: "cards"))
        case .pet: .pet(TickerPet(profile: .starter(.cat), mood: .awake))
        case .party: .party(TickerParty(pets: [], memberCount: 2))
        default:
            .highlight(TickerHighlight(id: "line", source: ModuleID(kind.rawValue), text: "line",
                                       isPinned: rotationItem.pinned))
        }
        XCTAssertEqual(item.isPinned, rotationItem.pinned, "Only meetings and highlights pin: \(rotationItem.kind)")
        return item
    }

    // MARK: - Inputs

    /// A fixed moment, in seconds since 1970.
    static let t0: Double = 1_790_000_000

    static let zoom = Link(provider: "zoom", url: "https://example.zoom.us/j/123456789")

    static let mochi = Pet(name: "Mochi", breed: "britishShorthair")
    static let pip = Pet(name: "  Pip  ", breed: "orangeTabby")

    static var sampleSelections: [(String, Sources, [Query])] {
        selectionsAboutEverything + selectionsAboutMeetings + selectionsAboutFocusAndGoals + selectionsAboutPetsAndParties
    }

    private static var selectionsAboutEverything: [(String, Sources, [Query])] {
        var everything = Sources()
        everything.events = [Event(id: "standup", title: "Standup", start: t0 + 1800, end: t0 + 2700, meetingLink: zoom)]
        everything.isMusicPlaying = true
        everything.focus = Focus(source: "planner", phase: "focus", label: "Focus",
                                 clock: Focus.Clock(kind: "countdown", endsAt: t0 + 600), phaseLength: 1500)
        everything.tasksRemaining = 3
        everything.progress = [
            Progress(id: "done", source: "study", title: "Study goal", completed: 120, target: 120, unit: "min"),
            Progress(id: "reviews", source: "anki", title: "Anki reviews", completed: 16, target: 100, unit: "cards",
                     action: Action(id: "study:Pharm", title: "Study Pharm Sketchy")),
        ]
        everything.highlights = [
            Highlight(id: "5h", source: "claudeUsage", symbol: nil, text: "5h 86%", summary: "Claude usage 5h 86%",
                      tone: "accent", priority: 1, isPinned: false, expiresAt: t0 + 7200),
            Highlight(id: "daily", source: "leetcode", symbol: "chevron.left.forwardslash.chevron.right",
                      text: "1 problem left", summary: "LeetCode daily, 1 problem left", tone: "primary",
                      priority: 0, isPinned: false, expiresAt: nil),
        ]
        everything.pet = Presence(pet: mochi, lastActive: t0 - 60)
        everything.party = [
            PartyPet(id: "me", name: "Me", pet: mochi),
            PartyPet(id: "maya", name: "Maya", pet: Pet(name: "", breed: "corgi")),
        ]
        return [
            ("nothing", Sources(), [Query(at: t0)]),
            ("everything-in-rotation-order", everything, [
                Query(at: t0),
                Query(at: t0, enabled: ["meeting", "tasks", "claudeUsage", "pet"]),
                Query(at: t0, enabled: ["leetcode", "party"]),
                Query(at: t0, enabled: []),
                Query(at: t0 + 600),
                Query(at: t0 + 7200),
            ]),
        ]
    }

    private static var selectionsAboutMeetings: [(String, Sources, [Query])] {
        var countdown = Sources()
        countdown.events = [Event(id: "review", title: "Design review", start: t0 + 330.5, end: t0 + 1800)]
        var horizon = Sources()
        horizon.events = [
            Event(id: "offsite", title: "Offsite", start: t0 - 3600, end: t0 + 80_000, isAllDay: true),
            Event(id: "over", title: "Earlier call", start: t0 - 1800, end: t0 - 60),
            Event(id: "later", title: "1:1 with Sam", start: t0 + 3660, end: t0 + 5400),
        ]
        var overlap = Sources()
        overlap.events = [
            Event(id: "block", title: "Deep work", start: t0 - 600, end: t0 + 3600),
            Event(id: "standup", title: "Standup", start: t0 + 180, end: t0 + 1080, meetingLink: zoom),
            Event(id: "quick", title: "   ", start: t0 + 240, end: t0 + 600),
        ]
        var hours = Sources()
        hours.events = [Event(id: "far", title: "Lunch", start: t0 + 3600, end: t0 + 7200)]
        return [
            ("meeting-countdown-and-pin", countdown, [
                Query(at: t0),
                Query(at: t0 + 30),
                Query(at: t0 + 30.5),
                Query(at: t0 + 31),
                Query(at: t0 + 270.5),
                Query(at: t0 + 330),
                Query(at: t0 + 330.5),
                Query(at: t0 + 1800),
                Query(at: t0, enabled: ["focus"]),
            ]),
            ("meeting-horizon-and-all-day", horizon, [
                Query(at: t0),
                Query(at: t0 + 59),
                Query(at: t0 + 60),
                Query(at: t0 + 3660),
            ]),
            ("imminent-beats-under-way", overlap, [
                Query(at: t0),
                Query(at: t0 + 179),
                Query(at: t0 + 180),
                Query(at: t0 + 600),
            ]),
            ("meeting-an-hour-out", hours, [
                Query(at: t0),
                Query(at: t0 + 1),
                Query(at: t0 + 59.75),
            ]),
        ]
    }

    private static var selectionsAboutFocusAndGoals: [(String, Sources, [Query])] {
        var idle = Sources()
        idle.focus = Focus(source: "focus", phase: "focus", label: "Focus", clock: Focus.Clock(kind: "idle"),
                           phaseLength: 1500)
        var paused = Sources()
        paused.focus = Focus(source: "study", phase: "rest", label: "Long break",
                             clock: Focus.Clock(kind: "paused", shown: 190), phaseLength: 900)
        var countUp = Sources()
        countUp.focus = Focus(source: "study", phase: "focus", label: "Review",
                              clock: Focus.Clock(kind: "countUp", since: t0 - 725), phaseLength: nil)
        var ended = Sources()
        ended.focus = Focus(source: "planner", phase: "focus", label: "Focus",
                            clock: Focus.Clock(kind: "countdown", endsAt: t0 + 0.25), phaseLength: 1500)
        var goals = Sources()
        goals.tasksRemaining = 1
        goals.progress = [
            Progress(id: "nothing-due", source: "anki", title: "Anki reviews", completed: 0, target: 0, unit: "cards"),
            Progress(id: "minutes", source: "study", title: "Study goal", completed: 0, target: 120, unit: "min",
                     waitsForStart: true),
            Progress(id: "over", source: "leetcode", title: "Problems", completed: 3, target: 2, unit: "problems"),
            Progress(id: "questions", source: "qbank", title: "Questions", completed: 12, target: 40, unit: "questions"),
        ]
        var startedGoal = Sources()
        startedGoal.progress = [
            Progress(id: "minutes", source: "study", title: "Study goal", completed: 5, target: 120, unit: "min",
                     waitsForStart: true),
        ]
        return [
            ("focus-idle-is-hidden", idle, [Query(at: t0)]),
            ("focus-paused-break", paused, [Query(at: t0), Query(at: t0 + 600)]),
            ("focus-counting-up", countUp, [Query(at: t0), Query(at: t0 + 0.5)]),
            ("focus-countdown-running-out", ended, [Query(at: t0), Query(at: t0 + 0.25), Query(at: t0 + 60)]),
            ("tasks-and-first-unfinished-goal", goals, [Query(at: t0), Query(at: t0, enabled: ["progress"])]),
            ("started-goal-shows", startedGoal, [Query(at: t0)]),
        ]
    }

    private static var selectionsAboutPetsAndParties: [(String, Sources, [Query])] {
        var highlights = Sources()
        highlights.highlights = [
            Highlight(id: "weekly", source: "claudeUsage", symbol: nil, text: "7d 81%", summary: "Claude usage 7d 81%",
                      tone: "accent", priority: 1, isPinned: false, expiresAt: t0 + 900),
            Highlight(id: "5h", source: "claudeUsage", symbol: nil, text: "5h 100%", summary: "Claude usage 5h 100%",
                      tone: "danger", priority: 3, isPinned: false, expiresAt: t0 + 300),
            Highlight(id: "streak", source: "leetcode", symbol: nil, text: "Streak 12", summary: "12 day streak",
                      tone: "secondary", priority: 1, isPinned: false, expiresAt: nil),
            Highlight(id: "tie", source: "leetcode", symbol: nil, text: "Tie", summary: "Same priority, later",
                      tone: "primary", priority: 1, isPinned: false, expiresAt: nil),
            Highlight(id: "deadline", source: "qbank", symbol: "exclamationmark.circle", text: "Exam in 1 h",
                      summary: "Practice exam starts in 1 hour", tone: "accent", priority: 1, isPinned: true,
                      expiresAt: t0 + 3600),
        ]
        var asleep = Sources()
        asleep.pet = Presence(pet: mochi, lastActive: t0 - 600)
        var studying = Sources()
        studying.pet = Presence(pet: pip, lastActive: t0 - 7200)
        studying.focus = Focus(source: "study", phase: "focus", label: "Focus",
                               clock: Focus.Clock(kind: "countdown", endsAt: t0 + 1200), phaseLength: 3000)
        var onBreak = Sources()
        onBreak.pet = Presence(pet: Pet(name: "", breed: "goldenRetriever"), lastActive: t0 - 7200)
        onBreak.focus = Focus(source: "planner", phase: "rest", label: "Break",
                              clock: Focus.Clock(kind: "countUp", since: t0 - 90), phaseLength: 300)
        var pausedPet = Sources()
        pausedPet.pet = Presence(pet: Pet(name: "Biscuit", breed: "beagle"), lastActive: t0 - 7200)
        pausedPet.focus = Focus(source: "planner", phase: "focus", label: "Focus",
                                clock: Focus.Clock(kind: "paused", shown: 600), phaseLength: 1500)
        var alone = Sources()
        alone.party = [PartyPet(id: "me", name: "Me", pet: mochi)]
        var crowd = Sources()
        crowd.party = [
            PartyPet(id: "me", name: "Me", pet: pip),
            PartyPet(id: "maya", name: "Maya", pet: Pet(name: "Noodle", breed: "dachshund")),
            PartyPet(id: "jo", name: "Jo", pet: Pet(name: "", breed: "siamese"), isAway: true),
            PartyPet(id: "lee", name: "Lee", pet: Pet(name: "Biscuit", breed: "poodle")),
            PartyPet(id: "ana", name: "Ana", pet: Pet(name: "Mochi", breed: "calico")),
            PartyPet(id: "kai", name: "Kai", pet: Pet(name: "Pepper", breed: "tuxedo")),
        ]
        return [
            ("highlights-priority-pins-and-expiry", highlights, [
                Query(at: t0),
                Query(at: t0 + 300),
                Query(at: t0 + 900),
                Query(at: t0 + 3600),
                Query(at: t0, enabled: ["claudeUsage", "leetcode"]),
            ]),
            ("pet-dozes-off", asleep, [
                Query(at: t0),
                Query(at: t0 + 599),
                Query(at: t0 + 600),
                Query(at: t0, enabled: ["meeting"]),
            ]),
            ("pet-studying-with-user-name", studying, [Query(at: t0), Query(at: t0 + 1300)]),
            ("pet-on-counting-break", onBreak, [Query(at: t0)]),
            ("pet-awake-while-paused", pausedPet, [Query(at: t0)]),
            ("party-alone-is-hidden", alone, [Query(at: t0)]),
            ("party-capped-at-four-pets", crowd, [Query(at: t0)]),
        ]
    }

    private static func step(_ at: Double, _ kinds: [String], pinned: String? = nil,
                             interval: Double? = nil) -> RotationInput {
        RotationInput(at: at, interval: interval, items: kinds.map { RotationItem(kind: $0, pinned: $0 == pinned) })
    }

    static let sampleRotations: [(String, Double, [RotationInput])] = [
        ("nothing-to-show", 8, [
            step(t0, []),
        ]),
        ("holds-each-item-then-wraps", 8, [
            step(t0, ["tasks", "progress", "pet"]),
            step(t0 + 7.75, ["tasks", "progress", "pet"]),
            step(t0 + 8, ["tasks", "progress", "pet"]),
            step(t0 + 16, ["tasks", "progress", "pet"]),
            step(t0 + 24, ["tasks", "progress", "pet"]),
        ]),
        ("single-item-restarts-its-hold", 8, [
            step(t0, ["nowPlaying"]),
            step(t0 + 8, ["nowPlaying"]),
            step(t0 + 9, ["nowPlaying"]),
        ]),
        ("vanished-item-hands-over-to-its-successor", 8, [
            step(t0, ["meeting", "focus", "tasks", "pet"]),
            step(t0 + 8, ["meeting", "focus", "tasks", "pet"]),
            step(t0 + 9, ["meeting", "tasks", "pet"]),
            step(t0 + 10, ["meeting", "pet"]),
        ]),
        ("vanished-last-item-wraps-to-first", 8, [
            step(t0, ["tasks", "pet"]),
            step(t0 + 8, ["tasks", "pet"]),
            step(t0 + 9, ["tasks"]),
        ]),
        ("vanished-item-and-successors-fall-back-to-first", 8, [
            step(t0, ["focus", "tasks", "pet"]),
            step(t0 + 8, ["focus", "tasks", "pet"]),
            step(t0 + 9, ["focus", "pet"]),
            step(t0 + 10, ["nowPlaying", "party"]),
        ]),
        ("new-item-joins-in-order", 8, [
            step(t0, ["tasks", "pet"]),
            step(t0 + 4, ["tasks", "progress", "pet"]),
            step(t0 + 8, ["tasks", "progress", "pet"]),
        ]),
        ("pinned-meeting-holds-then-rotation-resumes", 8, [
            step(t0, ["tasks", "pet"]),
            step(t0 + 2, ["meeting", "tasks", "pet"], pinned: "meeting"),
            step(t0 + 30, ["meeting", "tasks", "pet"], pinned: "meeting"),
            step(t0 + 31, ["tasks", "pet"]),
            step(t0 + 38, ["tasks", "pet"]),
            step(t0 + 39, ["tasks", "pet"]),
        ]),
        ("unpinned-meeting-rotates", 8, [
            step(t0, ["meeting", "tasks"]),
            step(t0 + 8, ["meeting", "tasks"]),
            step(t0 + 16, ["meeting", "tasks"], pinned: "meeting"),
            step(t0 + 17, ["meeting", "tasks"]),
        ]),
        ("pinned-highlight-holds-the-notch", 8, [
            step(t0, ["claudeUsage", "qbank", "pet"], pinned: "qbank"),
            step(t0 + 20, ["claudeUsage", "qbank", "pet"], pinned: "qbank"),
            step(t0 + 21, ["claudeUsage", "pet"]),
        ]),
        ("interval-changes-apply-to-the-item-on-screen", 8, [
            step(t0, ["tasks", "pet"]),
            step(t0 + 8, ["tasks", "pet"], interval: 20),
            step(t0 + 27, ["tasks", "pet"]),
            step(t0 + 28, ["tasks", "pet"], interval: 0),
            step(t0 + 28.5, ["tasks", "pet"]),
            step(t0 + 29, ["tasks", "pet"]),
        ]),
        ("interval-clamped-to-one-second", 0, [
            step(t0, ["tasks", "pet"]),
            step(t0 + 0.75, ["tasks", "pet"]),
            step(t0 + 1, ["tasks", "pet"]),
        ]),
        ("everything-disappearing-clears-the-rotation", 8, [
            step(t0, ["tasks", "pet"]),
            step(t0 + 8, ["tasks", "pet"]),
            step(t0 + 9, []),
            step(t0 + 10, ["tasks", "pet"]),
        ]),
    ]
}
