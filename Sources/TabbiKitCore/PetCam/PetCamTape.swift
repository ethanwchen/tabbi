import Foundation

/// What the pet is doing in a still. Each pose is drawn for every breed
/// and look by `PetCamPetArt` from the shared pet art.
public enum PetCamPose: Hashable, Sendable {
    /// Sitting on the floor, eyes on one spot: the tell.
    case stare(PetCamSpot)
    /// Creeping low toward a spot, mid-step.
    case sneak(step: Int)
    /// Sitting up on the furniture, a paw raised at the object.
    case swipe
    /// The strike, as the object calls for it: a swat at the mug, a paw in
    /// the fishbowl, a chomp of the donut, a shred of the tissues, a dig in
    /// the plant, a head-shove at the vase.
    case act(PetCamObjectKind)
    /// Frozen mid-act with its eyes on the lens: in mid-air off the spot,
    /// paw out, or (the donut) with its mouth full.
    case caughtMidAct(PetCamObjectKind)
    /// Eye contact after a catch, wearing the evidence (a fish on its head,
    /// frosting on its mouth): the guilty look the wall files.
    case guilty(PetCamObjectKind)
    /// The face that freezes under the stamp, exactly as the case file
    /// shows it: the case's expression (`look`), the evidence, and the
    /// rap-sheet `tier`'s props.
    case mugshot(PetCamObjectKind, look: Int, tier: Int)
    /// Looking straight into the camera.
    case lensStare
    /// Curled up on the floor, wide awake, looking into the camera.
    case lieDown
    /// An ordinary walk into frame.
    case stroll(step: Int)
    /// Strolling past a camera, wearing the evidence of what it went for:
    /// the walk-by miss.
    case walkBy(PetCamObjectKind)
}

/// Where the pet is in a shot, as a place in the room rather than pixels;
/// the room art (`PetCamLayout`) knows where each place is.
public enum PetCamPlace: Hashable, Sendable {
    /// The middle of the floor, where the pet waits.
    case home
    /// On the floor partway to a spot.
    case approach(PetCamSpot)
    /// Up on the spot's furniture beside the object.
    case strike(PetCamSpot)
    /// Walking into the spot camera's frame.
    case enter(PetCamSpot)
    /// Lying on the floor in front of the spot.
    case lounge(PetCamSpot)
}

extension PetCamPlace {
    /// The spot whose camera films this place; nil in the middle of the floor.
    public var spot: PetCamSpot? {
        switch self {
        case .home: nil
        case .approach(let spot), .strike(let spot), .enter(let spot), .lounge(let spot): spot
        }
    }
}

/// How an object looks in a shot.
public enum PetCamObjectState: Hashable, Sendable {
    case still
    /// Teetering: the wobble exception.
    case wobbling
    /// Scent lines: the appetite exception.
    case scented
    /// Mid-strike, as the act leaves it: knocked flying (the mug and the
    /// vase), splashing (the fishbowl), torn at (the tissues), spraying soil
    /// (the plant), or in the pet's mouth (the donut).
    case struck
    /// On its way to the floor, between the act and the wreck.
    case falling
    /// Gone from its spot (it is a wreck now, or eaten).
    case gone
}

/// One picture of the room, in the room's own terms: what is on each
/// spot, what lies on the floor, where the pet is and what it does. The
/// renderer turns it into pixels; tests read it as data.
public struct PetCamShot: Hashable, Sendable {
    public enum Framing: Hashable, Sendable {
        /// CAM 1, the corner camera that sees the whole room.
        case wide
        /// A spot's hidden camera, close on that spot: a 2x crop.
        case spot(PetCamSpot)
        /// The camera filming a place re-aimed at the pet there: a 2x crop,
        /// like a spot camera's, centered on the whole pet.
        case closeUp(PetCamPlace)
        /// Pushed in on the newest wreck under a spot, a 2x crop centered on
        /// it: from that spot's own hidden camera, or (`hidden` false) from
        /// CAM 1 in the corner.
        case wreck(PetCamSpot, hidden: Bool)
    }

    /// A nudge of the pet off its place, in sprite pixels, for the
    /// in-between frames of an export.
    public struct Offset: Hashable, Sendable {
        public var x: Int
        public var y: Int

        public init(x: Int, y: Int) {
            self.x = x
            self.y = y
        }

        public static let zero = Offset(x: 0, y: 0)
    }

