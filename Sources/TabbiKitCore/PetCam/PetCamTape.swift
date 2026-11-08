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
    /// The strike: the paw through the object, mouth open.
    case midAct
    /// Looking straight into the camera.
    case lensStare
    /// Curled up on the floor, wide awake, looking into the camera.
    case lieDown
    /// An ordinary walk into frame.
    case stroll(step: Int)
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
    /// Tipping off the edge mid-strike.
    case tipping
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
        /// The same camera pushed in on the pet at a place: a 4x crop
        /// ("ENHANCE").
        case closeUp(PetCamPlace)
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

    public init(framing: Framing, objects: [PetCamSpot: PetCamObject], states: [PetCamSpot: PetCamObjectState] = [:],
                wrecks: [PetCamWreck] = [], pet: PetCamPose? = nil, place: PetCamPlace? = nil,
                debrisFrom: PetCamSpot? = nil) {
        self.framing = framing
        self.objects = objects
        self.states = states
        self.wrecks = wrecks
        self.pet = pet
        self.place = place
        self.debrisFrom = debrisFrom
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
        /// A catch pushes in on the face; a miss does a double take.
        case closer
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
        public var shake = false

        public init(shot: PetCamShot, time: Date, duration: TimeInterval, caption: String, detail: String? = nil,
                    stamp: Stamp? = nil, shake: Bool = false) {
            self.shot = shot
            self.time = time
            self.duration = duration
            self.caption = caption
            self.detail = detail
            self.stamp = stamp
            self.shake = shake
        }

        /// The camera's label ("CAM 1").
        public var cameraLabel: String {
            switch shot.framing {
            case .wide: "CAM 1"
            case .spot(let spot): "CAM \(spot.cameraNumber)"
            case .closeUp(let place): place.spot.map { "CAM \($0.cameraNumber)" } ?? "CAM 1"
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

    /// The shape a block's tape takes: its seed's pick, never the shape of
    /// `previous` (the last tape with the same outcome).
    public static func shape(seed: UInt64, previous: Shape?) -> Shape {
        let choices = Shape.allCases.filter { $0 != previous }
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
        guard let strike = record.strike, record.struck != nil, record.outcome.hasTape else {
            // Stopped early: the pet frozen mid-sneak toward the spot it was
            // staring at, which the frozen frame already showed, so a stop
            // never gives away where it would have struck.
            shape = .straight
            stills = [Still(shot: Self.with(wide, pet: .sneak(step: 1), at: .approach(record.setup.stare)),
                            time: record.endedAt, duration: 4, caption: captions.opener, detail: captions.closer,
                            stamp: .frozen)]
            return
        }
        shape = record.shape.flatMap(Shape.init(rawValue:)) ?? Self.shape(seed: record.setup.seed, previous: nil)
        let camera = record.camera
        let plan = Self.timeline(record)
        // The floor after the strike, exactly as the room kept it.
        var struckRoom = room
        var refill = PetCamRandom(seed: record.setup.seed, stream: "refill")
        struckRoom.strike(strike, at: record.endedAt, blockID: record.id, random: &refill)
        let close = PetCamShot(framing: .spot(camera), objects: room.objects, wrecks: room.wrecks)
        var after = close
        after.states = [strike: .gone]
        after.wrecks = struckRoom.wrecks
        let opener = Still(shot: Self.with(wide, pet: .stare(record.setup.stare), at: .home, states: Self.tellStates(record)),
                           time: start, duration: 1.8, caption: captions.opener)
        let rewind = Still(shot: Self.with(wide, pet: .stare(record.setup.stare), at: .home, states: Self.tellStates(record)),
                           time: start, duration: 1.4, caption: captions.rewind ?? captions.opener, stamp: .rewind)
        let struckDetail = captions.tell ?? record.struck.map { PetCamCaptions.sound(of: $0.kind) }

        if record.outcome == .caught {
            let sneak = Still(shot: Self.with(close, pet: .sneak(step: 0), at: .approach(strike)), time: plan.watch,
                              duration: 1.8, caption: captions.watch)
            let swat = Still(shot: Self.with(close, pet: .midAct, at: .strike(strike), states: [strike: .tipping]),
                             time: plan.strike, duration: 2.2, caption: captions.strike, detail: struckDetail, shake: true)
            let lens = Still(shot: Self.with(after, pet: .lensStare, at: .strike(strike)), time: plan.turn, duration: 2.0,
                             caption: captions.turn, detail: captions.callback)
            var freeze = Still(shot: Self.with(after, pet: .lensStare, at: .strike(strike)), time: plan.turn,
                               duration: 3.2, caption: captions.charge ?? captions.closer, detail: captions.priors,
                               stamp: .caught)
            switch shape {
            case .straight:
                let windUp = Still(shot: Self.with(close, pet: .swipe, at: .strike(strike)),
                                   time: plan.strike.addingTimeInterval(-2), duration: 1.6,
                                   caption: captions.age ?? captions.watch)
                var opening = opener
                opening.duration = 2.0
                stills = [opening, sneak, windUp, swat, lens, freeze]
            case .coldOpen:
                let scene = Still(shot: Self.with(after, pet: .lensStare, at: .strike(strike)), time: plan.turn,
                                  duration: 2.0, caption: captions.aftermath ?? captions.turn,
                                  detail: captions.callback ?? captions.age)
                freeze.duration = 3.4
                stills = [scene, rewind, sneak, swat, freeze]
            case .closer:
                var push = close
                push.framing = .closeUp(.strike(strike))
                push.states = after.states
                push.wrecks = after.wrecks
                let enhance = Still(shot: Self.with(push, pet: .lensStare, at: .strike(strike)), time: plan.turn,
                                    duration: 1.6, caption: captions.enhance ?? captions.turn, detail: captions.age)
                freeze.shot = enhance.shot
                freeze.duration = 3.4
                var lensFirst = lens
                lensFirst.duration = 1.8
                stills = [opener, sneak, swat, lensFirst, enhance, freeze]
            }
            return
        }

        // A miss: the camera holds on the wrong spot while the strike happens
        // somewhere else; the pet strolls in and lies down for it.
        var heard = close
        heard.debrisFrom = strike
        let crash = Still(shot: heard, time: plan.strike, duration: 1.6, caption: captions.strike,
                          detail: PetCamCaptions.offCamera, shake: true)
        var later = close
        later.states = [strike: .gone]
        later.wrecks = struckRoom.wrecks
        let stroll = Still(shot: Self.with(later, pet: .stroll(step: 1), at: .enter(camera)), time: plan.turn,
                           duration: 2.2, caption: captions.turn, detail: captions.callback)
        let alibi = Still(shot: Self.with(later, pet: .lieDown, at: .lounge(camera)), time: plan.alibi, duration: 3.4,
                          caption: captions.closer, detail: captions.age)
        var everywhere = wide
        everywhere.states = [strike: .gone]
        everywhere.wrecks = struckRoom.wrecks
        let reveal = Still(shot: Self.with(everywhere, pet: .lieDown, at: .lounge(camera)), time: plan.alibi,
                           duration: 2.4, caption: captions.reveal ?? captions.age ?? captions.closer,
                           detail: captions.tell)
        var opening = opener
        opening.duration = 1.4
        switch shape {
        case .straight:
            stills = [opening, crash, stroll, alibi, reveal]
        case .closer:
            var walkIn = stroll
            walkIn.duration = 2.0
            let look = Still(shot: Self.with(later, pet: .lensStare, at: .enter(camera)), time: plan.turn,
                             duration: 1.4, caption: captions.reaction ?? captions.turn)
            var tight = later
            tight.framing = .closeUp(.enter(camera))
            let again = Still(shot: Self.with(tight, pet: .lensStare, at: .enter(camera)), time: plan.turn,
                              duration: 1.2, caption: captions.enhance ?? captions.closer)
            var lieDown = alibi
            lieDown.duration = 3.2
            lieDown.detail = captions.tell ?? captions.age
            stills = [opening, crash, walkIn, look, again, lieDown]
        case .coldOpen:
            let open = Still(shot: alibi.shot, time: plan.alibi, duration: 2.4,
                             caption: captions.alibi ?? captions.closer, detail: captions.closer)
            var walkIn = stroll
            walkIn.duration = 2.0
            var ending = reveal
            ending.duration = 3.0
            stills = [open, rewind, crash, walkIn, ending]
        }
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
