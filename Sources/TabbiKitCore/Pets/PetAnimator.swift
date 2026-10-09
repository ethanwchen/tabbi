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

    /// The next moment after `time` when the drawn frame can change: a frame
    /// boundary in the current clip or the next idle blink. Nil when the
    /// picture holds until an event arrives (hidden, or hanging from the
    /// notch). `animator` must already be advanced to `time`.
    public func nextChange(for animator: PetAnimator, after time: TimeInterval) -> TimeInterval? {
        guard let playback = animator.playback else { return nil }
        let boundary = self[playback.animation]
            .nextFrameBoundary(after: playback.elapsed(at: time))
            .map { playback.startedAt + $0 }
        let blink = animator.nextBlinkAt.flatMap { $0 > time ? $0 : nil }
        return [boundary, blink].compactMap { $0 }.min()
    }

    /// The still picture for `animator` under Reduce Motion: the playing
    /// clip's `stillFrame`, with blinks drawn as the idle pose they
    /// interrupt, so only real state changes (asleep, typing, an alert)
    /// change the picture. Nil while the pet is inside the notch.
    /// `animator` must already be advanced to the time drawn.
    public func stillFrame(for animator: PetAnimator) -> PetFrame? {
        guard let playback = animator.playback else { return nil }
        return self[playback.animation == .blink ? .idle : playback.animation].stillFrame
    }

    /// The next moment after `time` when `stillFrame(for:)` can change: the
    /// end of a one-shot clip (alert, celebrate, stretch, yawn, a peek),
    /// after which the pet rests again. Nil while it rests, since a still
    /// pet only changes on events. `animator` must already be advanced to
    /// `time`.
    public func nextStillChange(for animator: PetAnimator, after time: TimeInterval) -> TimeInterval? {
        guard let playback = animator.playback, !playback.animation.loops, playback.animation != .blink
        else { return nil }
        let end = playback.startedAt + self[playback.animation].duration
        return end > time ? end : nil
    }
}

/// Decides which animation the pet plays and since when.
///
/// The pet is always somewhere (beside the notch, hanging out of it, or
/// hidden inside it) and has a resting animation for that place: idle with
/// random blinks, sleep, or the held last frame of peekIn. Awake beside the
/// notch it also follows what the user is doing (`Activity`): it types on
/// its laptop through a focus block, sips coffee on a break, and yawns when
/// a long focus stretch ends. Events start
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

    /// What the user is doing, which picks the resting animation of a pet
    /// awake beside the notch.
    public enum Activity: Hashable, Sendable {
        /// No session running: idle with blinks.
        case free
        /// A focus block is running: typing on the tiny laptop.
        case studying
        /// A break is running: sipping the tiny coffee mug.
        case onBreak

        var restingAnimation: PetAnimation {
            switch self {
            case .free: .idle
            case .studying: .typing
            case .onBreak: .coffee
            }
        }

        /// The activity the closed notch's pet follows for its mood.
        public init(_ mood: PetMood) {
            switch mood {
            case .studying: self = .studying
            case .onBreak: self = .onBreak
            case .awake, .asleep: self = .free
            }
        }
    }

    public enum Event: Hashable, Sendable {
        /// Get the user's attention: beside the notch the pet wakes and does
        /// the alert hop; from inside the notch it peeks out.
        case nudge
        /// A finished session: wakes the pet and plays celebrate.
        case celebrate
        /// Doze off (beside the notch only).
        case sleep
        /// Wake from dozing: the pet stretches, then idles.
        case wake
        /// Come out of the notch and hang from its edge.
        case peekIn
        /// Climb back into the notch.
        case peekOut
        /// Cut straight to sitting beside the notch, awake.
        case appear
        /// Cut straight to hidden inside the notch.
        case disappear
        /// The user started or stopped studying or a break. Leaving a focus
        /// stretch of at least `longSession` makes the pet yawn first.
        case activity(Activity)
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

    /// Focus this long in one go earns a yawn when it ends: longer than one
    /// standard Pomodoro, so only a real stretch of work makes the pet tired.
    public static let longSession: TimeInterval = 45 * 60

    public private(set) var place: Place
    public private(set) var isAsleep: Bool
    public private(set) var activity: Activity
    /// When the current activity started, so leaving a long focus stretch
    /// can be told from leaving a short one.
    public private(set) var activitySince: TimeInterval
    /// What to draw; nil while the pet is hidden inside the notch.
    public private(set) var playback: Playback?
    /// When the next idle blink starts, if the pet is idling.
    public private(set) var nextBlinkAt: TimeInterval?

    private let durations: [PetAnimation: TimeInterval]
    /// An event that arrived during a peek transition, applied once the
    /// transition ends so the pet never teleports mid-climb. Latest wins.
    private var pending: Event?
    /// A long focus stretch ended while another one-shot clip played; the
    /// pet yawns as soon as that clip ends.
    private var yawnsNext = false
    private var random: SplitMix64

    public init(
        durations: [PetAnimation: TimeInterval], place: Place = .beside, asleep: Bool = false,
        activity: Activity = .free, activitySince: TimeInterval? = nil,
        at time: TimeInterval = 0, seed: UInt64 = 0
    ) {
        self.durations = durations
        self.place = place
        self.isAsleep = asleep && place == .beside
        self.activity = activity
        self.activitySince = activitySince ?? time
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
                if yawnsNext, place == .beside, animation != .yawn {
                    yawnsNext = false
                    play(.yawn, at: end)
                } else {
                    rest(at: end)
                }
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
            yawnsNext = false
            rest(at: time)
        case .sleep:
            guard place == .beside, !isAsleep else { return false }
            isAsleep = true
            // A running alert or celebration plays out before the pet dozes.
            if !isPlayingOneShot(at: time) { rest(at: time) }
        case .wake:
            guard place == .beside, isAsleep else { return false }
            isAsleep = false
            // Waking on its own (not by a nudge) earns a slow stretch first.
            if !isPlayingOneShot(at: time) { play(.stretch, at: time) }
        case .activity(let next):
            guard next != activity else { return false }
            let tired = activity == .studying && time - activitySince >= Self.longSession
            activity = next
            activitySince = time
            guard place == .beside, !isAsleep else { return true }
            if isPlayingOneShot(at: time) {
                // Let a celebration play out, then yawn.
                yawnsNext = yawnsNext || tired
            } else if tired {
                play(.yawn, at: time)
            } else {
                rest(at: time)
            }
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

    /// Alert, celebrate, the wake-up stretch or a yawn still running (blinks
    /// don't count: they yield).
    private func isPlayingOneShot(at time: TimeInterval) -> Bool {
        guard let playback, [.alert, .celebrate, .stretch, .yawn].contains(playback.animation) else { return false }
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
        case .beside where activity != .free:
            playback = Playback(animation: activity.restingAnimation, startedAt: time)
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
