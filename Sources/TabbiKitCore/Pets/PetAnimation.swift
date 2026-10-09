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
    public enum Eyes: String, CaseIterable, Hashable, Sendable {
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
    public enum Mouth: String, CaseIterable, Hashable, Sendable {
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
        /// away, `bounce` lifts a ball off the floor (yarn stays down), and
        /// `bat` puts the left front paw on top of it.
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
    public var loops: Bool { timeline.loops }

    /// How the animation plays, from `animations.json`.
    var timeline: PetTimeline { PetArt.animations.timeline(self) }
}

/// One frame of an animation.
public struct PetFrame: Hashable, Sendable {
    public var canvas: PetCanvas
    /// Seconds this frame stays on screen.
    public var duration: TimeInterval
    /// Where a speech bubble's tail should point, in frame pixels; set on
    /// frames that want to say something (alert).
    public var bubbleAnchor: PetPoint?
    /// The frame on each tick of the item clock while an animated costume
    /// item plays its loop (wings flapping, a glint on gold), starting with
    /// `canvas`, the still that Reduce Motion shows. Empty when nothing worn
    /// moves in this frame.
    public var itemFrames: [PetCanvas]

    public init(canvas: PetCanvas, duration: TimeInterval, bubbleAnchor: PetPoint? = nil, itemFrames: [PetCanvas] = []) {
        self.canvas = canvas
        self.duration = duration
        self.bubbleAnchor = bubbleAnchor
        self.itemFrames = itemFrames
    }

    /// Seconds per tick of the item clock, the pet's own frame rate (a
    /// walking step), so costume loops move in step with the pet.
    public static let itemFrameDuration: TimeInterval = {
        guard let duration = PetArt.costume.itemFrameDuration else {
            preconditionFailure("costume.json sets no itemFrameDuration")
        }
        return duration
    }()

    /// The item clock's tick at `time`. It counts from a fixed moment (any
    /// shared clock, such as the reference date), not from the clip's
    /// start, so a cape keeps glimmering smoothly when the pet changes clip.
    public static func itemTick(at time: TimeInterval) -> Int {
        Int((time / itemFrameDuration).rounded(.down))
    }

    /// This frame as drawn at `time` on the item clock: `canvas` is the
    /// item loop's frame for that tick.
    public func atItemTime(_ time: TimeInterval) -> PetFrame {
        guard !itemFrames.isEmpty else { return self }
        var frame = self
        frame.canvas = itemFrames[Self.itemTick(at: time) % itemFrames.count]
        return frame
    }

    /// When the item loop next changes the picture after `time`, skipping
    /// ticks that look the same (a glint that only shows now and then), or
    /// nil when nothing worn moves in this frame.
    public func nextItemChange(after time: TimeInterval) -> TimeInterval? {
        guard !itemFrames.isEmpty else { return nil }
        let tick = Self.itemTick(at: time)
        let shown = itemFrames[tick % itemFrames.count]
        for step in 1...itemFrames.count where itemFrames[(tick + step) % itemFrames.count] != shown {
            return Double(tick + step) * Self.itemFrameDuration
        }
        return nil
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
        frames[min(animation.timeline.stillIndex, frames.count - 1)]
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
    /// Builds `animation` for a dressed breed from its timeline in
    /// `animations.json`. Composition is cheap (a few 32x32 grids), but
    /// callers that play clips repeatedly should keep the result instead of
    /// rebuilding it every frame.
    public static func clip(
        _ animation: PetAnimation, for breed: PetBreed,
        outfit: PetOutfit = .none, accessories: [PetAccessory] = []
    ) -> PetClip {
        let timeline = animation.timeline
        let loop = itemLoopLength(outfit: outfit, accessories: accessories)
        // One composed frame per tick of the item loop, so animated costume
        // items stay anchored to every pose.
        let phases = timeline.frames.map { step in
            (0..<loop).map { compose(breed, pose: step.pose, outfit: outfit, accessories: accessories,
                                     stance: step.stance, phase: $0) }
        }
        // Effects placed by the head follow the clip's first frame, so a
        // drifting "z" doesn't bob with each breath.
        let head = phases[0][0].headTopRight
        func place(_ coordinate: PetTimeline.Coordinate, from origin: Int) -> Int {
            switch coordinate {
            case .frame(let value): value
            case .head(let offset): origin + offset
            }
        }
        func finish(_ step: PetTimeline.Frame, _ composed: Composed) -> PetCanvas {
            let pet = composed.canvas.shifted(x: 0, y: step.shiftY)
            var canvas = pet
            for effect in step.effects {
                let grid = PetArt.effect.grid(effect.grid)
                canvas = canvas.adding(grid, at: PetPoint(x: place(effect.x, from: head.x), y: place(effect.y, from: head.y)))
            }
            if let steam = step.steam, let top = composed.mugTop {
                let wisp = PropArt.steam[steam]
                // Painted over the chest, not behind the pet like other effects.
                canvas.stamp(wisp, x: top.x + 1, y: top.y - wisp.height)
            }
            if step.dust {
                // Puffs on the floor just outside the paws (the bottom row,
                // so a wide tail higher up doesn't push them away).
                let floor = frameSize - 1 - step.pose.lift
                let paws = (0..<frameSize).filter { canvas[$0, floor] != nil }
                if let left = paws.first, let right = paws.last {
                    let y = frameSize - EffectArt.dustLeft.height
                    canvas = canvas
                        .adding(EffectArt.dustLeft, at: PetPoint(x: left - EffectArt.dustLeft.width, y: y))
                        .adding(EffectArt.dustRight, at: PetPoint(x: right + 1, y: y))
                }
            }
            // Wings go behind the pet and its effects: a "z" or a heart
            // floats in front of them.
            if let back = composed.back {
                canvas = canvas.over(back.shifted(x: 0, y: step.shiftY), ringing: canvas.added(over: pet))
            }
            return canvas
        }
        let frames = zip(timeline.frames, phases).map { step, phases in
            let canvases = phases.map { finish(step, $0) }
            // A frame where the moving item is out of sight (a hanging pet
            // shows no body) holds still.
            let moves = canvases.contains { $0 != canvases[0] }
            return PetFrame(
                canvas: canvases[0], duration: step.duration,
                bubbleAnchor: step.bubble ? phases[0].headTopRight : nil,
                itemFrames: moves ? canvases : []
            )
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
    /// The pixels this canvas has where `base` is transparent: what was
    /// added over it, such as effects.
    func added(over base: PetCanvas) -> PetCanvas {
        var added = PetCanvas(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width where base[x, y] == nil { added[x, y] = self[x, y] }
        }
        return added
    }

    /// `over(layer)`, with an outline ring cut into `layer` around the
    /// pixels of `floating`, so a light "z" stays readable on white wings.
    func over(_ layer: PetCanvas, ringing floating: PetCanvas) -> PetCanvas {
        var ringed = layer
        for y in 0..<height {
            for x in 0..<width where floating[x, y] == nil && layer[x, y] != nil && self[x, y] == nil {
                let around = [floating[x - 1, y], floating[x + 1, y], floating[x, y - 1], floating[x, y + 1]]
                if around.contains(where: { $0 != nil }) { ringed[x, y] = .outline }
            }
        }
        return over(ringed)
    }

    /// A copy with an effect painted behind the pet (no outline): effect
    /// pixels only fill transparent space, so a heart or "z" drifting past
    /// a hat never hides part of the pet.
    func adding(_ grid: SpriteGrid, at point: PetPoint) -> PetCanvas {
        var effect = PetCanvas(width: width, height: height)
        effect.stamp(grid, x: point.x, y: point.y)
        return over(effect)
    }
}
