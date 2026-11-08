import Foundation

/// The Pet Cam's only source of chance: SplitMix64 from a stored seed.
///
/// Every roll in a block (where the pet stares, which object wobbles, where
/// it strikes, which caption a callback picks) comes from the block's seed,
/// so a tape replays exactly from its record, tests can pin an outcome, and
/// a Mac or Windows port that reads the same record draws the same tape.
/// Swift's `Hasher` and `SystemRandomNumberGenerator` are never used for
/// game rolls: the first is seeded per process and the second is not
/// replayable.
public struct PetCamRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    /// A generator for one named roll of `seed`, so adding a roll later
    /// never shifts the ones that already exist ("stare" stays the same
    /// draw when a "caption" roll is added).
    public init(seed: UInt64, stream: String) {
        state = PetCamRandom.mix(seed ^ PetCamRandom.fnv1a(stream))
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        return PetCamRandom.mix(state)
    }

    /// A uniform double in 0..<1 from the top 53 bits.
    public mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    /// Index into `weights` picked in proportion to each weight. Negative
    /// weights count as zero; when every weight is zero the pick is uniform.
    public mutating func pick(weights: [Double]) -> Int {
        precondition(!weights.isEmpty, "Nothing to pick from")
        let clean = weights.map { $0.isFinite ? max($0, 0) : 0 }
        let total = clean.reduce(0, +)
        guard total > 0 else { return Int(next() % UInt64(weights.count)) }
        var roll = unit() * total
        for (index, weight) in clean.enumerated() {
            if roll < weight { return index }
            roll -= weight
        }
        return clean.lastIndex { $0 > 0 } ?? 0
    }

    /// The SplitMix64 finalizer: a fast, well-mixed bijection on 64 bits.
    public static func mix(_ value: UInt64) -> UInt64 {
        var z = value
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 64-bit FNV-1a of a label's UTF-8 bytes: stable across runs and
    /// platforms, unlike `Hasher`.
    public static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return hash
    }
}
