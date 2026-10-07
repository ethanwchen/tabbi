import Foundation

/// A Party shared session that ran to its end with the user in it, for
/// points, the activity log and the celebration.
public struct PartySessionCompletion: Hashable, Sendable {
    /// The study method id the host picked, e.g. `pomodoro`.
    public var method: String
    /// When the user's stay began: the session's start, or later when they
    /// opened Tabbi or rejoined after it started.
    public var joinedAt: Date
    public var endedAt: Date
    /// The most friends who studied along at once.
    public var friendCount: Int
    /// Who started it; nil when the user did.
    public var hostName: String?

    public init(method: String, joinedAt: Date, endedAt: Date, friendCount: Int, hostName: String? = nil) {
        self.method = method
        self.joinedAt = joinedAt
        self.endedAt = max(endedAt, joinedAt)
        self.friendCount = max(friendCount, 0)
        self.hostName = hostName
    }

    /// Whole minutes the user stayed for.
    public var minutes: Int { Int(endedAt.timeIntervalSince(joinedAt) / 60) }

    /// The activity log entry: a completed focus stretch from Party, so
    /// streaks and insights count shared study like any other.
    public func activityRecord(source: ModuleID) -> ActivityRecord? {
        guard endedAt.timeIntervalSince(joinedAt) >= StudyPhaseRecord.minimumLoggedDuration else { return nil }
        return ActivityRecord(
            source: source, kind: .focusCompleted, start: joinedAt, end: endedAt,
            quantity: endedAt.timeIntervalSince(joinedAt) / 60, unit: .minutes,
            metadata: [ActivityMetadata.method: method, ActivityMetadata.outcome: "completed",
                       Self.friendsKey: String(friendCount)]
        )
    }

    /// The activity metadata key for how many friends studied along.
    public static let friendsKey = "friends"
}

/// Watches the shared session the user is in (`PartyState.session(at:)`)
/// and reports when one runs to its end.
///
/// Only a stay that lasts to the end counts: a session the host ended
/// early or the user stepped out of just goes away. A user who joins late
/// or rejoins is credited from then on, never for time they were not there.
public struct PartySessionTracker: Hashable, Sendable {
    private struct Stay: Hashable, Sendable {
        var session: ProvidedPartySession
        var joinedAt: Date
        var friendCount: Int
    }

    private var stay: Stay?

    /// How early the session may drop off and still count as finished,
    /// for timers that fire a moment before the end.
    public static let endTolerance: TimeInterval = 2

    public init() {}

    /// Observes the session the user is in at `now` (nil when none) and
    /// returns the completion when the one being watched has just ended.
    public mutating func observe(_ session: ProvidedPartySession?, at now: Date) -> PartySessionCompletion? {
        if let session, let stay, stay.session.startedAt == session.startedAt {
            self.stay?.session = session
            self.stay?.friendCount = max(stay.friendCount, session.friendCount)
            return nil
        }
        let finished = stay.flatMap { $0.session.endsAt.timeIntervalSince(now) <= Self.endTolerance ? $0 : nil }
        stay = session.map { Stay(session: $0, joinedAt: max(now, $0.startedAt), friendCount: $0.friendCount) }
        return finished.map {
            PartySessionCompletion(method: $0.session.method, joinedAt: $0.joinedAt, endedAt: $0.session.endsAt,
                                   friendCount: $0.friendCount, hostName: $0.session.hostName)
        }
    }
}
