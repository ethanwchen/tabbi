import Foundation

/// The kinds of live activity the closed notch can preview, in rotation order.
public enum TickerKind: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case meeting
    case nowPlaying
    case focus
    case tasks
    case claudeUsage

    public var id: String { rawValue }

    /// Label for the per-item toggle in Settings.
    public var title: String {
        switch self {
        case .meeting: "Next meeting"
        case .nowPlaying: "Now playing"
        case .focus: "Focus timer"
        case .tasks: "Tasks left today"
        case .claudeUsage: "Claude usage above 80%"
        }
    }

    /// The panel a click on this preview opens.
    public var module: ModuleID {
        switch self {
        case .meeting, .focus, .tasks: .planner
        case .nowPlaying: .spotify
        case .claudeUsage: .claudeUsage
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

/// One live activity the closed notch can show beside the hardware cutout.
public enum TickerItem: Hashable, Sendable {
    case meeting(TickerMeeting)
    /// Music is playing; the app renders artwork and the equalizer itself.
    case nowPlaying
    case focus(phase: FocusPhase, remaining: TimeInterval, isRunning: Bool)
    case tasks(remaining: Int)
    case claudeUsage(window: TickerUsageWindow, utilization: Double)

    public var kind: TickerKind {
        switch self {
        case .meeting: .meeting
        case .nowPlaying: .nowPlaying
        case .focus: .focus
        case .tasks: .tasks
        case .claudeUsage: .claudeUsage
        }
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
    public var usage: ClaudeRateLimitSnapshot?

    public init(
        events: [UpcomingEvent] = [],
        isMusicPlaying: Bool = false,
        focus: FocusTimer? = nil,
        tasksRemaining: Int = 0,
        usage: ClaudeRateLimitSnapshot? = nil
    ) {
        self.events = events
        self.isMusicPlaying = isMusicPlaying
        self.focus = focus
        self.tasksRemaining = tasksRemaining
        self.usage = usage
    }

    /// Every item that has something to say at `now`, in `TickerKind` order.
    ///
    /// Kinds missing from `enabled` and kinds with no data are skipped, so an
    /// empty result means the notch stays plain black.
    public func items(at now: Date, enabled: Set<TickerKind> = Set(TickerKind.allCases)) -> [TickerItem] {
        TickerKind.allCases.filter(enabled.contains).compactMap { item(for: $0, at: now) }
    }

    private func item(for kind: TickerKind, at now: Date) -> TickerItem? {
        switch kind {
        case .meeting:
            guard let event = UpcomingEvent.upNext(from: events, at: now, limit: 1).first,
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
