import SwiftUI
import TabbiKitCore

/// Plays one pet: owns its prebuilt clips and the `PetAnimator` deciding
/// what is on screen. Views draw it with `PetView`; study features drive
/// it with `send(_:)` (nudge when the user drifts, celebrate a finished
/// session, and so on).
///
/// The animator clock is `Date.timeIntervalSinceReferenceDate`, so events
/// and redraws share one timeline.
@MainActor
public final class PetPlayer: ObservableObject {
    public private(set) var profile: PetProfile
    public private(set) var clips: PetClipSet
    /// Deliberately not `@Published`: drawing advances it many times a
    /// second, and that must not invalidate views. Only events, which change
    /// the redraw schedule, notify observers.
    private var animator: PetAnimator

    public init(
        profile: PetProfile, place: PetAnimator.Place = .beside, asleep: Bool = false,
        at date: Date = .now, seed: UInt64 = .random(in: .min ... .max)
    ) {
        self.profile = profile
        clips = PetClipSet(profile: profile)
        animator = PetAnimator(durations: clips.durations, place: place, asleep: asleep,
                               at: date.timeIntervalSinceReferenceDate, seed: seed)
    }

    public var place: PetAnimator.Place { animator.place }
    public var palette: PetPalette { profile.palette }

    /// Sends `event` to the animator; returns false when it doesn't apply
    /// where the pet is (see `PetAnimator.send`).
    @discardableResult
    public func send(_ event: PetAnimator.Event, at date: Date = .now) -> Bool {
        objectWillChange.send()
        return animator.send(event, at: date.timeIntervalSinceReferenceDate)
    }

    /// Swaps in a new look (breed, colors, outfit) without moving the pet.
    public func update(profile: PetProfile, at date: Date = .now) {
        guard profile != self.profile else { return }
        objectWillChange.send()
        let time = date.timeIntervalSinceReferenceDate
        animator.advance(to: time)
        self.profile = profile
        clips = PetClipSet(profile: profile)
        // Durations can differ between looks, so restart in the same place.
        animator = PetAnimator(durations: clips.durations, place: animator.place,
                               asleep: animator.isAsleep, at: time, seed: .random(in: .min ... .max))
    }

    /// The frame to draw at `date`, or nil while the pet is inside the notch.
    public func frame(at date: Date) -> PetFrame? {
        let time = date.timeIntervalSinceReferenceDate
        animator.advance(to: time)
        return clips.frame(for: animator.playback, at: time)
    }

    /// Redraw dates for `TimelineView`: exactly when the frame changes, so an
    /// idle pet costs a few redraws a second instead of a 60 Hz loop.
    public var schedule: PetFrameSchedule { PetFrameSchedule(animator: animator, clips: clips) }
}

/// A `TimelineSchedule` that yields one date per frame change, simulated on
/// a copy of the animator. It ends when the picture holds (hidden, or
/// hanging from the notch); the next event publishes a fresh schedule.
public struct PetFrameSchedule: TimelineSchedule {
    let animator: PetAnimator
    let clips: PetClipSet

    /// Redraw a hair after each change so rounding can't show the old frame.
    private static let lag: TimeInterval = 0.001

    public func entries(from startDate: Date, mode: Mode) -> AnyIterator<Date> {
        var animator = animator
        var next: Date? = startDate
        return AnyIterator {
            guard let date = next else { return nil }
            let time = date.timeIntervalSinceReferenceDate
            animator.advance(to: time)
            next = clips.nextChange(for: animator, after: time)
                .map { Date(timeIntervalSinceReferenceDate: $0 + Self.lag) }
            return date
        }
    }
}
