import Foundation

/// A focus or break clock some module runs, as the rest of the app sees it.
/// The `FocusState` role of a module.
///
/// Neutral on purpose: Today's Pomodoro (`FocusTimer`) and Study's
/// `StudySession` both map into it, including phases with no length (a
/// Flowtime stretch or a card sprint counts up), so the ticker, the pet,
/// the coach and the party read one shape without knowing which engine runs
/// the clock. The value only changes when the clock's state changes, never
/// every second: a running clock carries a date to count from.
public struct ProvidedFocus: Hashable, Sendable {
    /// Where the clock stands.
    public enum Clock: Hashable, Sendable {
        /// Set up but not started.
        case idle
        /// Counting down to a wall-clock end.
        case countdown(endsAt: Date)
        /// An open-ended phase counting up from a wall-clock start (pauses
        /// already taken out).
        case countUp(since: Date)
        /// Stopped part-way; `shown` is the frozen clock: time left for a
        /// phase with a length, time worked for an open-ended one.
        case paused(shown: TimeInterval)
    }

    /// The module running the clock; set by `ProviderSnapshot` when merging.
    public var source: ModuleID
    /// Focus or break; review and long breaks map onto these two.
    public var phase: FocusPhase
    /// The engine's own name for the phase, e.g. "Focus", "Review" or
    /// "Long break".
    public var label: String
    public var clock: Clock
    /// Full length of the current phase; nil while it counts up.
    public var phaseLength: TimeInterval?
    /// How long a focus phase runs with this clock: the current one's length
    /// during focus, otherwise the planned or last worked one. Sizes the
    /// points a finished session earns; nil when unknown.
    public var focusLength: TimeInterval?
    /// Focus phases finished so far; only ever grows while the same clock
    /// runs, so followers can tell a completion from a skip.
    public var completedFocusCount: Int
    /// The user asked for deep focus with this clock (Study's switch), so
    /// followers such as the pet coach save their nudges for it.
    public var isDeep: Bool
    /// The module logs a focus phase cut short (stopped, skipped, or ended
    /// by sleep or quit) in the activity log, with its minutes, so the pet
    /// pays that time from the log (`PetCloset.credit(_:)`) rather than from
    /// this clock going idle, which can't tell a stop from another module's
    /// clock taking over.
    public var logsEarlyEnds: Bool

    public init(
        source: ModuleID,
        phase: FocusPhase,
        label: String? = nil,
        clock: Clock,
        phaseLength: TimeInterval?,
        focusLength: TimeInterval? = nil,
        completedFocusCount: Int = 0,
        isDeep: Bool = false,
        logsEarlyEnds: Bool = false
    ) {
        self.source = source
        self.phase = phase
        self.label = label ?? FocusTimerFormat.phaseName(phase)
        self.clock = clock
        self.phaseLength = phaseLength
        self.focusLength = focusLength ?? (phase == .focus ? phaseLength : nil)
        self.completedFocusCount = max(completedFocusCount, 0)
        self.isDeep = isDeep
        self.logsEarlyEnds = logsEarlyEnds
    }

    public var isRunning: Bool {
        switch clock {
        case .countdown, .countUp: true
        case .idle, .paused: false
        }
    }

    public var isPaused: Bool {
        if case .paused = clock { return true }
        return false
    }

    /// Running or paused: the user is mid-session.
    public var isActive: Bool { clock != .idle }

    /// Whether the clock counts up instead of down.
    public var countsUp: Bool { phaseLength == nil }

    /// When a countdown runs out; nil otherwise.
    public var endsAt: Date? {
        if case .countdown(let endsAt) = clock { return endsAt }
        return nil
    }

    /// Time left at `now`, never negative; nil for a phase that counts up.
    public func remaining(at now: Date) -> TimeInterval? {
        guard let phaseLength else { return nil }
        switch clock {
        case .idle: return phaseLength
        case .countdown(let endsAt): return max(endsAt.timeIntervalSince(now), 0)
        case .countUp(let since): return max(phaseLength - now.timeIntervalSince(since), 0)
        case .paused(let shown): return shown
        }
    }

    /// Time worked in the current phase at `now`, excluding pauses.
    public func elapsed(at now: Date) -> TimeInterval {
        switch clock {
        case .idle: return 0
        case .countUp(let since): return max(now.timeIntervalSince(since), 0)
        case .paused(let shown): return phaseLength.map { max($0 - shown, 0) } ?? shown
        case .countdown:
            guard let phaseLength, let remaining = remaining(at: now) else { return 0 }
            return max(phaseLength - remaining, 0)
        }
    }

    /// What a clock face shows at `now`: time left, or time worked for a
    /// phase that counts up.
    public func shownTime(at now: Date) -> TimeInterval {
        remaining(at: now) ?? elapsed(at: now)
    }
}

extension FocusTimer {
    /// The timer as the shared focus clock (`ModuleProvision.focus`). Its
    /// owner logs a focus phase cut short (`FocusStop.activityRecord`), so
    /// the clock says so.
    public func provided(by source: ModuleID) -> ProvidedFocus {
        let clock: ProvidedFocus.Clock = switch runState {
        case .idle: .idle
        case .running(let endsAt): .countdown(endsAt: endsAt)
        case .paused(let remaining): .paused(shown: remaining)
        }
        return ProvidedFocus(source: source, phase: phase, clock: clock, phaseLength: phaseDuration,
                             focusLength: config.focusDuration, completedFocusCount: completedFocusCount,
                             logsEarlyEnds: true)
    }
}
