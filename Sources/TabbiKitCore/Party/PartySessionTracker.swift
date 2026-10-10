import Foundation

/// One stay in a Party shared session, for points, the activity log and
/// the celebration: either it ran to the session's end with the user in
/// it, or it was cut short (the user stepped out, or the host ended it
/// early) and pays the minutes studied.
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
    /// Whether the session ran to its end with the user in it. A stay cut
    /// short earns its minutes without the completion and team bonuses
    /// (`PetPointsRules.sharedPoints`), and gets no team celebration.
    public var finished: Bool

    public init(method: String, joinedAt: Date, endedAt: Date, friendCount: Int, hostName: String? = nil,
                finished: Bool = true) {
        self.method = method
        self.joinedAt = joinedAt
        self.endedAt = max(endedAt, joinedAt)
        self.friendCount = max(friendCount, 0)
        self.hostName = hostName
        self.finished = finished
    }

    /// Whole minutes the user stayed for.
    public var minutes: Int { Int(endedAt.timeIntervalSince(joinedAt) / 60) }

    /// The activity log entry: a focus stretch from Party, so streaks and
    /// insights count shared study like any other. A stay cut short is
    /// logged as skipped, so it adds minutes but not a finished session.
    public func activityRecord(source: ModuleID) -> ActivityRecord? {
        guard endedAt.timeIntervalSince(joinedAt) >= StudyPhaseRecord.minimumLoggedDuration else { return nil }
        return ActivityRecord(
            source: source, kind: .focusCompleted, start: joinedAt, end: endedAt,
            quantity: endedAt.timeIntervalSince(joinedAt) / 60, unit: .minutes,
            metadata: [ActivityMetadata.method: method, ActivityMetadata.outcome: outcome.rawValue,
                       Self.friendsKey: String(friendCount)]
        )
    }

    private var outcome: StudyPhaseOutcome { finished ? .completed : .skipped }

    /// The activity metadata key for how many friends studied along.
    public static let friendsKey = "friends"
}

/// Watches the shared session the user is in (`PartyState.session(at:)`)
/// and reports each stay in it once it ends.
///
/// Every member's app runs its own tracker, so the host and each member
/// are paid alike. A stay that lasts to the end is `finished`; one cut
/// short (the user stepped out, the host ended it early, or a new session
/// replaced it) reports the time studied until then. A user who joins late
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
    /// returns the stay in the one being watched when it has just ended or
    /// the user left it.
    public mutating func observe(_ session: ProvidedPartySession?, at now: Date) -> PartySessionCompletion? {
        if let session, let stay, stay.session.startedAt == session.startedAt {
            self.stay?.session = session
            self.stay?.friendCount = max(stay.friendCount, session.friendCount)
            return nil
        }
        let ended = stay
        stay = session.map { Stay(session: $0, joinedAt: max(now, $0.startedAt), friendCount: $0.friendCount) }
        return ended.map {
            let finished = $0.session.endsAt.timeIntervalSince(now) <= Self.endTolerance
            return PartySessionCompletion(method: $0.session.method, joinedAt: $0.joinedAt,
                                          endedAt: finished ? $0.session.endsAt : now, friendCount: $0.friendCount,
                                          hostName: $0.session.hostName, finished: finished)
        }
    }
}