    public var framing: Framing
    public var objects: [PetCamSpot: PetCamObject]
    public var states: [PetCamSpot: PetCamObjectState]
    /// Wrecks on the floor, oldest first (the newest drawn on top).
    public var wrecks: [PetCamWreck]
    public var pet: PetCamPose?
    public var place: PetCamPlace?
    /// Bits flying in from the edge of the frame: the miss's off-camera
    /// strike.
    public var debrisFrom: PetCamSpot?
    /// How far the debris has slid in: 0 just over the edge, 1 skidding
    /// into the frame.
    public var debrisStep: Int
    public var petOffset: Offset
    /// The pet's eyes shut for a moment: the one blink a held still gets.
    public var blink = false

    public init(framing: Framing, objects: [PetCamSpot: PetCamObject], states: [PetCamSpot: PetCamObjectState] = [:],
                wrecks: [PetCamWreck] = [], pet: PetCamPose? = nil, place: PetCamPlace? = nil,
                debrisFrom: PetCamSpot? = nil, debrisStep: Int = 0, petOffset: Offset = .zero) {
        self.framing = framing
        self.objects = objects
        self.states = states
        self.wrecks = wrecks
        self.pet = pet
        self.place = place
        self.debrisFrom = debrisFrom
        self.debrisStep = debrisStep
        self.petOffset = petOffset
    }

    /// The frozen frame on the home screen: the pet on the floor staring
    /// at one spot, and the exception (a wobble or scent lines) if one shows.
    public static func frozenFrame(room: PetCamRoom, setup: PetCamSetup) -> PetCamShot {
        var states: [PetCamSpot: PetCamObjectState] = [:]
        if let tell = setup.tell {
            states[tell.spot] = tell.exception == .appetite ? .scented : .wobbling
        }
        return PetCamShot(framing: .wide, objects: room.objects, states: states, wrecks: room.wrecks,
                          pet: .stare(setup.stare), place: .home)
    }
}

/// A tape: four to six timestamped stills with cuts and captions, ten to
/// fifteen seconds long, that ends by itself. Built from a block record
/// alone, so a mugshot on the wall replays exactly the tape it came from.
///
/// Each outcome has three shapes, picked by the block's seed when it
/// resolves and never the same one twice in a row (`PetCamBlockRecord.shape`),
/// so the tapes do not settle into one rhythm:
///
/// - a catch plays straight through, opens cold on the aftermath and
///   rewinds, or pushes in on the pet's face ("ENHANCE") for the freeze;
/// - a miss cuts from the crash over the wrong spot to the pet walking in
///   at second three, plays a double take into the lens, or opens cold on
///   the alibi and rewinds; the straight and cold versions end on the
///   corner camera's view of what really happened.
/// A tape: five to seven timestamped stills with cuts and captions, ten to
/// fifteen seconds long, that ends by itself. Built from a block record
/// alone, so a mugshot on the wall replays exactly the tape it came from.
///
/// Each outcome has three shapes, picked by the block's seed when it
/// resolves and never one of the last two of the same outcome
/// (`PetCamBlockRecord.shape`), so the tapes do not settle into one rhythm.
/// The act in every catch is the object's own (a swat, a paw in the bowl, a
/// chomp, a shred, a dig, a head-shove):
///
/// - a catch plays straight through to the eye contact and the freeze,
///   opens cold on a close-up of the wreck with no pet in frame and
///   rewinds, or freezes on the act itself, mid-air or with its mouth full;
/// - a miss hears the crash as debris skids into the wrong camera's frame
///   and the pet walks in at second three, adds a double take into the
///   lens, or opens cold on the alibi and rewinds; every miss ends on
///   CAM 1 pushed in on the wreck it did not see.
public struct PetCamTape: Hashable, Sendable {
    /// What a still stamps over the picture.
    public enum Stamp: Hashable, Sendable {
        /// The catch's freeze frame.
        case caught
        /// The early stop's single still.
        case frozen
        /// The tape winds back: what follows happened earlier.
        case rewind
    }

    /// The tape's structure, one of three per outcome.
    public enum Shape: Int, CaseIterable, Hashable, Sendable {
        /// Straight through: the opener, the act, the turn.
        case straight
        /// Starts on the result, rewinds, and plays up to it.
        case coldOpen
        /// A catch freezes on the act; a miss does a double take.
        case closer
    }

