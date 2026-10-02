import Foundation

/// Every clip for one dressed pet, built once so a player never composes
/// frames while animating.
public struct PetClipSet: Hashable, Sendable {
    public let clips: [PetAnimation: PetClip]

    public init(breed: PetBreed, outfit: PetOutfit = .none, accessories: [PetAccessory] = []) {
        var clips: [PetAnimation: PetClip] = [:]
        for animation in PetAnimation.allCases {
            clips[animation] = PetComposer.clip(animation, for: breed, outfit: outfit, accessories: accessories)
        }
        self.clips = clips
    }

    public init(profile: PetProfile) {
        self.init(breed: profile.breed, outfit: profile.outfit, accessories: profile.accessories)
    }

    public subscript(animation: PetAnimation) -> PetClip {
        // Every case is built in init, so the lookup always succeeds.
        clips[animation]!
    }

    /// One-pass length of every clip, which is all `PetAnimator` needs.
    public var durations: [PetAnimation: TimeInterval] { clips.mapValues(\.duration) }

    /// The frame to draw for `playback` at `time`, or nil when the pet is
    /// tucked away inside the notch.
    public func frame(for playback: PetAnimator.Playback?, at time: TimeInterval) -> PetFrame? {
        guard let playback else { return nil }
        return self[playback.animation].frame(at: playback.elapsed(at: time))
    }
}

/// Decides which animation the pet plays and since when.
///
/// The pet is always somewhere (beside the notch, hanging out of it, or
/// hidden inside it) and has a resting animation for that place: idle with
/// random blinks, sleep, or the held last frame of peekIn. Events start
/// one-shot clips on top; when one finishes, the pet returns to rest at the
/// exact moment the clip ended, so timing never drifts with the frame rate.
///
/// The animator is a pure value driven by timestamps (any monotonic clock in
/// seconds) and a seeded random generator, so it is fully deterministic and
/// testable. Call `advance(to:)` before reading `playback` for a new time.
public struct PetAnimator: Hashable, Sendable {
    /// Where the pet is relative to the notch.
    public enum Place: Hashable, Sendable {
        /// Sitting beside the notch while the user studies.
        case beside
        /// Dangling from the notch's top edge by its front paws.
        case hanging
        /// Tucked inside the notch; nothing is drawn.
        case hidden
    }

    public enum Event: Hashable, Sendable {
        /// Get the user's attention: beside the notch the pet wakes and does
        /// the alert hop; from inside the notch it peeks out.
        case nudge
        /// A finished session: wakes the pet and plays celebrate.
        case celebrate
        /// Doze off (beside the notch only).
        case sleep
        /// Wake from dozing back to idle.
        case wake
        /// Come out of the notch and hang from its edge.
        case peekIn
        /// Climb back into the notch.
        case peekOut
        /// Cut straight to sitting beside the notch, awake.
        case appear
        /// Cut straight to hidden inside the notch.
        case disappear
    }

    /// The clip on screen and when it started.
    public struct Playback: Hashable, Sendable {
        public var animation: PetAnimation
        public var startedAt: TimeInterval

        public init(animation: PetAnimation, startedAt: TimeInterval) {
            self.animation = animation
            self.startedAt = startedAt
        }

        public func elapsed(at time: TimeInterval) -> TimeInterval { time - startedAt }
    }

    /// Seconds between blinks are drawn uniformly from this range, so the
    /// pet blinks often enough to feel alive but never mechanically.
    public static let blinkInterval: ClosedRange<TimeInterval> = 2.5...6

    public private(set) var place: Place
    public private(set) var isAsleep: Bool
    /// What to draw; nil while the pet is hidden inside the notch.
    public private(set) var playback: Playback?
    /// When the next idle blink starts, if the pet is idling.
    public private(set) var nextBlinkAt: TimeInterval?

    private let durations: [PetAnimation: TimeInterval]
    /// An event that arrived during a peek transition, applied once the
    /// transition ends so the pet never teleports mid-climb. Latest wins.
    private var pending: Event?
    private var random: SplitMix64

    public init(
        durations: [PetAnimation: TimeInterval], place: Place = .beside, asleep: Bool = false,
        at time: TimeInterval = 0, seed: UInt64 = 0
    ) {
        self.durations = durations
        self.place = place
        self.isAsleep = asleep && place == .beside
        self.random = SplitMix64(seed: seed)
        rest(at: time)
    }

