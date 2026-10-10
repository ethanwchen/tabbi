import Foundation

/// When the coach overlay's picture next changes, so it redraws only then.
///
/// Every redraw of the overlay is a full SwiftUI update of its window
/// (about 4 ms of CPU). A 30 fps clock for the whole scene redrew the
/// standing pet 30 times a second through its 12 s of talking, while its
/// idle frames change only a few times a second. Walking still moves the
/// pet every frame; standing, peeking and talking follow the clips' own
/// frame boundaries. Dates land a hair after each change, so rounding can
/// never show the old frame.
public enum PetCoachRedraw {
    /// How often a walking pet moves: 64 pt/s at 30 fps is about 2 pt a step.
    public static let walkFrameRate: Double = 30

    static let lag: TimeInterval = 0.001
}

extension PetCoachStroll {
    /// The next redraw after `date`: every walking frame, each frame change
    /// of the `arrival` clip and then the idle loop while talking, and the
    /// moments the pet sets off, arrives and turns back. Nil once the pet is
    /// home. `clips` must hold the pet's `.idle` and `arrival` clips.
    public func nextRedraw(after date: Date, clips: PetClipSet, arrival: PetAnimation,
                           walkFrameRate: Double = PetCoachRedraw.walkFrameRate) -> Date? {
        let step = 1 / max(walkFrameRate, 1)
        // Still tucked under the notch before the start: nothing moves yet.
        if date < startedAt { return startedAt.addingTimeInterval(PetCoachRedraw.lag) }
        switch phase(at: date) {
        case .walkingOut:
            return min(date.addingTimeInterval(step), arrivesAt.addingTimeInterval(PetCoachRedraw.lag))
        case .talking:
            let elapsed = date.timeIntervalSince(arrivesAt)
            let arrivalClip = clips[arrival]
            let boundary: TimeInterval?
            if elapsed < arrivalClip.duration {
                boundary = arrivalClip.nextFrameBoundary(after: elapsed) ?? arrivalClip.duration
            } else {
                boundary = clips[.idle].nextFrameBoundary(after: elapsed - arrivalClip.duration)
                    .map { $0 + arrivalClip.duration }
            }
            let frame = boundary.map { arrivesAt.addingTimeInterval($0 + PetCoachRedraw.lag) }
            let turn = turnsBackAt.addingTimeInterval(PetCoachRedraw.lag)
            return frame.map { min($0, turn) } ?? turn
        case .walkingBack:
            return min(date.addingTimeInterval(step), endsAt.addingTimeInterval(PetCoachRedraw.lag))
        case .finished:
            return nil
        }
    }
}

extension PetCoachGlance {
    /// The next redraw after `date`: each frame change of the peek clips,
    /// the moment the pet starts pulling back up, and its exit. Nil once
    /// it's back inside the notch. The hold shows `peekIn`'s last frame, so
    /// nothing redraws while the pet just looks.
    public func nextRedraw(after date: Date, clips: PetClipSet) -> Date? {
        let lag = PetCoachRedraw.lag
        let elapsed = date.timeIntervalSince(startedAt)
        if elapsed < 0 { return startedAt.addingTimeInterval(lag) }
        guard elapsed < duration else { return nil }
        let leavesAt = enter + hold
        let boundary: TimeInterval
        if elapsed < leavesAt {
            let next = clips[.peekIn].nextFrameBoundary(after: elapsed) ?? leavesAt
            boundary = min(next, leavesAt)
        } else {
            let next = clips[.peekOut].nextFrameBoundary(after: elapsed - leavesAt).map { $0 + leavesAt } ?? duration
            boundary = min(next, duration)
        }
        return startedAt.addingTimeInterval(boundary + lag)
    }
}
