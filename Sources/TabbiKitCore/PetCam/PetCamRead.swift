import Foundation

/// How the pet decides where to strike, as data, so playtests can compare
/// variants without a code change (the debug tuning panel edits it).
///
/// One tell and one exception. The tell is the stare: with nothing else
/// showing, the pet strikes the spot it stares at with `followStare` and
/// splits the rest between the other two. The exception is visible on the
/// frozen frame in about one block in three (`exceptionChance`), always on
/// a spot the pet is not staring at: a wobbling object (it teeters on the
/// home screen) or, as an alternative to try, the breed's appetite (scent
/// lines over its favorite object). When it shows it decides the strike
/// with `exceptionPull`; otherwise the stare rule still applies. So the
/// defaults read as "where she stares, unless something wobbles", and a
/// wobble is a strong lean rather than a sure thing:
///
/// - nothing wobbling: 62% the stare, 19% each other spot;
/// - a wobble: 79.75% the wobble, 15.5% the stare, 4.75% the third spot.
///
/// A player who always follows the stare catches about 46%, one who picks
/// at random 33%, and one who reads the wobble when it shows about 68%
/// (`PetCamReadTests` pins those bands), so reading the room is worth it
/// without the stare ever being a coin flip, and IT WAS ALREADY WOBBLING.
/// stays a punchline. The stake that makes the other blocks a choice is
/// not in the read at all: it is the WANTED object (`PetCamSetup.wanted`).
public struct PetCamTuning: Codable, Hashable, Sendable {
    /// Which visible exception can override the stare.
    public enum Exception: String, Codable, CaseIterable, Hashable, Sendable {
        /// The base rule only.
        case none
        /// Some blocks, one object teeters on its spot.
        case wobble
        /// Some blocks, the pet's favorite object (by species) smells too
        /// good, shown as scent lines, if it is in the room and not where
        /// the pet stares.
        case appetite
    }

    /// With no exception showing, the chance the pet strikes where it stares.
    public var followStare: Double
    public var exception: Exception
    /// Chance per block that the exception shows at all.
    public var exceptionChance: Double
    /// When the exception shows, the chance it decides the strike.
    public var exceptionPull: Double
    /// The object each species cannot resist, for the appetite exception.
    public var catAppetite: PetCamObjectKind
    public var dogAppetite: PetCamObjectKind

    public init(followStare: Double = 0.62, exception: Exception = .wobble, exceptionChance: Double = 0.34,
                exceptionPull: Double = 0.75, catAppetite: PetCamObjectKind = .fishbowl,
                dogAppetite: PetCamObjectKind = .donut) {
        self.followStare = Self.chance(followStare)
        self.exception = exception
        self.exceptionChance = Self.chance(exceptionChance)
        self.exceptionPull = Self.chance(exceptionPull)
        self.catAppetite = catAppetite
        self.dogAppetite = dogAppetite
    }

    /// The tuning every prototype build starts from.
    public static let standard = PetCamTuning()

    private static func chance(_ value: Double) -> Double {
        min(max(value.isFinite ? value : 0, 0), 1)
    }

    public func appetite(for species: PetSpecies) -> PetCamObjectKind {
        species == .cat ? catAppetite : dogAppetite
    }

    /// The chance of a strike on each spot, given the stare and the
    /// exception's spot (nil when none shows). Always sums to 1.
    public func strikeChances(stare: PetCamSpot, exception spot: PetCamSpot?) -> [PetCamSpot: Double] {
        var chances: [PetCamSpot: Double] = [:]
        for candidate in PetCamSpot.allCases {
            chances[candidate] = candidate == stare ? followStare : (1 - followStare) / 2
        }
        guard let spot else { return chances }
        // The exception wins with its pull; the rest of the time the stare
        // rule plays out as if it were not there.
        return chances.mapValues { $0 * (1 - exceptionPull) }
            .merging([spot: exceptionPull]) { $0 + $1 }
    }

