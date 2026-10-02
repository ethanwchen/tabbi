import Foundation

/// A pixel position inside a frame (top-left origin, in sprite pixels).
public struct PetPoint: Hashable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

/// How the sitting pet holds itself in one frame. Poses are small offsets
/// from the plain sitting frame, so every costume follows along for free.
public struct PetPose: Hashable, Sendable {
    public enum Eyes: Hashable, Sendable {
        case open
        /// A quick blink: flat lines.
        case closed
        /// Asleep: soft downward curves.
        case sleepy
        /// Celebrating: "^" arches.
        case happy
    }

    public var eyes: Eyes
    /// Pixels the head sinks into the shoulders (breathing, dozing).
    public var headDrop: Int
    /// Pixels the whole pet rises off the baseline (hops).
    public var lift: Int

    public init(eyes: Eyes = .open, headDrop: Int = 0, lift: Int = 0) {
        self.eyes = eyes
        self.headDrop = headDrop
        self.lift = lift
    }
}

/// Every animation a pet can play. Each one is a list of frames with
/// per-frame durations (see `PetClip`).
public enum PetAnimation: String, CaseIterable, Codable, Sendable {
    /// Slow breathing while the user studies. Loops.
    case idle
    /// A single quick blink, played now and then on top of idle.
    case blink
    /// Holding still, sitting upright. Loops.
    case sit
    /// Dozing with drifting "z"s. Loops.
    case sleep
    /// Trotting toward the left, side-on with the face to the viewer. Loops;
    /// mirror the frames to walk right.
    case walk
    /// A play bow: chest down, paws forward, rump and tail up, then back to
    /// standing. Side-on like `walk`, facing left.
    case stretch
    /// Hanging head first out of the notch's top edge.
    case peekIn
    /// The reverse of `peekIn`: pulling back up into the notch.
    case peekOut
    /// A double bounce to get attention; frames carry a speech-bubble anchor.
    case alert
    /// A happy hop with a rising heart when a session is done.
    case celebrate

    /// Whether the clip repeats forever or stops on its last frame.
    public var loops: Bool {
        switch self {
        case .idle, .sit, .sleep, .walk: true
        case .blink, .stretch, .peekIn, .peekOut, .alert, .celebrate: false
        }
    }
}

/// One frame of an animation.
public struct PetFrame: Hashable, Sendable {
    public var canvas: PetCanvas
    /// Seconds this frame stays on screen.
    public var duration: TimeInterval
    /// Where a speech bubble's tail should point, in frame pixels; set on
    /// frames that want to say something (alert).
    public var bubbleAnchor: PetPoint?

    public init(canvas: PetCanvas, duration: TimeInterval, bubbleAnchor: PetPoint? = nil) {
        self.canvas = canvas
        self.duration = duration
        self.bubbleAnchor = bubbleAnchor
    }
}

/// A playable animation: frames plus timing.
public struct PetClip: Hashable, Sendable {
    public let animation: PetAnimation
    public let frames: [PetFrame]

    public init(animation: PetAnimation, frames: [PetFrame]) {
        precondition(!frames.isEmpty, "A clip needs at least one frame")
        self.animation = animation
        self.frames = frames
    }

    public var loops: Bool { animation.loops }

    /// Timestamps arrive as `start + boundary` and are turned back into
    /// elapsed time by subtraction, which can land a hair before the
    /// boundary. Treating anything this close as past it keeps
    /// `frameIndex` and `nextFrameBoundary` in agreement.
    private static let rounding: TimeInterval = 1e-9

    /// Length of one pass through every frame, in seconds.
    public var duration: TimeInterval { frames.reduce(0) { $0 + $1.duration } }

    /// Whether a one-shot clip has played to the end after `elapsed`
    /// seconds. Looping clips never finish.
    public func isFinished(at elapsed: TimeInterval) -> Bool {
        !loops && elapsed >= duration
    }

