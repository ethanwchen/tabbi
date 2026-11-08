import Foundation

/// How the pet decides where to strike, as data, so playtests can compare
/// variants without a code change (the debug tuning panel edits it).
///
/// The base rule is a weight per spot: the spot the pet stares at gets
/// `stareWeight`, the other two `otherWeight` each. One visible exception
/// can add `exceptionWeight` to a spot: a wobbling object (it teeters on
/// the home screen) or, as an alternative to try, the breed's appetite
/// (scent lines over its favorite object). The chance of each spot is its
/// weight over the total, so the default reads as "usually where she
/// stares, unless something wobbles":
///
/// - nothing wobbling: 60% the stare, 20% each other spot;
/// - a wobble elsewhere: 37.5% the stare, 50% the wobble, 12.5% the rest;
/// - a wobble on the stared spot: 75% there.
///
/// `PetCamReadTests` plays scripted players against these numbers and
/// keeps the read between a coin flip and a solved puzzle.
public struct PetCamTuning: Codable, Hashable, Sendable {
    /// Which visible exception can override the stare.
    public enum Exception: String, Codable, CaseIterable, Hashable, Sendable {
        /// The base rule only.
        case none
        /// Some blocks, one object teeters on its spot.
        case wobble
        /// Some blocks, the pet's favorite object (by species) smells too
        /// good, shown as scent lines, if it is in the room.
        case appetite
    }

    public var stareWeight: Double
    public var otherWeight: Double
    public var exception: Exception
    /// Chance per block that the exception shows at all.
    public var exceptionChance: Double
    /// Weight the exception adds to its spot.
    public var exceptionWeight: Double
    /// The object each species cannot resist, for the appetite exception.
    public var catAppetite: PetCamObjectKind
    public var dogAppetite: PetCamObjectKind

    public init(stareWeight: Double = 6, otherWeight: Double = 2, exception: Exception = .wobble,
                exceptionChance: Double = 0.35, exceptionWeight: Double = 6,
                catAppetite: PetCamObjectKind = .fishbowl, dogAppetite: PetCamObjectKind = .donut) {
        self.stareWeight = Self.weight(stareWeight)
        self.otherWeight = Self.weight(otherWeight)
        self.exception = exception
        self.exceptionChance = min(max(exceptionChance.isFinite ? exceptionChance : 0, 0), 1)
        self.exceptionWeight = Self.weight(exceptionWeight)
        self.catAppetite = catAppetite
        self.dogAppetite = dogAppetite
    }

    /// The tuning every prototype build starts from.
    public static let standard = PetCamTuning()

    /// The heaviest weight the panel allows, so a typo cannot make one
    /// spot certain by accident.
    public static let maximumWeight = 20.0

    private static func weight(_ value: Double) -> Double {
        min(max(value.isFinite ? value : 0, 0), maximumWeight)
    }

    public func appetite(for species: PetSpecies) -> PetCamObjectKind {
        species == .cat ? catAppetite : dogAppetite
    }

    /// The chance of a strike on each spot, given the stare and the
    /// exception's spot (nil when none shows). Always sums to 1.
    public func strikeChances(stare: PetCamSpot, exception spot: PetCamSpot?) -> [PetCamSpot: Double] {
        var weights: [PetCamSpot: Double] = [:]
        for candidate in PetCamSpot.allCases {
            var weight = candidate == stare ? stareWeight : otherWeight
            if candidate == spot { weight += exceptionWeight }
            weights[candidate] = weight
        }
        let total = weights.values.reduce(0, +)
        guard total > 0 else {
            return Dictionary(uniqueKeysWithValues: PetCamSpot.allCases.map { ($0, 1.0 / 3) })
        }
        return weights.mapValues { $0 / total }
    }

    // Forgiving decoding: a missing key keeps its default, so a tuning
    // saved by an older panel still loads.
    private enum CodingKeys: String, CodingKey {
        case stareWeight, otherWeight, exception, exceptionChance, exceptionWeight, catAppetite, dogAppetite
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = PetCamTuning.standard
        self.init(
            stareWeight: (try? container.decode(Double.self, forKey: .stareWeight)) ?? standard.stareWeight,
            otherWeight: (try? container.decode(Double.self, forKey: .otherWeight)) ?? standard.otherWeight,
            exception: (try? container.decode(Exception.self, forKey: .exception)) ?? standard.exception,
            exceptionChance: (try? container.decode(Double.self, forKey: .exceptionChance)) ?? standard.exceptionChance,
            exceptionWeight: (try? container.decode(Double.self, forKey: .exceptionWeight)) ?? standard.exceptionWeight,
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
/// pet stares, and any exception, all drawn from the seed, plus the tuning
/// in force when it was prepared.
///
/// The setup is saved, so reopening the app shows the same frozen frame,
/// and it survives a block stopped early: stopping never rerolls the tell,
/// so there is nothing to farm by starting and stopping.
public struct PetCamSetup: Codable, Hashable, Sendable {
    public var seed: UInt64
    public var stare: PetCamSpot
    public var tell: PetCamTell?
    public var tuning: PetCamTuning
    public var preparedAt: Date

    public init(seed: UInt64, stare: PetCamSpot, tell: PetCamTell?, tuning: PetCamTuning, preparedAt: Date) {
        self.seed = seed
        self.stare = stare
        self.tell = tell
        self.tuning = tuning
        self.preparedAt = preparedAt
    }

    /// Draws the stare and the exception for `room` from `seed`. The stare
    /// is a fair pick of the three spots; the exception shows with
    /// `tuning.exceptionChance`: a wobble on any spot, or the appetite on
    /// the spot holding the species' favorite object (none if it is not in
    /// the room).
    public static func prepare(seed: UInt64, room: PetCamRoom, species: PetSpecies, tuning: PetCamTuning,
                               at date: Date) -> PetCamSetup {
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
                tell = PetCamTell(exception: .wobble, spot: spots[Int(tellRoll.next() % UInt64(spots.count))])
            case .appetite:
                let favorite = tuning.appetite(for: species)
                if let spot = spots.first(where: { room.object(at: $0)?.kind == favorite }) {
                    tell = PetCamTell(exception: .appetite, spot: spot)
                }
            }
        }
        return PetCamSetup(seed: seed, stare: stare, tell: tell, tuning: tuning, preparedAt: date)
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
        case seed, stare, tell, tuning, preparedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let seed = PetCamSeed.parse(try container.decode(String.self, forKey: .seed)) else {
            throw DecodingError.dataCorruptedError(forKey: .seed, in: container, debugDescription: "Seed is not hex")
        }
        self.init(seed: seed, stare: try container.decode(PetCamSpot.self, forKey: .stare),
                  tell: try? container.decode(PetCamTell.self, forKey: .tell),
                  tuning: (try? container.decode(PetCamTuning.self, forKey: .tuning)) ?? .standard,
                  preparedAt: try container.decode(Date.self, forKey: .preparedAt))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(PetCamSeed.text(seed), forKey: .seed)
        try container.encode(stare, forKey: .stare)
        try container.encodeIfPresent(tell, forKey: .tell)
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