    /// Whether a peek transition is playing and can't be interrupted.
    public func isTransitioning(at time: TimeInterval) -> Bool {
        guard let playback, playback.animation == .peekIn || playback.animation == .peekOut else { return false }
        return playback.elapsed(at: time) < duration(playback.animation)
    }

    /// Handles `event` at `time`. Returns false when the event doesn't apply
    /// where the pet is (for example celebrating while hidden). Events during
    /// a peek transition are deferred and count as accepted.
    @discardableResult
    public mutating func send(_ event: Event, at time: TimeInterval) -> Bool {
        advance(to: time)
        if isTransitioning(at: time) {
            pending = event
            return true
        }
        return apply(event, at: time)
    }

    /// Finishes every one-shot clip and starts every blink due by `time`.
    public mutating func advance(to time: TimeInterval) {
        while let current = playback {
            let animation = current.animation
            let end = current.startedAt + duration(animation)
            if animation == .idle, let blinkAt = nextBlinkAt, blinkAt <= time {
                playback = Playback(animation: .blink, startedAt: blinkAt)
                nextBlinkAt = nil
                continue
            }
            guard !animation.loops, end <= time else { break }
            switch animation {
            case .peekIn:
                // Hanging is peekIn's held last frame; only a deferred event moves on.
                guard let event = pending else { return }
                pending = nil
                apply(event, at: end)
            case .peekOut:
                playback = nil
                if let event = pending {
                    pending = nil
                    apply(event, at: end)
                }
            default:
                rest(at: end)
            }
        }
    }

    @discardableResult
    private mutating func apply(_ event: Event, at time: TimeInterval) -> Bool {
        switch event {
        case .appear:
            place = .beside
            isAsleep = false
            rest(at: time)
        case .disappear:
            place = .hidden
            isAsleep = false
            rest(at: time)
        case .sleep:
            guard place == .beside, !isAsleep else { return false }
            isAsleep = true
            // A running alert or celebration plays out before the pet dozes.
            if !isPlayingOneShot(at: time) { rest(at: time) }
        case .wake:
            guard place == .beside, isAsleep else { return false }
            isAsleep = false
            if !isPlayingOneShot(at: time) { rest(at: time) }
        case .nudge:
            switch place {
            case .beside:
                // Never cut a celebration short to nag.
                if playback?.animation == .celebrate, isPlayingOneShot(at: time) { return false }
                isAsleep = false
                play(.alert, at: time)
            case .hidden:
                return apply(.peekIn, at: time)
            case .hanging:
                return false
            }
        case .celebrate:
            guard place == .beside else { return false }
            isAsleep = false
            play(.celebrate, at: time)
        case .peekIn:
            guard place == .hidden else { return false }
            place = .hanging
            play(.peekIn, at: time)
        case .peekOut:
            guard place == .hanging else { return false }
            place = .hidden
            play(.peekOut, at: time)
        }
        return true
    }

    /// Alert or celebrate still running (blinks don't count: they yield).
    private func isPlayingOneShot(at time: TimeInterval) -> Bool {
        guard let playback, playback.animation == .alert || playback.animation == .celebrate else { return false }
        return playback.elapsed(at: time) < duration(playback.animation)
    }

    private mutating func play(_ animation: PetAnimation, at time: TimeInterval) {
        playback = Playback(animation: animation, startedAt: time)
        nextBlinkAt = nil
    }

    /// Starts the resting animation for the current place at `time`.
    private mutating func rest(at time: TimeInterval) {
        nextBlinkAt = nil
        switch place {
        case .hidden:
            playback = nil
        case .hanging:
            // Started one clip-length ago, so the held last frame shows at once.
            playback = Playback(animation: .peekIn, startedAt: time - duration(.peekIn))
        case .beside where isAsleep:
            playback = Playback(animation: .sleep, startedAt: time)
        case .beside:
            playback = Playback(animation: .idle, startedAt: time)
            nextBlinkAt = time + random.next(in: Self.blinkInterval)
        }
    }

    private func duration(_ animation: PetAnimation) -> TimeInterval {
        durations[animation] ?? 0
    }
}

/// A tiny seeded generator (SplitMix64) so the animator stays a value type
/// with reproducible blink timing.
struct SplitMix64: Hashable, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) / Double(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
