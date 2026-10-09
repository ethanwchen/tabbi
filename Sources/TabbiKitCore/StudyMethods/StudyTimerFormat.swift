import Foundation

/// What the Study tab's dial shows in its center.
public struct StudyDialReadout: Hashable, Sendable {
    /// The big number: time left, time worked for open-ended focus, or cards
    /// answered for a sprint, e.g. "24:13", "1:02:40", "37".
    public let value: String
    /// Small text under the value, e.g. "Focus", "of 100 cards", "Break · Paused".
    /// Empty for a plain Timer that is not paused: the tab and the method
    /// card already say "Timer", so the dial shows just the time.
    public let caption: String
    /// Whether the value counts down (for the numeric text transition).
    public let countsDown: Bool

    public init(value: String, caption: String, countsDown: Bool) {
        self.value = value
        self.caption = caption
        self.countsDown = countsDown
    }
}

/// Labels for the Study tab, kept out of the view so they're testable and
/// every method reads the same way.
public enum StudyTimerFormat {
    /// Clock text that grows an hour field only when needed:
    /// "4:05", "52:00", "1:30:00". Rounds up, so a phase never shows 0:00
    /// while it still has a fraction of a second left.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = seconds.isFinite ? Int(max(seconds, 0).rounded(.up)) : 0
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Phase name, e.g. "Focus", "Timer", "Review", "Break", "Long break".
    public static func phaseName(_ phase: StudyPhaseKind, method: StudyMethod) -> String {
        switch phase {
        case .focus: method.kind == .timer ? "Timer" : method.cardGoal == nil ? "Focus" : "Sprint"
        case .review: "Review"
        case .shortBreak: "Break"
        case .longBreak: "Long break"
        }
    }

    /// The dial's center for `session` at `now`.
    public static func readout(_ session: StudySession, at now: Date) -> StudyDialReadout {
        let phase = phaseName(session.phase, method: session.method)
        let paused = session.runState == .paused
        func caption(_ base: String) -> String { paused ? "\(base) · Paused" : base }

        if session.method.kind == .timer, let remaining = session.remaining(at: now) {
            return StudyDialReadout(value: clock(remaining), caption: paused ? "Paused" : "", countsDown: true)
        }
        if let remaining = session.remaining(at: now) {
            return StudyDialReadout(value: clock(remaining), caption: caption(phase), countsDown: true)
        }
        if let goal = session.method.cardGoal {
            return StudyDialReadout(value: "\(session.cardsDone)",
                                    caption: caption("of \(goal) cards"), countsDown: false)
        }
        // Open-ended Flowtime focus counts up.
        return StudyDialReadout(value: clock(session.elapsed(at: now)),
                                caption: caption(session.runState == .idle ? "Flow" : "In flow"),
                                countsDown: false)
    }

    /// Where the session stands, e.g. "Round 2 of 4" for a method with a long
    /// break, "3 rounds done", or nil before the first round finishes and
    /// for the Timer, which has no rounds.
    public static func roundLabel(_ session: StudySession) -> String? {
        // A plain countdown has no rounds to count.
        guard session.method.hasBreaks else { return nil }
        let done = session.completedFocusCount
        if let every = session.method.longBreak?.every {
            // Count the round in progress; after a long break start a new set.
            let round = session.phase == .focus ? done % every + 1 : (done - 1) % every + 1
            return done == 0 && session.phase != .focus ? nil : "Round \(max(round, 1)) of \(every)"
        }
        guard done > 0 else { return nil }
        return done == 1 ? "1 round done" : "\(done) rounds done"
    }

    /// Title of the primary button for the session's state.
    public static func primaryAction(_ session: StudySession) -> String {
        switch session.runState {
        case .running:
            if session.phase == .focus, case .openEnded = session.method.focus { return "Take a break" }
            return "Pause"
        case .paused:
            return "Resume"
        case .idle:
            switch session.phase {
            case .focus:
                if session.method.kind == .timer { return "Start timer" }
                return session.method.cardGoal == nil ? "Start focus" : "Start sprint"
            case .review: return "Start review"
            case .shortBreak, .longBreak: return "Start break"
            }
        }
    }

    /// Time studied as a short label: "0 min", "45 min", "1 h 5 min", read
    /// the way Today and the closed notch show the same daily goal.
    public static func studied(minutes: Int) -> String {
        ProgressItem.amount(max(minutes, 0), unit: ProgressItem.minutesUnit)
    }

    /// Points as a signed label for a day's tally: "+79 pts", "+1 pt", "0 pts".
    public static func points(_ points: Int) -> String {
        let points = max(points, 0)
        let unit = points == 1 ? "pt" : "pts"
        return points == 0 ? "0 pts" : "+\(points.formatted()) \(unit)"
    }
}
