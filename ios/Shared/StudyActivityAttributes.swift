import ActivityKit
import Foundation
import TabbiKitCore

/// A study session as a Live Activity: the Lock Screen banner and the
/// Dynamic Island while a phase runs or is paused.
///
/// Built in the app and drawn by the TabbiLiveActivity extension, so both
/// compile this file. Everything that changes during a session is in
/// `ContentState`; the system draws the countdown from its dates with
/// `Text(timerInterval:)`, so a running phase needs no updates at all.
struct StudyActivityAttributes: ActivityAttributes {
    /// The study pet as it looks when the session starts, drawn by the
    /// shared `PetRenderer` in the extension. A `PetProfile` is a few hundred
    /// bytes, well inside ActivityKit's 4 KB.
    var pet: PetProfile

    struct ContentState: Codable, Hashable, Sendable {
        /// How the clock moves, mirroring `ProvidedFocus.Clock`.
        enum Clock: Codable, Hashable, Sendable {
            /// A timed phase running from `start` (where it would have begun
            /// had it never paused) to `end`.
            case countdown(start: Date, end: Date)
            /// An open-ended phase (a Flowtime stretch) counting up.
            case countUp(since: Date)
            /// A paused phase, showing `shown` seconds left (or worked).
            case paused(shown: TimeInterval)
        }

        /// The phase as the app names it ("Focus", "Break", "Timer"),
        /// already localized.
        var phaseName: String
        var isBreak: Bool
        var clock: Clock
        /// The phase's length, for the paused progress bar; nil when it has none.
        var phaseLength: TimeInterval?
        /// What to say once the phase has run out ("Focus session done"),
        /// already localized.
        var doneLine: String
        /// Set on the final content of a phase that ran out while the app
        /// was away, which stays on the Lock Screen for a while.
        var isDone = false
        /// The Pet Cam is filming this focus block: the activity shows the
        /// camera recording (a REC dot and the countdown, nothing else).
        var filming = false

        /// When a running countdown ends; nil otherwise.
        var endsAt: Date? {
            if case .countdown(_, let end) = clock { return end }
            return nil
        }
    }
}

extension StudyActivityAttributes.ContentState {
    /// The Live Activity for `session` at `now`, or nil while it is idle
    /// (nothing to show, so the activity ends).
    init?(_ session: StudySession, at now: Date, filming: Bool = false) {
        guard session.runState != .idle else { return nil }
        let clock: Clock
        if let end = session.endsAt, let length = session.phaseDuration {
            clock = .countdown(start: end.addingTimeInterval(-length), end: end)
        } else if let since = session.runningSince {
            clock = .countUp(since: since)
        } else {
            clock = .paused(shown: session.remaining(at: now) ?? session.elapsed(at: now))
        }
        let filming = filming && session.phase == .focus
        let doneLine = if filming {
            "Tape ready"
        } else if session.phase.isBreak {
            String(localized: "Break's over", bundle: .tabbi)
        } else if session.method.kind == .timer {
            String(localized: "Session done. Nice work!", bundle: .tabbi)
        } else {
            String(localized: "Focus session done", bundle: .tabbi)
        }
        self.init(phaseName: StudyTimerFormat.phaseName(session.phase, method: session.method),
                  isBreak: session.phase.isBreak, clock: clock, phaseLength: session.phaseDuration, doneLine: doneLine,
                  filming: filming)
    }
}