    // Forgiving decoding: a missing key keeps its default, so a tuning
    // saved by an older panel still loads.
    private enum CodingKeys: String, CodingKey {
        case followStare, exception, exceptionChance, exceptionPull, catAppetite, dogAppetite
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = PetCamTuning.standard
        self.init(
            followStare: (try? container.decode(Double.self, forKey: .followStare)) ?? standard.followStare,
            exception: (try? container.decode(Exception.self, forKey: .exception)) ?? standard.exception,
            exceptionChance: (try? container.decode(Double.self, forKey: .exceptionChance)) ?? standard.exceptionChance,
            exceptionPull: (try? container.decode(Double.self, forKey: .exceptionPull)) ?? standard.exceptionPull,
            catAppetite: (try? container.decode(PetCamObjectKind.self, forKey: .catAppetite)) ?? standard.catAppetite,
            dogAppetite: (try? container.decode(PetCamObjectKind.self, forKey: .dogAppetite)) ?? standard.dogAppetite
        )
    }
}

/// The visible exception in one block: which kind and on which spot.
public struct PetCamTell: Codable, Hashable, Sendable {
    public var exception: PetCamTuning.Exception
    public var spot: PetCamSpot

    public init(exception: PetCamTuning.Exception, spot: PetCamSpot) {
        self.exception = exception
        self.spot = spot
    }
}

/// A block as the home screen shows it before Start: the seed, where the
/// pet stares, and any exception, all drawn from the seed, the WANTED
/// object, plus the tuning in force when it was prepared.
///
/// The setup is saved, so reopening the app shows the same frozen frame,
/// and it survives a block stopped early: stopping never rerolls the tell,
/// so there is nothing to farm by starting and stopping.
public struct PetCamSetup: Codable, Hashable, Sendable {
    public var seed: UInt64
    public var stare: PetCamSpot
    public var tell: PetCamTell?
    /// The spot whose object wears the WANTED tag. From the second block
    /// on, when nothing wobbles, it is whichever of the two objects the pet
    /// is not eyeing it has gone longer without being caught with (a kind
    /// never caught with counts as longest; ties to the seed). A block with
    /// a visible exception has no tag at all, so a frame never shows more
    /// than two things to read. It never changes where the pet strikes: it
    /// is the stake that turns every block with nothing wobbling into one
    /// choice, the likely catch on the stare or the one the wall lacks.
    public var wanted: PetCamSpot?
    public var tuning: PetCamTuning
    public var preparedAt: Date

    public init(seed: UInt64, stare: PetCamSpot, tell: PetCamTell?, wanted: PetCamSpot? = nil, tuning: PetCamTuning,
                preparedAt: Date) {
        self.seed = seed
        self.stare = stare
        self.tell = tell
        self.wanted = wanted
        self.tuning = tuning
        self.preparedAt = preparedAt
    }

    /// Draws the stare and the exception for `room` from `seed`. The stare
    /// is a fair pick of the three spots; the exception shows with
    /// `tuning.exceptionChance`, never on the stared spot (it would tell
    /// nothing the stare does not): a wobble on one of the other two, or
    /// the appetite on the spot holding the species' favorite object (none
    /// if that object is not in the room or is the one stared at). The
    /// WANTED object comes from `history` (none before the first tape).
    public static func prepare(seed: UInt64, room: PetCamRoom, species: PetSpecies, tuning: PetCamTuning,
                               history: [PetCamBlockRecord] = [], at date: Date) -> PetCamSetup {
        var stareRoll = PetCamRandom(seed: seed, stream: "stare")
        let spots = PetCamSpot.allCases
        let stare = spots[Int(stareRoll.next() % UInt64(spots.count))]
        var tellRoll = PetCamRandom(seed: seed, stream: "tell")
        var tell: PetCamTell?
        if tuning.exception != .none, tellRoll.unit() < tuning.exceptionChance {
            switch tuning.exception {
            case .none:
                break
            case .wobble:
                let others = spots.filter { $0 != stare }
                tell = PetCamTell(exception: .wobble, spot: others[Int(tellRoll.next() % UInt64(others.count))])
            case .appetite:
                let favorite = tuning.appetite(for: species)
                if let spot = spots.first(where: { $0 != stare && room.object(at: $0)?.kind == favorite }) {
                    tell = PetCamTell(exception: .appetite, spot: spot)
                }
            }
        }
        return PetCamSetup(seed: seed, stare: stare, tell: tell,
                           wanted: wanted(seed: seed, room: room, stare: stare, tell: tell, history: history, at: date),
                           tuning: tuning, preparedAt: date)
    }

