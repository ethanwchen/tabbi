import Foundation

/// A kind of live activity the closed notch can preview, and the unit the
/// user turns previews on and off by.
///
/// Open rather than a closed enum: besides the built-in kinds with their own
/// look (meetings, music, the focus clock, the pet), every module that
/// publishes `TickerHighlight`s gets a kind of its own, `highlights(from:)`,
/// whose raw value is the module id. So a new module's previews need no
/// ticker code, and a kit's `ticker` list names them by module id.
public struct TickerKind: RawRepresentable, Hashable, Codable, Sendable, Identifiable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var id: String { rawValue }
    public var description: String { rawValue }

    public static let meeting = TickerKind(rawValue: "meeting")
    public static let nowPlaying = TickerKind(rawValue: "nowPlaying")
    public static let focus = TickerKind(rawValue: "focus")
    public static let tasks = TickerKind(rawValue: "tasks")
    public static let progress = TickerKind(rawValue: "progress")
    public static let party = TickerKind(rawValue: "party")
    /// The study pet, last so live data always comes first.
    public static let pet = TickerKind(rawValue: "pet")

    /// Built-in kinds that come before module highlights in the rotation.
    public static let leading: [TickerKind] = [.meeting, .nowPlaying, .focus, .tasks, .progress]
    /// Built-in kinds that come after module highlights.
    public static let trailing: [TickerKind] = [.party, .pet]
    /// Every built-in kind, in rotation order.
    public static let builtIn: [TickerKind] = leading + trailing

    /// The kind for `module`'s highlights.
    public static func highlights(from module: ModuleID) -> TickerKind {
        TickerKind(rawValue: module.rawValue)
    }

    /// Every kind this build can show: the built-in ones, with the
    /// highlights of each module in `catalog` that declares a
    /// `highlightTitle` in between, in catalog order.
    public static func all(in catalog: ModuleCatalog) -> [TickerKind] {
        leading + catalog.descriptors.filter { $0.highlightTitle != nil }.map { highlights(from: $0.id) } + trailing
    }

    public var isBuiltIn: Bool { Self.builtIn.contains(self) }

    /// Label for the per-item toggle in Settings; a module's highlights use
    /// its descriptor's `highlightTitle`.
    public func title(in catalog: ModuleCatalog) -> String {
        switch self {
        case .meeting: "Next meeting"
        case .nowPlaying: "Now playing"
        case .focus: "Focus timer"
        case .tasks: "Tasks left today"
        case .progress: "Goals left today"
        case .pet: "Pet"
        case .party: "Party pets"
        default: catalog.descriptor(for: ModuleID(rawValue: rawValue)).highlightTitle
            ?? catalog.descriptor(for: ModuleID(rawValue: rawValue)).title
        }
    }

    /// The module this preview needs turned on, and whose panel a click
    /// opens. `nil` for the focus clock and progress, which any module can
    /// provide; only enabled modules publish them, and `TickerItem.module`
    /// opens the one they came from.
    public var module: ModuleID? {
        switch self {
        case .meeting, .tasks: .planner
        case .focus, .progress: nil
        case .nowPlaying: .spotify
        case .pet: .closet
        case .party: .party
        default: ModuleID(rawValue: rawValue)
        }
    }
}

/// The meeting a ticker item counts down to.
public struct TickerMeeting: Hashable, Sendable {
    public var title: String
    public var timing: EventTiming
    /// Whether the event carries a video-call link, so the opened panel can offer "Join".
    public var canJoin: Bool

    public init(title: String, timing: EventTiming, canJoin: Bool) {
        self.title = title
        self.timing = timing
        self.canJoin = canJoin
    }
}

/// The study pet beside the closed notch and what it is doing.
public struct TickerPet: Hashable, Sendable {
    public var profile: PetProfile
    public var mood: PetMood

    public init(profile: PetProfile, mood: PetMood) {
        self.profile = profile
        self.mood = mood
    }
}

/// The pets the closed notch shows while the user is in a study party.
public struct TickerParty: Hashable, Sendable {
    /// Most pets that fit beside the notch: the user's and three others.
    public static let maxPets = 4

    /// The user's pet first, capped at `maxPets`.
    public var pets: [ProvidedPartyPet]
    /// Everyone in the party, including members whose pets don't fit.
    public var memberCount: Int

    public init(pets: [ProvidedPartyPet], memberCount: Int) {
        self.pets = pets
        self.memberCount = memberCount
    }
}

/// A focus or break clock under way, as the closed notch shows it.
public struct TickerFocus: Hashable, Sendable {
    public var phase: FocusPhase
    /// The running engine's name for the phase, e.g. "Focus" or "Review".
    public var label: String
    /// Time left, or time worked when `countsUp`.
    public var time: TimeInterval
    /// An open-ended phase (Flowtime, a card sprint) that counts up.
    public var countsUp: Bool
    public var isRunning: Bool
    /// The module running the clock, whose panel a click opens.
    public var source: ModuleID

