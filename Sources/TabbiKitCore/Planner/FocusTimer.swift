import Foundation

/// Which half of a Pomodoro cycle the focus timer is in.
public enum FocusPhase: String, Codable, Hashable, Sendable {
    case focus
    case rest

    /// The phase that follows this one.
    public var next: FocusPhase { self == .focus ? .rest : .focus }
}

/// Phase lengths for the focus timer. Defaults to the classic 25/5 split.
public struct FocusTimerConfig: Codable, Hashable, Sendable {
    public var focusDuration: TimeInterval
    public var restDuration: TimeInterval

    public init(focusDuration: TimeInterval = 25 * 60, restDuration: TimeInterval = 5 * 60) {
        self.focusDuration = max(focusDuration, 1)
        self.restDuration = max(restDuration, 1)
    }

    public func duration(of phase: FocusPhase) -> TimeInterval {
        phase == .focus ? focusDuration : restDuration
    }
}

/// Whether the clock is moving.
public enum FocusRunState: Codable, Hashable, Sendable {
    /// Not started; the full phase duration remains.
    case idle
    /// Counting down to a wall-clock end date.
    case running(endsAt: Date)
    /// Stopped part-way with this much time left.
    case paused(remaining: TimeInterval)
}

/// A phase that ran to its end, reported so the app can notify the user.
public struct FocusPhaseCompletion: Hashable, Sendable {
    public let phase: FocusPhase
    public let endedAt: Date

    public init(phase: FocusPhase, endedAt: Date) {
        self.phase = phase
        self.endedAt = endedAt
    }
}

/// Pomodoro state machine for the Today panel's focus card.
///
/// Time is derived from a wall-clock end date rather than a ticking counter,
/// so the timer stays correct while the notch is closed, the app is busy, or
/// the Mac sleeps. Callers pass `now` explicitly, which keeps every
/// transition deterministic and testable.
///
/// When a focus phase ends the break starts on its own (that's the point of
/// the reminder); when a break ends the timer waits idle for the user to
/// start the next focus phase, so it never runs on while they're away.
public struct FocusTimer: Codable, Hashable, Sendable {
    public private(set) var phase: FocusPhase
    public private(set) var runState: FocusRunState
    public var config: FocusTimerConfig
    /// Checklist item the user is focusing on, shown as "Focusing on: ...".
    public var linkedItemID: UUID?
    /// Focus phases finished by running out (skips don't count), across sessions.
    public private(set) var completedFocusCount: Int

    public init(config: FocusTimerConfig = FocusTimerConfig(), linkedItemID: UUID? = nil) {
        phase = .focus
        runState = .idle
        self.config = config
        self.linkedItemID = linkedItemID
        completedFocusCount = 0
    }

    /// A timer in a given state, for modules that run their own clock (such
    /// as Study) and share it through `ModuleProvision.focus`.
    public init(phase: FocusPhase, runState: FocusRunState, config: FocusTimerConfig, completedFocusCount: Int = 0) {
        self.phase = phase
        self.runState = runState
        self.config = config
        linkedItemID = nil
        self.completedFocusCount = max(completedFocusCount, 0)
    }

    public var isRunning: Bool {
        if case .running = runState { return true }
        return false
    }

    public var isPaused: Bool {
        if case .paused = runState { return true }
        return false
    }

    /// Length of the current phase.
    public var phaseDuration: TimeInterval { config.duration(of: phase) }

    /// Time left in the current phase at `now`, never negative.
    public func remaining(at now: Date) -> TimeInterval {
        switch runState {
        case .idle: return phaseDuration
        case .running(let endsAt): return max(endsAt.timeIntervalSince(now), 0)
        case .paused(let remaining): return remaining
        }
    }

    /// Fraction of the current phase already elapsed, 0...1, for the ring.
    public func progress(at now: Date) -> Double {
        let fraction = 1 - remaining(at: now) / phaseDuration
        return min(max(fraction, 0), 1)
    }

    /// When the running phase ends, for scheduling a notification.
    public var endsAt: Date? {
        if case .running(let endsAt) = runState { return endsAt }
        return nil
    }

    /// Starts from idle or resumes from pause. No-op while running.
    public mutating func start(at now: Date) {
        switch runState {
        case .idle: runState = .running(endsAt: now.addingTimeInterval(phaseDuration))
        case .paused(let remaining): runState = .running(endsAt: now.addingTimeInterval(remaining))
        case .running: break
        }
    }

    /// Freezes the remaining time. No-op unless running.
    ///
    /// Call `advance(to:)` first so a phase that already ended isn't paused
    /// with zero seconds left.
    public mutating func pause(at now: Date) {
        guard case .running = runState else { return }
        runState = .paused(remaining: remaining(at: now))
    }

    /// Back to an idle focus phase at full length. Keeps the linked item.
    public mutating func reset() {
        phase = .focus
        runState = .idle
    }

    /// Ends the current phase early and moves to the next one.
    ///
    /// The next phase keeps running if the timer was running, so skipping a
    /// break while in flow drops straight into the next focus block. Skipped
    /// phases don't count as completed and produce no notification.
    public mutating func skip(at now: Date) {
        let wasRunning = isRunning
        phase = phase.next
        runState = wasRunning ? .running(endsAt: now.addingTimeInterval(phaseDuration)) : .idle
    }

    /// Applies every phase end that has passed by `now` and reports them.
    ///
    /// Usually returns zero or one completion. After a long sleep it can
    /// return a focus end followed by the auto-started break's end, each
    /// stamped with its real wall-clock end time.
    @discardableResult
    public mutating func advance(to now: Date) -> [FocusPhaseCompletion] {
        var completions: [FocusPhaseCompletion] = []
        while case .running(let endsAt) = runState, endsAt <= now {
            completions.append(FocusPhaseCompletion(phase: phase, endedAt: endsAt))
            switch phase {
            case .focus:
                completedFocusCount += 1
                phase = .rest
                runState = .running(endsAt: endsAt.addingTimeInterval(phaseDuration))
            case .rest:
                phase = .focus
                runState = .idle
            }
        }
        return completions
    }
}

/// Short strings for the focus timer in Today and the Focus tab.
public enum FocusTimerFormat {
    /// Countdown as "25:00", "4:59", or "0:00".
    ///
    /// Seconds round up so the display shows the full length the moment the
    /// timer starts and only reads "0:00" once the phase is really over.
    public static func clock(_ remaining: TimeInterval) -> String {
        let total = Int(max(remaining, 0).rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Phase label, e.g. "Focus" or "Break".
    public static func phaseName(_ phase: FocusPhase) -> String {
        phase == .focus ? "Focus" : "Break"
    }

    /// One line on where the timer stands, shown when no task is linked,
    /// e.g. "25 min, no distractions" before a focus session starts.
    public static func status(_ timer: FocusTimer) -> String {
        switch (timer.phase, timer.runState) {
        case (.rest, _): "Step away for a bit"
        case (.focus, .idle): "\(Int(timer.config.focusDuration / 60)) min, no distractions"
        case (.focus, .paused): "Paused"
        case (.focus, .running): "Heads down"
        }
    }

    /// Notification copy for a finished phase.
    public static func completionMessage(_ completion: FocusPhaseCompletion, config: FocusTimerConfig) -> (title: String, body: String) {
        let minutes = Int((config.duration(of: completion.phase.next) / 60).rounded())
        switch completion.phase {
        case .focus: return ("Focus session done", "Time for a \(minutes)-minute break.")
        case .rest: return ("Break's over", "Ready for another \(minutes)-minute focus session?")
        }
    }
}
