import Foundation

/// The "leave now" moment before a meeting: when it comes within
/// `TickerSources.pinLeadTime` (about five minutes), the closed notch's
/// meeting preview glows gently for `duration`, with a Join button when the
/// event has a call.
///
/// A value, like `PetCheer`, so the ticker can tell when it is over without
/// a timer of its own.
public struct MeetingNudge: Hashable, Sendable {
    /// Long enough for a few soft breaths, short enough to stay polite.
    public static let duration: TimeInterval = 4

    /// The meeting it is for (`MeetingNudgeWatch.key(for:)`).
    public let key: String
    public let startedAt: Date

    public init(key: String, startedAt: Date) {
        self.key = key
        self.startedAt = startedAt
    }

    public var endsAt: Date { startedAt.addingTimeInterval(Self.duration) }

    /// Whether the glow is on screen at `date`; a clock set back before the
    /// start shows nothing.
    public func isShowing(at date: Date) -> Bool {
        date >= startedAt && date < endsAt
    }
}

/// Remembers which meetings already had their nudge, so each meeting pulses
/// at most once, however often the ticker refreshes or the notch opens and
/// closes. A moved meeting is a new one and gets a nudge of its own.
public struct MeetingNudgeWatch: Equatable, Sendable {
    /// Each nudged meeting's key and start, dropped once it has started.
    private var nudged: [String: Date] = [:]

    public init() {}

    /// The meeting's identity for nudging: its event and its start, so
    /// rescheduling it counts as a new meeting.
    public static func key(for event: UpcomingEvent) -> String {
        "\(event.id)@\(event.start.timeIntervalSinceReferenceDate)"
    }

    /// Starts the nudge for `sources`' imminent meeting at `now` and records
    /// it, or returns nil: no meeting starts within the lead time, or this
    /// one already had its nudge.
    public mutating func nudge(for sources: TickerSources, at now: Date) -> MeetingNudge? {
        nudged = nudged.filter { $0.value > now }
        guard let event = sources.imminentMeeting(at: now) else { return nil }
        let key = Self.key(for: event)
        guard nudged[key] == nil else { return nil }
        nudged[key] = event.start
        return MeetingNudge(key: key, startedAt: now)
    }
}