    /// The sound a still cuts in on, for a player or export with sound:
    /// the motion beep, the object's own strike, the same strike muffled
    /// off camera, and the thud of the CAUGHT stamp. Tape hiss runs under
    /// all of it.
    public enum Cue: Hashable, Sendable {
        case motion
        case strike(PetCamObjectKind)
        case offCamera(PetCamObjectKind)
        case stamp
    }

    public struct Still: Hashable, Sendable {
        public var shot: PetCamShot
        /// The camera's burn-in time.
        public var time: Date
        /// Seconds on screen.
        public var duration: TimeInterval
        /// The main caption, burned in at the bottom.
        public var caption: String
        /// A smaller line under it.
        public var detail: String?
        public var stamp: Stamp?
        /// The camera jolts as the still cuts in: something just hit hard.
        public var shake: Bool
        public var cue: Cue?
        /// Eye contact: an export pushes in on the pet while it holds.
        public var punchIn: Bool

        public init(shot: PetCamShot, time: Date, duration: TimeInterval, caption: String, detail: String? = nil,
                    stamp: Stamp? = nil, shake: Bool = false, cue: Cue? = nil, punchIn: Bool = false) {
            self.shot = shot
            self.time = time
            self.duration = duration
            self.caption = caption
            self.detail = detail
            self.stamp = stamp
            self.shake = shake
            self.cue = cue
            self.punchIn = punchIn
        }

        /// The camera's label ("CAM 1").
        public var cameraLabel: String {
            switch shot.framing {
            case .wide: "CAM 1"
            case .spot(let spot): "CAM \(spot.cameraNumber)"
            case .closeUp(let place): place.spot.map { "CAM \($0.cameraNumber)" } ?? "CAM 1"
            case .wreck(let spot, let hidden): hidden ? "CAM \(spot.cameraNumber)" : "CAM 1"
            }
        }
    }

    public var stills: [Still]
    public var outcome: PetCamBlockRecord.Outcome
    public var shape: Shape

    /// The tape's whole length in seconds.
    public var duration: TimeInterval { stills.reduce(0) { $0 + $1.duration } }

    /// The tape's length, by the design rule that a reveal is short and ends
    /// by itself well inside a break.
    public static let durationRange: ClosedRange<TimeInterval> = 10...15

    /// The longest any tape may run.
    public static let maximumDuration: TimeInterval = 20

    /// The shape a block's tape takes: its seed's pick of the shapes not in
    /// `recent` (the last tapes with the same outcome, newest first; only
    /// the last two count), so three tapes in a row of one outcome play all
    /// three shapes.
    public static func shape(seed: UInt64, recent: [Shape]) -> Shape {
        var choices = Shape.allCases.filter { !recent.prefix(2).contains($0) }
        if choices.isEmpty { choices = Shape.allCases.filter { $0 != recent.first } }
        var roll = PetCamRandom(seed: seed, stream: "shape")
        return choices[Int(roll.next() % UInt64(choices.count))]
    }