    public init(phase: FocusPhase, label: String? = nil, time: TimeInterval, countsUp: Bool = false,
                isRunning: Bool, source: ModuleID = .planner) {
        self.phase = phase
        self.label = label ?? FocusTimerFormat.phaseName(phase)
        self.time = time
        self.countsUp = countsUp
        self.isRunning = isRunning
        self.source = source
    }

    /// The clock at `now` for the shared focus clock.
    public init(_ focus: ProvidedFocus, at now: Date) {
        self.init(phase: focus.phase, label: focus.label, time: focus.shownTime(at: now),
                  countsUp: focus.countsUp, isRunning: focus.isRunning, source: focus.source)
    }
}

/// One live activity the closed notch can show beside the hardware cutout.
public enum TickerItem: Hashable, Sendable {
    case meeting(TickerMeeting)
    /// Music is playing; the app renders artwork and the equalizer itself.
    case nowPlaying
    /// A focus clock under way, from whichever module runs it.
    case focus(TickerFocus)
    case tasks(remaining: Int)
    /// An unfinished shared goal, e.g. Anki cards left to review today.
    case progress(ProgressItem)
    /// A module's own line, drawn with its symbol and accent.
    case highlight(TickerHighlight)
    case pet(TickerPet)
    case party(TickerParty)

    public var kind: TickerKind {
        switch self {
        case .meeting: .meeting
        case .nowPlaying: .nowPlaying
        case .focus: .focus
        case .tasks: .tasks
        case .progress: .progress
        case .highlight(let highlight): .highlights(from: highlight.source)
        case .pet: .pet
        case .party: .party
        }
    }

    /// The panel a click on this item opens: the module running a focus
    /// clock or that provided a progress goal or highlight, otherwise the
    /// kind's module.
    public var module: ModuleID {
        switch self {
        case .focus(let focus): return focus.source
        case .progress(let item): return item.source
        case .highlight(let highlight): return highlight.source
        default: return kind.module ?? .planner
        }
    }

    /// What a click runs besides opening `module`: the action the module
    /// offered on its progress goal, if any.
    public var action: ProvidedAction? {
        if case .progress(let item) = self { return item.action }
        return nil
    }

    /// Whether this item should hold the notch instead of rotating away.
    ///
    /// A meeting that starts within `TickerSources.pinLeadTime` or is under
    /// way is the one thing the user must not miss; a module can pin a
    /// highlight for the same reason.
    public var isPinned: Bool {
        switch self {
        case .meeting(let meeting):
            switch meeting.timing {
            case .now: return true
            case .startsIn(let minutes): return TimeInterval(minutes * 60) <= TickerSources.pinLeadTime
            }
        case .highlight(let highlight):
            return highlight.isPinned
        default:
            return false
        }
    }
}

/// A snapshot of every module's state the ticker draws from.
///
/// The app fills this from the merged `ProviderSnapshot`; keeping it a plain
/// value lets the selection rules be tested without any module.
public struct TickerSources: Equatable, Sendable {
    /// Meetings starting this soon (or already under way) pin themselves.
    public static let pinLeadTime: TimeInterval = 5 * 60
    /// Meetings further out than this are not "live" yet and stay hidden.
    public static let meetingHorizon: TimeInterval = 60 * 60

    public var events: [UpcomingEvent]
    public var isMusicPlaying: Bool
    /// The shared focus clock; its `source` is the module running it.
    public var focus: ProvidedFocus?
    public var tasksRemaining: Int
    /// Shared goals from the enabled modules, in tab order.
    public var progress: [ProgressItem]
    /// Modules' own lines, in tab order.
    public var highlights: [TickerHighlight]
    public var pet: PetPresence?
    public var party: ProvidedParty?

    public init(
        events: [UpcomingEvent] = [],
        isMusicPlaying: Bool = false,
        focus: ProvidedFocus? = nil,
        tasksRemaining: Int = 0,
        progress: [ProgressItem] = [],
        highlights: [TickerHighlight] = [],
        pet: PetPresence? = nil,
        party: ProvidedParty? = nil
    ) {
        self.events = events
        self.isMusicPlaying = isMusicPlaying
        self.focus = focus
        self.tasksRemaining = tasksRemaining
        self.progress = progress
        self.highlights = highlights
        self.pet = pet
        self.party = party
    }

    /// What the ticker needs from the enabled modules' merged provisions.
    public init(_ snapshot: ProviderSnapshot) {
        self.init(events: snapshot.events, isMusicPlaying: snapshot.isPlaying, focus: snapshot.focus,
                  tasksRemaining: snapshot.openTasks.count, progress: snapshot.progress,
                  highlights: snapshot.highlights, pet: snapshot.pet, party: snapshot.party)
    }

