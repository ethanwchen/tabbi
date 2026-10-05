import Foundation

/// How the pet in the Study panel's corner follows the timer: awake and
/// breathing while the clock runs (studying along, or stretching its legs on
/// a break), dozing while the timer is paused or hasn't started, and a happy
/// hop whenever a focus block is finished.
public enum StudyPetCue {
    /// Whether the pet should be asleep for `session`.
    public static func isDozing(_ session: StudySession) -> Bool {
        !session.isRunning
    }

    /// The animator events that take the pet from `old` to `new`, in order.
    ///
    /// A finished focus block (Pomodoro, sprint goal, ended Flowtime stretch)
    /// celebrates; if the timer then stops, the pet dozes off once the hop
    /// has played (`PetAnimator` lets a celebration finish first). Otherwise
    /// the pet only reacts when the clock starts (`wake`) or stops (`sleep`).
    /// Resetting or switching methods never celebrates.
    public static func events(from old: StudySession, to new: StudySession) -> [PetAnimator.Event] {
        let finishedBlock = new.method.kind == old.method.kind
            && new.completedFocusCount > old.completedFocusCount
        let dozing = isDozing(new)
        if finishedBlock { return dozing ? [.celebrate, .sleep] : [.celebrate] }
        guard dozing != isDozing(old) else { return [] }
        return [dozing ? .sleep : .wake]
    }
}
