import Foundation

extension FocusActivity {
    /// What a study session asks of focus mode. With deep focus off the
    /// Study tab never touches it; with it on, a running focus or review
    /// phase turns on the focus sound and Do Not Disturb, a break or pause
    /// interrupts them, and an idle session ends them.
    public init(_ session: StudySession, deepFocus: Bool) {
        guard deepFocus else {
            self = .idle
            return
        }
        switch session.runState {
        case .running: self = session.phase.isBreak ? .interrupted : .focusing
        case .paused: self = .interrupted
        case .idle: self = .idle
        }
    }

    /// One activity for several timers that can drive focus mode at once
    /// (the Focus timer and the Study timer): focusing if any is focusing,
    /// else interrupted if any is mid-session, else idle. So ending one
    /// timer never turns off the sound or Do Not Disturb another still needs.
    public static func combined<S: Sequence>(_ activities: S) -> FocusActivity where S.Element == FocusActivity {
        var result = FocusActivity.idle
        for activity in activities {
            switch activity {
            case .focusing: return .focusing
            case .interrupted: result = .interrupted
            case .idle: break
            }
        }
        return result
    }
}