    /// Every item that has something to say at `now`, in rotation order: the
    /// leading built-in kinds, then one highlight per module (highest
    /// priority first, ties in tab order), then the party and the pet.
    ///
    /// Kinds `enabled` rejects and kinds with no data are skipped, so an
    /// empty result means the notch stays plain black.
    public func items(at now: Date, enabled: (TickerKind) -> Bool = { _ in true }) -> [TickerItem] {
        TickerKind.leading.filter(enabled).compactMap { item(for: $0, at: now) }
            + topHighlights(at: now).filter { enabled(.highlights(from: $0.source)) }.map(TickerItem.highlight)
            + TickerKind.trailing.filter(enabled).compactMap { item(for: $0, at: now) }
    }

    /// `items(at:enabled:)` limited to the kinds in `enabled`.
    public func items(at now: Date, enabled: Set<TickerKind>) -> [TickerItem] {
        items(at: now) { enabled.contains($0) }
    }

    /// The earliest moment after `now` at which `items(at:enabled:)` can
    /// change from the clock alone: a meeting countdown ticking down a
    /// minute, a meeting entering the horizon or ending, a focus phase
    /// ending, a highlight expiring, or the pet dozing off. `nil` when
    /// nothing is pending.
    ///
    /// Lets the caller sleep until then instead of polling. A running focus
    /// clock's per-second change is left to the caller, which only needs it
    /// while that clock is on screen.
    public func nextChange(after now: Date, enabled: (TickerKind) -> Bool = { _ in true }) -> Date? {
        var dates: [Date] = []
        if enabled(.meeting) {
            for event in events where !event.isAllDay && event.end > now {
                let lead = event.start.timeIntervalSince(now)
                if lead > Self.meetingHorizon {
                    dates.append(event.start.addingTimeInterval(-Self.meetingHorizon))
                } else if lead > 0 {
                    // The countdown shows whole minutes rounded up, so it
                    // drops by one each time the lead crosses a minute.
                    let minutes = (lead / 60).rounded(.up)
                    dates.append(event.start.addingTimeInterval(-(minutes - 1) * 60))
                } else {
                    dates.append(event.end)
                }
            }
        }
        if enabled(.focus), let endsAt = focus?.endsAt, endsAt > now {
            dates.append(endsAt)
        }
        dates += highlights.filter { enabled(.highlights(from: $0.source)) }
            .compactMap(\.expiresAt).filter { $0 > now }
        if enabled(.pet), let sleepsAt = pet?.sleepsAt(focus: focus, after: now) {
            dates.append(sleepsAt)
        }
        return dates.min()
    }

    /// `nextChange(after:enabled:)` limited to the kinds in `enabled`.
    public func nextChange(after now: Date, enabled: Set<TickerKind>) -> Date? {
        nextChange(after: now) { enabled.contains($0) }
    }

    /// Each module's live highlight with the highest priority (ties keep the
    /// module's own order), ordered by priority with ties in tab order.
    private func topHighlights(at now: Date) -> [TickerHighlight] {
        var best: [ModuleID: TickerHighlight] = [:]
        var modules: [ModuleID] = []
        for highlight in highlights where highlight.isLive(at: now) {
            guard let current = best[highlight.source] else {
                best[highlight.source] = highlight
                modules.append(highlight.source)
                continue
            }
            if highlight.priority > current.priority { best[highlight.source] = highlight }
        }
        return modules.compactMap { best[$0] }.enumerated()
            .sorted { ($1.element.priority, $0.offset) < ($0.element.priority, $1.offset) }
            .map(\.element)
    }

    private func item(for kind: TickerKind, at now: Date) -> TickerItem? {
        switch kind {
        case .meeting:
            // A meeting about to start beats one already under way, so a long
            // block can't hide "Standup in 3 min".
            let upcoming = UpcomingEvent.upNext(from: events, at: now, limit: events.count)
            let imminent = upcoming.first { $0.start > now && $0.start.timeIntervalSince(now) <= Self.pinLeadTime }
            guard let event = imminent ?? upcoming.first,
                  event.start.timeIntervalSince(now) <= Self.meetingHorizon else { return nil }
            return .meeting(TickerMeeting(
                title: UpcomingEventFormat.title(event),
                timing: event.timing(at: now),
                canJoin: event.meetingLink != nil
            ))
        case .nowPlaying:
            return isMusicPlaying ? .nowPlaying : nil
        case .focus:
            // An idle timer isn't an activity; paused still is, since the
            // user is mid-session.
            guard let focus, focus.isActive else { return nil }
            return .focus(TickerFocus(focus, at: now))
        case .tasks:
            return tasksRemaining > 0 ? .tasks(remaining: tasksRemaining) : nil
        case .progress:
            // The first goal in tab order with work left; a finished goal
            // has nothing to say, and nor has an untouched aspiration.
            return progress.first(where: \.showsBesideNotch).map(TickerItem.progress)
        case .pet:
            guard let pet else { return nil }
            return .pet(TickerPet(profile: pet.profile, mood: pet.mood(focus: focus, at: now)))
        case .party:
            // Alone in a party there are no other pets to show.
            guard let party, party.memberCount > 1 else { return nil }
            return .party(TickerParty(pets: Array(party.pets.prefix(TickerParty.maxPets)),
                                      memberCount: party.memberCount))
        default:
            return nil
        }
    }
}
