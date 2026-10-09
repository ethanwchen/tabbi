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
        /// Squeezed shut: "> <", for a yawn.
        case squeezed
    }

    /// The mouth, drawn over the face's own mouth when it opens.
    public enum Mouth: Hashable, Sendable {
        /// The face as drawn: a closed smile or a panting tongue.
        case closed
        /// A small round "o", the start and end of a yawn.
        case open
        /// A big yawn with the tongue showing.
        case wide
    }

    /// Something held in front of the sitting pet for the study moments.
    public enum Prop: Hashable, Sendable {
        /// Typing on a tiny laptop. `tap` lifts the left (-1) or right (1)
        /// paw off the keys; 0 rests both.
        case laptop(tap: Int)
        /// A coffee mug in both paws. `raise` is 0 at the chest, 1 on the
        /// way up, 2 at the mouth for a sip.
        case mug(raise: Int)
        /// A toy on the floor in front: a ball of yarn for cats, a ball for
        /// dogs. `roll` moves it that many pixels to the left as it rolls
        /// away, `bounce` lifts a ball off the floor, and `bat` puts the
        /// left front paw on top of it.
        case toy(roll: Int, bounce: Int, bat: Bool)
    }

    /// A front paw lifted off the floor, beside the head or to the face.
    public enum Gesture: Hashable, Sendable {
        /// Waving hello: `swing` 0 leans the paw out, 1 brings it back in.
        case wave(swing: Int)
        /// Grooming: `reach` 0 holds the paw at the chest, 1 at the mouth
        /// for a lick, 2 up over the cheek to wash the face.
        case groom(reach: Int)
    }

    public var eyes: Eyes
    public var mouth: Mouth
    public var prop: Prop?
    public var gesture: Gesture?
    /// Pixels the tip of a sitting pet's tail leans out to the side (0 at
    /// rest), for the tail swish. Tailless breeds wiggle a stub instead.
    public var tailSwing: Int
    /// Pixels the head sinks into the shoulders (breathing, dozing);
    /// negative tips it back (a yawn).
    public var headDrop: Int
    /// Pixels the whole pet rises off the baseline (hops).
    public var lift: Int

    public init(
        eyes: Eyes = .open, mouth: Mouth = .closed, prop: Prop? = nil, gesture: Gesture? = nil,
        tailSwing: Int = 0, headDrop: Int = 0, lift: Int = 0
    ) {
        self.eyes = eyes
        self.mouth = mouth
        self.prop = prop
        self.gesture = gesture
        self.tailSwing = tailSwing
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
    /// A slow, sleepy yawn: the head tips back, the eyes squeeze shut and
    /// the mouth opens wide, then the pet settles back down.
    case yawn
    /// Two springy hops with happy eyes and dust puffs on landing: plain
    /// joy, with no heart (that is `celebrate`, for a finished session).
    case hop
    /// Typing away on a tiny laptop, with a pause now and then to read the
    /// screen: the pet studying along while a focus session runs. Loops.
    case typing
    /// Sipping a tiny coffee: steam curls up while the pet holds the mug,
    /// then it raises it for a slow, happy sip. Loops, for breaks.
    case coffee
    /// A friendly wave: one front paw goes up beside the head and swings
    /// back and forth a few times with happy eyes.
    case wave
    /// Grooming: a few licks of a raised paw, then a wipe over the cheek,
    /// eyes closed in concentration.
    case groom
    /// A lazy tail swish while sitting: the tail sweeps out to the side and
    /// back twice. Tailless breeds wiggle a stub by the haunch.
    case tailSwish
    /// A deep nap curled up on the floor: lying down with the head resting
    /// on the tail wrapped round in front, the back rising with each slow
    /// breath while "z"s drift up. Loops; `sleep` is the sitting doze.
    case nap
    /// Playing: a pat sends a ball of yarn (cats) or a ball (dogs) rolling
    /// away, the pet watches it, and it comes back to be caught. A ball
    /// bounces on the way.
    case play

    /// Whether the clip repeats forever or stops on its last frame.
    public var loops: Bool {
        switch self {
        case .idle, .sit, .sleep, .walk, .typing, .coffee, .nap: true
        case .blink, .stretch, .peekIn, .peekOut, .alert, .celebrate, .yawn, .hop, .wave, .groom, .tailSwish, .play: false
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

    /// The one frame a still pet shows for this clip under Reduce Motion: a
    /// one-shot clip's last frame, where it settles (the alert keeps its
    /// bubble, celebrate its heart), and a loop's first, except that sleep
    /// and nap hold the frame with both "z"s, so a frozen pet reads as asleep.
    public var stillFrame: PetFrame {
        switch animation {
        case .sleep, .nap: frames[min(2, frames.count - 1)]
        default: loops ? frames[0] : frames[frames.count - 1]
        }
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

        case .nap:
            // Slower than the sitting doze: a deep breath every two seconds,
            // with a "z" rising from the ear and drifting off like `sleep`.
            func curled(_ breath: Int) -> Composed {
                compose(breed, pose: PetPose(eyes: .sleepy), outfit: outfit, accessories: accessories,
                        stance: .curled(breath: breath))
            }
            let resting = curled(0)
            let breathing = curled(1)
            let top = resting.headTopRight
            let small = PetPoint(x: top.x + 3, y: top.y - 2)
            let large = PetPoint(x: frameSize - 4, y: top.y - 9)
            frames = [
                PetFrame(canvas: resting.canvas, duration: 1),
                PetFrame(canvas: breathing.canvas.adding(EffectArt.zSmall, at: small), duration: 1),
                PetFrame(canvas: resting.canvas.adding(EffectArt.zSmall, at: small)
                    .adding(EffectArt.zLarge, at: large), duration: 1),
                PetFrame(canvas: breathing.canvas.adding(EffectArt.zLarge, at: large), duration: 1),
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

        case .yawn:
            // Tip back and open up slowly, hold the big yawn, then close
            // with a contented squint before the eyes open again.
            frames = [
                frame(PetPose(), 0.25),
                frame(PetPose(eyes: .squeezed, mouth: .open, headDrop: -1), 0.18),
                frame(PetPose(eyes: .squeezed, mouth: .wide, headDrop: -1), 0.9),
                frame(PetPose(eyes: .squeezed, mouth: .open, headDrop: -1), 0.16),
                frame(PetPose(eyes: .sleepy), 0.45),
                frame(PetPose(eyes: .sleepy, headDrop: 1), 0.35),
                frame(PetPose(), 0.3),
            ]

        case .hop:
            // Crouch, spring up, squash on landing with a puff of dust, and
            // again a little lower. Short frames keep it bouncy.
            let steps: [(PetPose, Bool, TimeInterval)] = [
                (PetPose(eyes: .happy, headDrop: 1), false, 0.1),
                (PetPose(eyes: .happy, lift: 2), false, 0.06),
                (PetPose(eyes: .happy, lift: 3), false, 0.12),
                (PetPose(eyes: .happy, lift: 2), false, 0.06),
                (PetPose(eyes: .happy, headDrop: 1), true, 0.1),
                (PetPose(eyes: .happy, lift: 2), false, 0.08),
                (PetPose(eyes: .happy, lift: 1), false, 0.06),
                (PetPose(eyes: .happy, headDrop: 1), true, 0.1),
                (PetPose(eyes: .happy), false, 0.35),
                (PetPose(), false, 0.2),
            ]
            frames = steps.map { value, dust, duration in
                var canvas = pose(value).canvas
                // Puffs on the floor just outside the paws (the bottom row,
                // so a wide tail higher up doesn't push them away).
                let floor = frameSize - 1 - value.lift
                let paws = (0..<frameSize).filter { canvas[$0, floor] != nil }
                if dust, let left = paws.first, let right = paws.last {
                    let y = frameSize - EffectArt.dustLeft.height
                    canvas = canvas
                        .adding(EffectArt.dustLeft, at: PetPoint(x: left - EffectArt.dustLeft.width, y: y))
                        .adding(EffectArt.dustRight, at: PetPoint(x: right + 1, y: y))
                }
                return PetFrame(canvas: canvas, duration: duration)
            }

        case .typing:
            // A burst of alternating taps, then a pause to read the screen.
            let taps: [(Int, Int, TimeInterval)] = [
                (-1, 0, 0.12), (0, 0, 0.1), (1, 0, 0.12), (0, 0, 0.1), (-1, 0, 0.12), (0, 0, 0.1),
                (1, 0, 0.12), (0, 0, 0.1), (-1, 0, 0.12), (0, 1, 0.7), (0, 1, 0.5),
            ]
            frames = taps.map { tap, drop, duration in
                frame(PetPose(prop: .laptop(tap: tap), headDrop: drop), duration)
            }

        case .coffee:
            // Hold the mug while the steam curls, then a slow sip with the
            // eyes closed, and a happy "ahh" on the way back down.
            let steps: [(Int, PetPose.Eyes, Int?, TimeInterval)] = [
                (0, .open, 0, 0.45), (0, .open, 1, 0.45), (0, .open, 0, 0.45), (0, .open, 1, 0.45),
                (1, .open, nil, 0.12), (2, .closed, nil, 0.9), (1, .happy, nil, 0.12),
                (0, .happy, 0, 0.5), (0, .open, 1, 0.45),
            ]
            frames = steps.map { raise, eyes, steam, duration in
                let composed = pose(PetPose(eyes: eyes, prop: .mug(raise: raise)))
                var canvas = composed.canvas
                if let steam, let top = composed.mugTop {
                    let wisp = PropArt.steam[steam]
                    // Painted over the chest, not behind the pet like other effects.
                    canvas.stamp(wisp, x: top.x + 1, y: top.y - wisp.height)
                }
                return PetFrame(canvas: canvas, duration: duration)
            }

        case .wave:
            // Up goes the paw, three swings out and back, and down again.
            let steps: [(PetPose, TimeInterval)] = [
                (PetPose(gesture: .wave(swing: 1)), 0.12),
                (PetPose(eyes: .happy, gesture: .wave(swing: 0)), 0.22),
                (PetPose(eyes: .happy, gesture: .wave(swing: 1)), 0.18),
                (PetPose(eyes: .happy, gesture: .wave(swing: 0)), 0.22),
                (PetPose(eyes: .happy, gesture: .wave(swing: 1)), 0.18),
                (PetPose(eyes: .happy, gesture: .wave(swing: 0)), 0.3),
                (PetPose(eyes: .happy), 0.25),
                (PetPose(), 0.2),
            ]
            frames = steps.map { frame($0.0, $0.1) }

        case .groom:
            // Lift the paw, three quick licks, two strokes over the cheek
            // with the head bent into them, then a contented look.
            let steps: [(PetPose, TimeInterval)] = [
                (PetPose(gesture: .groom(reach: 0)), 0.15),
                (PetPose(eyes: .closed, mouth: .open, gesture: .groom(reach: 1)), 0.18),
                (PetPose(eyes: .closed, gesture: .groom(reach: 0)), 0.12),
                (PetPose(eyes: .closed, mouth: .open, gesture: .groom(reach: 1)), 0.18),
                (PetPose(eyes: .closed, gesture: .groom(reach: 0)), 0.12),
                (PetPose(eyes: .closed, mouth: .open, gesture: .groom(reach: 1)), 0.18),
                (PetPose(eyes: .closed, gesture: .groom(reach: 2), headDrop: 1), 0.28),
                (PetPose(eyes: .closed, gesture: .groom(reach: 1), headDrop: 1), 0.2),
                (PetPose(eyes: .closed, gesture: .groom(reach: 2), headDrop: 1), 0.28),
                (PetPose(eyes: .happy), 0.4),
                (PetPose(), 0.2),
            ]
            frames = steps.map { frame($0.0, $0.1) }

        case .tailSwish:
            // Two lazy sweeps out and back, the first slower, holding at the
            // far end the way a content cat's tail hangs before it returns.
            let steps: [(Int, TimeInterval)] = [
                (0, 0.2), (1, 0.14), (2, 0.4), (1, 0.14), (0, 0.3),
                (1, 0.12), (2, 0.3), (1, 0.12), (0, 0.35),
            ]
            frames = steps.map { frame(PetPose(tailSwing: $0.0), $0.1) }

        case .play:
            // Eye the toy, crouch, and pat it: it rolls away (a ball bounces
            // as it goes) and comes back to be caught.
            let ball = breed.species == .dog
            let steps: [(PetPose.Prop, PetPose.Eyes, Int, TimeInterval)] = [
                (.toy(roll: 0, bounce: 0, bat: false), .open, 0, 0.35),
                (.toy(roll: 0, bounce: 0, bat: false), .open, 1, 0.2),
                (.toy(roll: 0, bounce: 0, bat: true), .open, 1, 0.16),
                (.toy(roll: 3, bounce: 0, bat: false), .happy, 0, 0.1),
                (.toy(roll: 7, bounce: ball ? 2 : 0, bat: false), .happy, 0, 0.1),
                (.toy(roll: 10, bounce: 0, bat: false), .open, 0, 0.45),
                (.toy(roll: 6, bounce: ball ? 3 : 0, bat: false), .open, 0, 0.12),
                (.toy(roll: 2, bounce: ball ? 1 : 0, bat: false), .open, 1, 0.12),
                (.toy(roll: 0, bounce: 0, bat: true), .happy, 1, 0.4),
                (.toy(roll: 0, bounce: 0, bat: false), .happy, 0, 0.3),
                (.toy(roll: 0, bounce: 0, bat: false), .open, 0, 0.2),
            ]
            frames = steps.map { toy, eyes, drop, duration in
                frame(PetPose(eyes: eyes, prop: toy, headDrop: drop), duration)
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
    /// Where the chin rests on a pet curled up asleep: on the tail that
    /// wraps along the floor in front of it.
    static let curledChinRow = 27
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