    /// The tape (or, for a stop, the single still) of `record`; nil for a
    /// cancelled block, which shows nothing.
    public init?(record: PetCamBlockRecord) {
        guard record.outcome != .cancelled else { return nil }
        outcome = record.outcome
        let room = record.room
        let captions = record.captions
        let wide = PetCamShot(framing: .wide, objects: room.objects, wrecks: room.wrecks)
        let start = record.startedAt
        guard let strike = record.strike, let struck = record.struck, record.outcome.hasTape else {
            // Stopped early: the pet frozen mid-sneak toward the spot it was
            // staring at, which the frozen frame already showed, so a stop
            // never gives away where it would have struck.
            shape = .straight
            stills = [Still(shot: Self.with(wide, pet: .sneak(step: 1), at: .approach(record.setup.stare)),
                            time: record.endedAt, duration: 4, caption: captions.opener, detail: captions.closer,
                            stamp: .frozen)]
            return
        }
        shape = record.shape.flatMap(Shape.init(rawValue:)) ?? Self.shape(seed: record.setup.seed, recent: [])
        let kind = struck.kind
        let camera = record.camera
        let plan = Self.timeline(record)
        // The floor right after the strike: the new wreck down, nothing
        // tidied away or left out yet.
        var wrecked = room
        wrecked.wreck(strike, at: record.endedAt, blockID: record.id)
        let close = PetCamShot(framing: .spot(camera), objects: room.objects, wrecks: room.wrecks)
        var after = close
        after.states = [strike: .gone]
        after.wrecks = wrecked.wrecks
        let stare = Self.with(wide, pet: .stare(record.setup.stare), at: .home, states: Self.tellStates(record))
        let opener = Still(shot: stare, time: start, duration: 1.8, caption: captions.opener)
        let rewind = Still(shot: stare, time: start, duration: 1.4, caption: captions.rewind ?? captions.opener,
                           stamp: .rewind)
        let struckDetail = captions.tell ?? PetCamCaptions.sound(of: kind)
        var exhibit = after
        exhibit.framing = .wreck(strike, hidden: record.outcome == .caught)

        if record.outcome == .caught {
            let sneak = Still(shot: Self.with(close, pet: .sneak(step: 0), at: .approach(strike)), time: plan.watch,
                              duration: 1.8, caption: captions.watch, cue: .motion)
            let windUp = Still(shot: Self.with(close, pet: .swipe, at: .strike(strike)),
                               time: plan.strike.addingTimeInterval(-2), duration: 1.6,
                               caption: captions.age ?? captions.windUp ?? captions.watch)
            let act = Still(shot: Self.with(close, pet: .act(kind), at: .strike(strike), states: [strike: .struck]),
                            time: plan.strike, duration: 1.8, caption: captions.strike, detail: struckDetail,
                            shake: true, cue: .strike(kind))
            // Between the act and the landing, the object on its way down,
            // so the strike moves instead of cutting.
            var fall = act
            fall.shot.states[strike] = .falling
            fall.duration = 0.4
            fall.shake = false
            fall.cue = nil
            fall.time = plan.strike.addingTimeInterval(1)
            let falls = PetCamScene.falls(kind)
            // Eye contact wearing the evidence, then the freeze on the face
            // the wall files, with its rap-sheet props.
            let lens = Still(shot: Self.with(after, pet: .guilty(kind), at: .strike(strike)), time: plan.turn,
                             duration: 1.4, caption: captions.turn, detail: captions.callback, punchIn: true)
            var freeze = Still(shot: Self.with(after, pet: Self.mugshotPose(record, kind), at: .strike(strike)),
                               time: min(plan.turn.addingTimeInterval(1), record.endedAt), duration: 2.2,
                               caption: captions.charge ?? captions.closer,
                               detail: captions.wanted ?? captions.priors, stamp: .caught, cue: .stamp)
            switch shape {
            case .straight:
                var opening = opener
                opening.duration = 2.0
                stills = [opening, sneak, windUp, act] + (falls ? [fall] : []) + [lens, freeze]
            case .coldOpen:
                // The wreck alone, as the hidden camera found it.
                let scene = Still(shot: exhibit, time: plan.turn, duration: 2.2,
                                  caption: captions.aftermath ?? captions.turn, detail: captions.callback ?? captions.age)
                freeze.punchIn = true
                // The wind-up, so the rewound part has its build before the act.
                var cocked = windUp
                cocked.caption = captions.windUp ?? captions.watch
                stills = [scene, rewind, sneak, cocked, act] + (falls ? [fall] : []) + [freeze]
            case .closer:
                // The freeze lands on the act itself.
                // An object that falls hangs in mid-air past the edge under
                // the stamp, so the picture matches the sound already heard.
                var midAct = Self.with(close, pet: .caughtMidAct(kind), at: .strike(strike),
                                       states: [strike: falls ? .falling : .struck])
                // Pushed in on the pet, unless something is falling: then
                // the camera's own view, which keeps the object in frame.
                midAct.framing = falls ? .spot(strike) : .closeUp(.strike(strike))
                freeze.shot = midAct
                var quick = act
                quick.duration = 2.0
                // No hold runs past 2.4 s, so the build-up carries the length.
                var opening = opener
                opening.duration = 2.0
                var creep = sneak
                creep.duration = 2.0
                var cocked = windUp
                cocked.duration = 1.8
                stills = [opening, creep, cocked, quick, freeze]
            }
            return
        }

        // A miss: the camera holds on the wrong spot while the strike happens
        // somewhere else; debris skids into its frame, then the pet strolls
        // in and lies down for it, and CAM 1 shows what really happened.
        var heard = close
        heard.debrisFrom = strike
        let crash = Still(shot: heard, time: plan.strike, duration: 0.6, caption: captions.strike,
                          detail: captions.offCamera ?? PetCamCaptions.offCamera, shake: true, cue: .offCamera(kind))
        var skid = crash
        skid.shot.debrisStep = 1
        skid.duration = 1.0
        skid.shake = false
        skid.cue = nil
        skid.time = plan.strike.addingTimeInterval(1)
        var later = close
        later.states = [strike: .gone]
        later.wrecks = wrecked.wrecks
        // A callback that names a spot rides only on a still filmed there or
        // on CAM 1, so THE COUNTER AGAIN never sits under the shelf camera.
        let named = captions.callback.flatMap(PetCamCaptions.spotNamed(in:))
        let callbackHere = named == nil || named == camera ? captions.callback : nil
        let callbackOnCAM1 = named != nil && named != camera ? captions.callback : nil
        let walkIn = Still(shot: Self.with(later, pet: .stroll(step: 1), at: .enter(camera)), time: plan.turn,
                           duration: 2.4, caption: captions.turn, detail: callbackHere)
        let alibi = Still(shot: Self.with(later, pet: .lieDown, at: .lounge(camera)), time: plan.alibi, duration: 2.4,
                          caption: captions.closer, detail: captions.age)
        // The pet lying in front of the other camera is in this picture only
        // when all of it is; never a cut-off cat at the edge.
        let witness = PetCamScene.showsWholePet(at: .lounge(camera), pose: .lieDown, in: exhibit, pet: record.pet)
        let reveal = Still(shot: witness ? Self.with(exhibit, pet: .lieDown, at: .lounge(camera)) : exhibit,
                           time: plan.alibi, duration: 2.2, caption: captions.reveal ?? captions.closer,
                           detail: captions.tell ?? callbackOnCAM1)
        var opening = opener
        opening.duration = 1.4
        switch shape {
        case .straight:
            stills = [opening, crash, skid, walkIn, alibi, reveal]
        case .closer:
            // The walk-by: the suspect strolls right past the hidden camera
            // wearing the evidence, stops, stares into it and denies it all;
            // then CAM 1 shows where it struck.
            let walkBy = Still(shot: Self.with(later, pet: .walkBy(kind), at: .enter(camera)), time: plan.turn,
                               duration: 2.4, caption: captions.walkBy ?? captions.turn, detail: callbackHere)
            let denial = Still(shot: Self.with(later, pet: .guilty(kind), at: .enter(camera)),
                               time: min(plan.turn.addingTimeInterval(2), record.endedAt), duration: 2.4,
                               caption: captions.denial ?? captions.closer, punchIn: true)
            stills = [opening, crash, skid, walkBy, denial, reveal]
        case .coldOpen:
            let open = Still(shot: alibi.shot, time: plan.alibi, duration: 2.4,
                             caption: captions.alibi ?? captions.closer, detail: captions.closer)
            var ending = reveal
            ending.detail = captions.tell ?? captions.age
            stills = [open, rewind, crash, skid, walkIn, ending]
        }
    }

