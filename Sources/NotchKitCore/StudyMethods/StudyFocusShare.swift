import Foundation

extension StudySession {
    /// The session as the shared focus clock (`ModuleProvision.focus`), so
    /// the closed notch's focus preview and any module that follows focus
    /// (such as the pet coach) see a study block like any other timer.
    ///
    /// Only a session under way is shared: an idle one has nothing to show
    /// and would only hide another module's timer. Phases with no length
    /// (an open-ended Flowtime stretch, an Anki sprint counting cards) count
    /// up. Focus and question review both read as focus, and either break
    /// as rest. The value never depends on `now` beyond the session's own
    /// state, so it is not republished every second.
    public func sharedFocus(by source: ModuleID, isDeep: Bool = false, at now: Date) -> ProvidedFocus? {
        guard runState != .idle else { return nil }
        let isFocus = !phase.isBreak
        let clock: ProvidedFocus.Clock = if let endsAt {
            .countdown(endsAt: endsAt)
        } else if let runningSince {
            .countUp(since: runningSince)
        } else {
            .paused(shown: remaining(at: now) ?? elapsed(at: now))
        }
        return ProvidedFocus(
            source: source,
            phase: isFocus ? .focus : .rest,
            label: StudyTimerFormat.phaseName(phase, method: method),
            clock: clock,
            phaseLength: phaseDuration,
            focusLength: isFocus ? phaseDuration : method.duration(of: .focus) ?? lastFocusWorked,
            completedFocusCount: completedFocusCount,
            isDeep: isDeep
        )
    }
}