    /// The WANTED spot for `room` after `history` (see `wanted`).
    static func wanted(seed: UInt64, room: PetCamRoom, stare: PetCamSpot, tell: PetCamTell?,
                       history: [PetCamBlockRecord], at date: Date) -> PetCamSpot? {
        guard tell == nil, history.contains(where: \.outcome.hasTape) else { return nil }
        let waits = PetCamSpot.allCases.filter { $0 != stare }.compactMap { spot in
            room.object(at: spot).map { (spot, wantedSince($0.kind, history: history, before: date) ?? .distantPast) }
        }
        guard let longest = waits.map(\.1).min() else { return nil }
        let tied = waits.filter { $0.1 == longest }.map(\.0)
        var roll = PetCamRandom(seed: seed, stream: "wanted")
        return tied[Int(roll.next() % UInt64(tied.count))]
    }

    /// Since when the pet has gone without being caught with `kind` before
    /// `date`: its last catch with one, or (never caught with one) the
    /// first tape, when the surveillance began. Nil on a fresh history.
    public static func wantedSince(_ kind: PetCamObjectKind, history: [PetCamBlockRecord], before date: Date) -> Date? {
        // The log is sorted, so look back from the end and stop at the
        // first catch with one.
        for record in history.reversed() where record.endedAt < date {
            if record.outcome == .caught, record.struck?.kind == kind { return record.endedAt }
        }
        return history.first { $0.outcome.hasTape && $0.endedAt < date }?.startedAt
    }

    /// The chance of a strike on each spot in this block.
    public var strikeChances: [PetCamSpot: Double] {
        tuning.strikeChances(stare: stare, exception: tell?.spot)
    }

    /// Where the pet strikes: one weighted roll of the seed, the same every
    /// time, whatever the player picked. The pick never changes the pet.
    public var strike: PetCamSpot {
        var roll = PetCamRandom(seed: seed, stream: "strike")
        let chances = strikeChances
        return PetCamSpot.allCases[roll.pick(weights: PetCamSpot.allCases.map { chances[$0] ?? 0 })]
    }

    /// The seed of the setup after this one, so a whole run of blocks
    /// replays from the first seed.
    public var nextSeed: UInt64 {
        PetCamRandom.mix(seed ^ PetCamRandom.fnv1a("next"))
    }

    /// A short id for records and file names.
    public var id: String { PetCamSeed.text(seed) }

    // The seed is written as hex text: a JSON number above 2^53 loses its
    // low bits in a JavaScript port.
    private enum CodingKeys: String, CodingKey {
        case seed, stare, tell, wanted, tuning, preparedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let seed = PetCamSeed.parse(try container.decode(String.self, forKey: .seed)) else {
            throw DecodingError.dataCorruptedError(forKey: .seed, in: container, debugDescription: "Seed is not hex")
        }
        self.init(seed: seed, stare: try container.decode(PetCamSpot.self, forKey: .stare),
                  tell: try? container.decode(PetCamTell.self, forKey: .tell),
                  wanted: try? container.decode(PetCamSpot.self, forKey: .wanted),
                  tuning: (try? container.decode(PetCamTuning.self, forKey: .tuning)) ?? .standard,
                  preparedAt: try container.decode(Date.self, forKey: .preparedAt))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(PetCamSeed.text(seed), forKey: .seed)
        try container.encode(stare, forKey: .stare)
        try container.encodeIfPresent(tell, forKey: .tell)
        try container.encodeIfPresent(wanted, forKey: .wanted)
        try container.encode(tuning, forKey: .tuning)
        try container.encode(preparedAt, forKey: .preparedAt)
    }
}

/// Seeds as 16 hex digits, the form records store them in.
public enum PetCamSeed {
    public static func text(_ seed: UInt64) -> String {
        let digits = String(seed, radix: 16)
        return String(repeating: "0", count: max(0, 16 - digits.count)) + digits
    }

    public static func parse(_ text: String) -> UInt64? {
        UInt64(text, radix: 16)
    }
}
