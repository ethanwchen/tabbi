import Foundation

/// The kinds of live activity the closed notch can preview, in rotation order.
public enum TickerKind: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case meeting
    case nowPlaying
    case focus
    case tasks
    case progress
    case claudeUsage
    case party
    /// The study pet, last so live data always comes first.
    case pet

    public var id: String { rawValue }

    /// Label for the per-item toggle in Settings.
    public var title: String {
        switch self {
        case .meeting: "Next meeting"
        case .nowPlaying: "Now playing"
        case .focus: "Focus timer"
        case .tasks: "Tasks left today"
        case .progress: "Study goals left today"
        case .claudeUsage: "Claude usage above 80%"
        case .pet: "Study pet"
        case .party: "Study party pets"
        }
    }

    /// The module this preview needs turned on, and whose panel a click opens.
    /// `nil` for progress, which any module can provide; only enabled modules
    /// publish it, and `TickerItem.module` opens the one it came from.
    public var module: ModuleID? {
        switch self {
        case .meeting, .focus, .tasks: .planner
        case .nowPlaying: .spotify
        case .progress: nil
        case .claudeUsage: .claudeUsage
        case .pet: .closet
        case .party: .party
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

/// Which Claude usage window crossed the warning threshold.
public enum TickerUsageWindow: Hashable, Sendable {
    case fiveHour
    case weekly
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

/// One live activity the closed notch can show beside the hardware cutout.
public enum TickerItem: Hashable, Sendable {
    case meeting(TickerMeeting)
    /// Music is playing; the app renders artwork and the equalizer itself.
    case nowPlaying
    case focus(phase: FocusPhase, remaining: TimeInterval, isRunning: Bool)
    case tasks(remaining: Int)
    /// An unfinished shared goal, e.g. Anki cards left to review today.
    case progress(ProgressItem)
    case claudeUsage(window: TickerUsageWindow, utilization: Double)
    case pet(TickerPet)
    case party(TickerParty)

    public var kind: TickerKind {
        switch self {
        case .meeting: .meeting
        case .nowPlaying: .nowPlaying
        case .focus: .focus
        case .tasks: .tasks
        case .progress: .progress
        case .claudeUsage: .claudeUsage
        case .pet: .pet
        case .party: .party
        }
    }

    /// The panel a click on this preview opens: the kind's module, or for
    /// progress the module that provided the goal.
    public var module: ModuleID {
        if case .progress(let item) = self { return item.source }
        return kind.module ?? .planner
    }

    /// Whether this item should hold the notch instead of rotating away.
    ///
    /// A meeting that starts within `TickerSources.pinLeadTime` or is under
    /// way is the one thing the user must not miss.
    public var isPinned: Bool {
        guard case .meeting(let meeting) = self else { return false }
        switch meeting.timing {
        case .now: return true
        case .startsIn(let minutes): return TimeInterval(minutes * 60) <= TickerSources.pinLeadTime
        }
    }
}

/// A snapshot of every module's state the ticker draws from.
///
/// The app fills this from its stores; keeping it a plain value lets the
/// selection rules be tested without any of them.
public struct TickerSources: Equatable, Sendable {
    /// Meetings starting this soon (or already under way) pin themselves.
    public static let pinLeadTime: TimeInterval = 5 * 60
    /// Meetings further out than this are not "live" yet and stay hidden.
    public static let meetingHorizon: TimeInterval = 60 * 60
    /// Claude usage only surfaces once a window is above this fraction.
    public static let usageThreshold: Double = 0.8

    public var events: [UpcomingEvent]
    public var isMusicPlaying: Bool
    public var focus: FocusTimer?
    public var tasksRemaining: Int
    /// Shared goals from the enabled modules, in tab order.
    public var progress: [ProgressItem]
    public var usage: ClaudeRateLimitSnapshot?
    public var pet: PetPresence?
    public var party: ProvidedParty?

    public init(
        events: [UpcomingEvent] = [],
        isMusicPlaying: Bool = false,
        focus: FocusTimer? = nil,
        tasksRemaining: Int = 0,
        progress: [ProgressItem] = [],
        usage: ClaudeRateLimitSnapshot? = nil,
        pet: PetPresence? = nil,
        party: ProvidedParty? = nil
    ) {
        self.events = events
        self.isMusicPlaying = isMusicPlaying
        self.focus = focus
        self.tasksRemaining = tasksRemaining
        self.progress = progress
        self.usage = usage
        self.pet = pet
        self.party = party
    }

    /// Every item that has something to say at `now`, in `TickerKind` order.
    ///
    /// Kinds missing from `enabled` and kinds with no data are skipped, so an
    /// empty result means the notch stays plain black.
    public func items(at now: Date, enabled: Set<TickerKind> = Set(TickerKind.allCases)) -> [TickerItem] {
        TickerKind.allCases.filter(enabled.contains).compactMap { item(for: $0, at: now) }
    }

    /// The earliest moment after `now` at which `items(at:enabled:)` can
    /// change from the clock alone: a meeting countdown ticking down a
    /// minute, a meeting entering the horizon or ending, a focus phase
    /// ending, a usage window resetting, or the pet dozing off. `nil` when nothing is pending.
    ///
    /// Lets the caller sleep until then instead of polling. A running focus
    /// clock's per-second change is left to the caller, which only needs it
    /// while that clock is on screen.
    public func nextChange(after now: Date, enabled: Set<TickerKind> = Set(TickerKind.allCases)) -> Date? {
        var dates: [Date] = []
        if enabled.contains(.meeting) {
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
        if enabled.contains(.focus), let endsAt = focus?.endsAt, endsAt > now {
            dates.append(endsAt)
        }
        if enabled.contains(.claudeUsage) {
            dates += [usage?.fiveHour?.resetsAt, usage?.sevenDay?.resetsAt].compactMap { $0 }.filter { $0 > now }
        }
        if enabled.contains(.pet), let sleepsAt = pet?.sleepsAt(focus: focus, after: now) {
            dates.append(sleepsAt)
        }
        return dates.min()
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
            guard let focus, focus.isRunning || focus.isPaused else { return nil }
            return .focus(phase: focus.phase, remaining: focus.remaining(at: now), isRunning: focus.isRunning)
        case .tasks:
            return tasksRemaining > 0 ? .tasks(remaining: tasksRemaining) : nil
        case .progress:
            // The first goal in tab order with work left; a finished goal
            // has nothing to say.
            return progress.first { !$0.isComplete }.map(TickerItem.progress)
        case .claudeUsage:
            let windows: [(TickerUsageWindow, Double)] = [
                (.fiveHour, Self.utilization(of: usage?.fiveHour, at: now)),
                (.weekly, Self.utilization(of: usage?.sevenDay, at: now)),
            ]
            // The fuller window is the more urgent one; ties favor the 5-hour
            // window because it resets sooner and is the one the user can act on.
            guard let worst = windows.max(by: { $0.1 < $1.1 }),
                  worst.1 > Self.usageThreshold else { return nil }
            return .claudeUsage(window: worst.0, utilization: worst.1)
        case .pet:
            guard let pet else { return nil }
            return .pet(TickerPet(profile: pet.profile, mood: pet.mood(focus: focus, at: now)))
        case .party:
            // Alone in a party there are no other pets to show.
            guard let party, party.memberCount > 1 else { return nil }
            return .party(TickerParty(pets: Array(party.pets.prefix(TickerParty.maxPets)),
                                      memberCount: party.memberCount))
        }
    }

    /// The window's utilization, or 0 once it has reset: the snapshot is only
    /// refreshed on demand, so after `resetsAt` its number no longer holds.
    private static func utilization(of window: ClaudeUsageWindow?, at now: Date) -> Double {
        guard let window else { return 0 }
        if let resetsAt = window.resetsAt, resetsAt <= now { return 0 }
        return window.utilization
    }
}
