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
        /// A spot's hidden camera, close on that spot.
        case spot(PetCamSpot)
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

/// A tape: four to six timestamped stills with cuts and captions, under
/// twenty seconds, that ends by itself. Built from a block record alone,
/// so a mugshot on the wall replays exactly the tape it came from.
public struct PetCamTape: Hashable, Sendable {
    /// What a still stamps over the picture.
    public enum Stamp: Hashable, Sendable {
        /// The catch's freeze frame.
        case caught
        /// The early stop's single still.
        case frozen
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

        /// The camera's label ("CAM 1").
        public var cameraLabel: String {
            switch shot.framing {
            case .wide: "CAM 1"
            case .spot(let spot): "CAM \(spot.cameraNumber)"
            }
        }
    }

    public var stills: [Still]
    public var outcome: PetCamBlockRecord.Outcome

    /// The tape's whole length in seconds.
    public var duration: TimeInterval { stills.reduce(0) { $0 + $1.duration } }

    /// The longest a tape may run, by the design rule that a reveal ends by
    /// itself well inside a break.
    public static let maximumDuration: TimeInterval = 20

    /// The tape (or, for a stop, the single still) of `record`; nil for a
    /// cancelled block, which shows nothing.
    public init?(record: PetCamBlockRecord) {
        guard record.outcome != .cancelled else { return nil }
        outcome = record.outcome
        let room = record.room
        let wide = PetCamShot(framing: .wide, objects: room.objects, wrecks: room.wrecks)
        let opener = Still(shot: Self.with(wide, pet: .stare(record.setup.stare), at: .home, states: Self.tellStates(record)),
                           time: record.startedAt, duration: 2.2, caption: record.captions.opener)
        guard let strike = record.strike, record.struck != nil, record.outcome.hasTape else {
            // Stopped early: the pet frozen mid-sneak toward the spot it was
            // staring at, which the frozen frame already showed, so a stop
            // never gives away where it would have struck.
            let still = Still(shot: Self.with(wide, pet: .sneak(step: 1), at: .approach(record.setup.stare)),
                              time: record.endedAt, duration: 4, caption: record.captions.opener,
                              detail: record.captions.closer, stamp: .frozen)
            stills = [still]
            return
        }
        let camera = record.camera
        let plan = Self.timeline(record)
        let close = PetCamShot(framing: .spot(camera), objects: room.objects, wrecks: room.wrecks)
        // The floor after the strike, exactly as the room kept it.
        var struckRoom = room
        var refill = PetCamRandom(seed: record.setup.seed, stream: "refill")
        struckRoom.strike(strike, at: record.endedAt, blockID: record.id, random: &refill)
        let after = PetCamShot(framing: .spot(camera), objects: room.objects, states: [strike: .gone],
                               wrecks: struckRoom.wrecks)
        if record.outcome == .caught {
            stills = [
                opener,
                Still(shot: Self.with(close, pet: .sneak(step: 0), at: .approach(strike)), time: plan.watch,
                      duration: 2.2, caption: record.captions.watch),
                Still(shot: Self.with(close, pet: .swipe, at: .strike(strike)), time: plan.strike.addingTimeInterval(-2),
                      duration: 2.0, caption: record.captions.age ?? record.captions.watch),
                Still(shot: Self.with(close, pet: .midAct, at: .strike(strike), states: [strike: .tipping]),
                      time: plan.strike, duration: 2.4, caption: record.captions.strike,
                      detail: record.struck.map { PetCamCaptions.sound(of: $0.kind) }, shake: true),
                Still(shot: Self.with(after, pet: .lensStare, at: .strike(strike)), time: plan.turn, duration: 2.6,
                      caption: record.captions.turn, detail: record.captions.callback),
                // The stamp says CAUGHT; the caption reads the charge.
                Still(shot: Self.with(after, pet: .lensStare, at: .strike(strike)), time: plan.turn, duration: 3.6,
                      caption: record.captions.charge ?? record.captions.closer, detail: record.captions.priors,
                      stamp: .caught),
            ]
        } else {
            // The camera holds on the wrong spot while the strike happens
            // somewhere else; then the pet strolls in and lies down for it.
            let quiet = PetCamShot(framing: .spot(camera), objects: room.objects, wrecks: room.wrecks)
            var heard = quiet
            heard.debrisFrom = strike
            var later = quiet
            later.states = [strike: .gone]
            later.wrecks = struckRoom.wrecks
            stills = [
                opener,
                Still(shot: quiet, time: plan.watch, duration: 2.2, caption: record.captions.watch),
                Still(shot: heard, time: plan.strike, duration: 2.6, caption: record.captions.strike,
                      detail: PetCamCaptions.offCamera, shake: true),
                Still(shot: Self.with(later, pet: .stroll(step: 1), at: .enter(camera)), time: plan.turn, duration: 2.4,
                      caption: record.captions.turn, detail: record.captions.callback),
                Still(shot: Self.with(later, pet: .lieDown, at: .lounge(camera)), time: plan.alibi, duration: 3.8,
                      caption: record.captions.closer, detail: record.captions.age),
            ]
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