    /// The frame to show `elapsed` seconds after the clip started. Looping
    /// clips wrap around; one-shot clips hold their last frame.
    public func frameIndex(at elapsed: TimeInterval) -> Int {
        guard elapsed > 0 else { return 0 }
        let total = duration
        var time = loops && total > 0 ? elapsed.truncatingRemainder(dividingBy: total) : elapsed
        for (index, frame) in frames.enumerated() {
            if time < frame.duration - Self.rounding { return index }
            time -= frame.duration
        }
        // Past the end: a loop has wrapped (rounding left `time` on its end).
        return loops ? 0 : frames.count - 1
    }

    public func frame(at elapsed: TimeInterval) -> PetFrame {
        frames[frameIndex(at: elapsed)]
    }

    /// When the shown frame next changes, in seconds since the clip started,
    /// strictly after `elapsed`. A one-shot clip's last boundary is its end;
    /// after that (and for single-frame loops) nothing changes, so nil. Lets
    /// a player redraw exactly on frame changes instead of polling.
    public func nextFrameBoundary(after elapsed: TimeInterval) -> TimeInterval? {
        let elapsed = max(0, elapsed)
        let total = duration
        guard total > 0 else { return nil }
        var base: TimeInterval = 0
        var offset = elapsed
        if loops {
            guard frames.count > 1 else { return nil }
            let cycles = (elapsed / total).rounded(.down)
            base = cycles * total
            offset = elapsed - base
        }
        var boundary: TimeInterval = 0
        for frame in frames {
            boundary += frame.duration
            if offset < boundary - Self.rounding { return base + boundary }
        }
        // Rounding put `offset` on the loop's end: the next change is one frame in.
        return loops ? base + total + frames[0].duration : nil
    }
}

