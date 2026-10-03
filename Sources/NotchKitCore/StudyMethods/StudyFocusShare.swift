import Foundation

extension StudySession {
    /// The session as the shared focus timer (`ModuleProvision.focus`), so
    /// the closed notch's focus preview and any module that follows focus
    /// (such as the pet coach) see a study block like any other timer.
    ///
    /// Only a session under way is shared: an idle one has nothing to show
    /// and would only hide another module's timer. Phases with no length
    /// (an open-ended Flowtime stretch, an Anki sprint counting cards) are
    /// not shared either, since a focus timer always counts down; the
    /// break that follows them is. Focus and question review both read as
    /// focus, and either break as rest.
    public func sharedFocusTimer(at now: Date) -> FocusTimer? {
        guard runState != .idle, let phaseDuration, let remaining = remaining(at: now) else { return nil }
        let isFocus = !phase.isBreak
        let config = FocusTimerConfig(
            focusDuration: isFocus ? phaseDuration : method.duration(of: .focus) ?? lastFocusWorked,
            restDuration: isFocus ? method.duration(of: .shortBreak) ?? phaseDuration : phaseDuration
        )
        let runState: FocusRunState = if let endsAt { .running(endsAt: endsAt) } else { .paused(remaining: remaining) }
        return FocusTimer(
            phase: isFocus ? .focus : .rest,
            runState: runState,
            config: config,
            completedFocusCount: completedFocusCount
        )
    }
}