    /// The in-between pictures from one still to the next, for an export
    /// that moves rather than cuts: the next still's pet slid (with a small
    /// hop) from where it stood in this one, `count` of them, when both
    /// are the same camera's view of the pet in two places; empty for a cut.
    public static func tweens(from: Still, to: Still, count: Int) -> [PetCamShot] {
        guard count > 0, from.shot.framing == to.shot.framing,
              let fromPose = from.shot.pet, let fromPlace = from.shot.place,
              let toPose = to.shot.pet, let toPlace = to.shot.place, fromPlace != toPlace else { return [] }
        let a = PetCamScene.placement(for: fromPlace, pose: fromPose)
        let b = PetCamScene.placement(for: toPlace, pose: toPose)
        let dx = Double(a.x - b.x), dy = Double(a.y - b.y)
        return (1...count).map { step in
            let left = 1 - Double(step) / Double(count + 1)
            let hop = sin(Double.pi * left) * min(6, abs(dy) / 4 + 2)
            var shot = to.shot
            shot.petOffset = PetCamShot.Offset(x: Int((dx * left).rounded()), y: Int((dy * left - hop).rounded()))
            return shot
        }
    }

    /// The freeze's face: the case file's expression for this case number,
    /// the evidence and the rap-sheet tier.
    public static func mugshotPose(_ record: PetCamBlockRecord, _ kind: PetCamObjectKind) -> PetCamPose {
        let look = (record.caseNumber ?? Int(record.setup.seed % 5) + 1) - 1
        return .mugshot(kind, look: look, tier: record.tier)
    }