extension PetComposer {
    /// Builds `animation` for a dressed breed. Composition is cheap (a few
    /// 32x32 grids), but callers that play clips repeatedly should keep the
    /// result instead of rebuilding it every frame.
    public static func clip(
        _ animation: PetAnimation, for breed: PetBreed,
        outfit: PetOutfit = .none, accessories: [PetAccessory] = []
    ) -> PetClip {
        func pose(_ pose: PetPose) -> Composed {
            compose(breed, pose: pose, outfit: outfit, accessories: accessories)
        }
        func frame(_ value: PetPose, _ duration: TimeInterval) -> PetFrame {
            PetFrame(canvas: pose(value).canvas, duration: duration)
        }

        let frames: [PetFrame]
        switch animation {
        case .sit:
            frames = [frame(PetPose(), 1)]

        case .idle:
            // Inhale holds a little longer than exhale, like real breathing.
            frames = [frame(PetPose(), 1.1), frame(PetPose(headDrop: 1), 0.9)]

        case .blink:
            frames = [frame(PetPose(eyes: .closed), 0.14)]

        case .sleep:
            let dozing = pose(PetPose(eyes: .sleepy, headDrop: 2))
            let breathing = pose(PetPose(eyes: .sleepy, headDrop: 1))
            let top = dozing.headTopRight
            // A small "z" appears by the ear, grows, and drifts up and away.
            let small = PetPoint(x: top.x + 3, y: top.y - 2)
            let large = PetPoint(x: frameSize - 4, y: top.y - 9)
            frames = [
                PetFrame(canvas: dozing.canvas, duration: 0.8),
                PetFrame(canvas: breathing.canvas.adding(EffectArt.zSmall, at: small), duration: 0.8),
                PetFrame(canvas: dozing.canvas.adding(EffectArt.zSmall, at: small)
                    .adding(EffectArt.zLarge, at: large), duration: 0.8),
                PetFrame(canvas: breathing.canvas.adding(EffectArt.zLarge, at: large), duration: 0.8),
            ]

        case .walk:
            frames = WalkArt.cycle.indices.map { step in
                let composed = compose(breed, pose: PetPose(), outfit: outfit, accessories: accessories,
                                       stance: .walking(step: step))
                return PetFrame(canvas: composed.canvas, duration: 0.15)
            }

        case .stretch:
            // Ease down into the bow, hold it with a tail wag and happy
            // eyes, then rise back up.
            let steps: [(Int, Int, PetPose.Eyes, TimeInterval)] = [
                (0, 0, .open, 0.15), (1, 0, .open, 0.1), (2, 0, .happy, 0.1), (3, 0, .happy, 0.35),
                (3, 1, .happy, 0.35), (3, 0, .happy, 0.35), (2, 0, .open, 0.1), (1, 0, .open, 0.1), (0, 0, .open, 0.3),
            ]
            frames = steps.map { depth, wag, eyes, duration in
                let composed = compose(breed, pose: PetPose(eyes: eyes), outfit: outfit, accessories: accessories,
                                       stance: .stretching(depth: depth, wag: wag))
                return PetFrame(canvas: composed.canvas, duration: duration)
            }

        case .alert:
            // Two hops, the second smaller, then hold so the bubble can be read.
            frames = [(0, 0.06), (2, 0.1), (0, 0.08), (1, 0.08), (0, 0.6)].map { lift, duration in
                let composed = pose(PetPose(lift: lift))
                return PetFrame(canvas: composed.canvas, duration: duration,
                                bubbleAnchor: PetPoint(x: composed.headTopRight.x, y: composed.headTopRight.y))
            }

        case .celebrate:
            let lifts: [(Int, TimeInterval)] = [(0, 0.08), (2, 0.08), (3, 0.16), (2, 0.08), (0, 0.1), (0, 0.3), (0, 0.4)]
            frames = lifts.enumerated().map { index, step in
                var canvas = pose(PetPose(eyes: .happy, lift: step.0)).canvas
                // The heart pops in at the top of the hop and floats up
                // beside the head; sparkles twinkle on the other side.
                if index >= 2 {
                    let heartY = 8 - (index - 2) * 2
                    canvas = canvas.adding(EffectArt.heart, at: PetPoint(x: frameSize - EffectArt.heart.width, y: heartY))
                }
                if index == 2 || index == 4 {
                    canvas = canvas.adding(EffectArt.sparkle, at: PetPoint(x: 1, y: index - 1))
                }
                return PetFrame(canvas: canvas, duration: step.1)
            }

        case .peekIn, .peekOut:
            // Dangling from the notch by the front paws: the head lowers into
            // view from beyond the top edge and settles with a tiny bounce,
            // chin on `hangingChinRow`.
            let hanging = compose(breed, pose: PetPose(), outfit: outfit, accessories: accessories, stance: .hanging)
            let hidden = -(hangingChinRow + 2)
            let steps: [(Int, TimeInterval)] = [(hidden, 0.08), (-14, 0.08), (-8, 0.08), (-3, 0.1), (1, 0.1), (0, 0.5)]
            let sliding = steps.map { offset, duration in
                PetFrame(canvas: hanging.canvas.shifted(x: 0, y: offset), duration: duration)
            }
            frames = animation == .peekIn ? sliding : sliding.reversed()
        }
        return PetClip(animation: animation, frames: frames)
    }
}

extension PetComposer {
    /// Where the chin rests once a peeking pet is fully out of the notch.
    static let hangingChinRow = 20
}

extension PetCanvas {
    /// A copy with an effect painted behind the pet (no outline): effect
    /// pixels only fill transparent space, so a heart or "z" drifting past
    /// a hat never hides part of the pet.
    func adding(_ grid: SpriteGrid, at point: PetPoint) -> PetCanvas {
        var effect = PetCanvas(width: width, height: height)
        effect.stamp(grid, x: point.x, y: point.y)
        var copy = self
        for y in 0..<height {
            for x in 0..<width where copy[x, y] == nil { copy[x, y] = effect[x, y] }
        }
        return copy
    }
}