    /// The share clip of `record`: about five seconds that open on the
    /// strike and loop. A catch plays the act (and the fall), the eye
    /// contact with a push-in and the stamp by about 3.5 seconds, held a
    /// moment; a miss plays the crash skidding in, the innocent lie-down and
    /// the evidence. Both end on the tape winding back to the start, so the
    /// loop reads as a rewind. Nil for a block without a tape.
    public static func clip(_ record: PetCamBlockRecord) -> [Still]? {
        guard let tape = PetCamTape(record: record), tape.outcome.hasTape, let strike = record.strike,
              let kind = record.struck?.kind else { return nil }
        let captions = record.captions
        func first(_ match: (Still) -> Bool) -> Still? { tape.stills.first(where: match) }
        var cut: [Still] = []
        if tape.outcome == .caught {
            let act = first { $0.cue == .strike(kind) }
            let fall = first { $0.shot.states[strike] == .falling }
            let after = tape.stills.last.map(\.shot) ?? PetCamShot(framing: .spot(strike), objects: [:])
            var shot = after
            shot.pet = .guilty(kind)
            shot.framing = .spot(record.camera)
            guard var opening = act else { return nil }
            opening.duration = 1.4
            cut.append(opening)
            if var fall {
                fall.duration = 0.4
                cut.append(fall)
            }
            cut.append(Still(shot: shot, time: opening.time, duration: 1.5, caption: captions.turn, punchIn: true))
            var freeze = tape.stills[tape.stills.count - 1]
            freeze.shot.pet = Self.mugshotPose(record, kind)
            freeze.shot.framing = .spot(record.camera)
            freeze.duration = 1.4
            freeze.detail = captions.wanted ?? captions.priors
            cut.append(freeze)
        } else {
            guard var crash = first({ $0.shot.debrisFrom != nil && $0.shot.debrisStep == 0 }),
                  var skid = first({ $0.shot.debrisFrom != nil && $0.shot.debrisStep == 1 }),
                  var alibi = first({ ($0.shot.pet == .lieDown || $0.shot.pet == .guilty(kind))
                      && $0.shot.framing == .spot(record.camera) }),
                  var evidence = tape.stills.last else { return nil }
            crash.duration = 0.6
            skid.duration = 0.8
            alibi.duration = 1.6
            // The lie-down says the alibi; the walk-by keeps its denial.
            if alibi.shot.pet == .lieDown { alibi.caption = captions.closer }
            alibi.detail = nil
            evidence.duration = 1.6
            cut += [crash, skid, alibi, evidence]
        }
        // The loop: the tape winds back to its first frame.
        var rewind = cut[0]
        rewind.stamp = .rewind
        rewind.shake = false
        rewind.cue = nil
        rewind.duration = 0.6
        rewind.caption = captions.rewind ?? "REWIND."
        rewind.detail = nil
        cut.append(rewind)
        return cut
    }

    private static func with(_ shot: PetCamShot, pet: PetCamPose, at place: PetCamPlace,
                             states: [PetCamSpot: PetCamObjectState] = [:]) -> PetCamShot {
        var copy = shot
        copy.pet = pet
        copy.place = place
        for (spot, state) in states { copy.states[spot] = state }
        return copy
    }

    private static func tellStates(_ record: PetCamBlockRecord) -> [PetCamSpot: PetCamObjectState] {
        guard let tell = record.setup.tell else { return [:] }
        return [tell.spot: tell.exception == .appetite ? .scented : .wobbling]
    }

    /// The burn-in times: the strike lands somewhere in the back half of
    /// the block (from the seed), the rest follows within seconds.
    private static func timeline(_ record: PetCamBlockRecord) -> (watch: Date, strike: Date, turn: Date, alibi: Date) {
        var roll = PetCamRandom(seed: record.setup.seed, stream: "times")
        let span = max(record.endedAt.timeIntervalSince(record.startedAt), 1)
        let strike = record.startedAt.addingTimeInterval(span * (0.5 + 0.35 * roll.unit()))
        // Seconds around the strike, shrunk to fit a short block's end.
        let left = record.endedAt.timeIntervalSince(strike)
        return (strike.addingTimeInterval(-min(8 + 10 * roll.unit(), span * 0.2)), strike,
                strike.addingTimeInterval(min(2 + 3 * roll.unit(), left * 0.1)),
                strike.addingTimeInterval(min(40 + 50 * roll.unit(), left * 0.8)))
    }
}
