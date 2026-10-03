import Foundation

// Small, allocation-free DSP building blocks for the focus sound engine.
// Everything here is a value type with a per-sample `next`/`process` call so
// it can run inside a real-time audio render callback without locks.

/// Seedable xorshift64* generator, fast enough to call per audio sample.
///
/// `SystemRandomNumberGenerator` can block and isn't meant for the audio
/// thread; a fixed seed also makes the spectral tests deterministic.
public struct NoiseRandom: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        // A zero state would stay zero forever.
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    public mutating func nextUInt64() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545_F491_4F6C_DD1D
    }

    /// Uniform in 0 ..< 1.
    public mutating func nextUnit() -> Float {
        Float(nextUInt64() >> 40) / Float(1 << 24)
    }

    /// Uniform in -1 ..< 1 (variance 1/3).
    public mutating func nextBipolar() -> Float {
        nextUnit() * 2 - 1
    }
}

/// First-order low- or high-pass filter: cheap, gentle 6 dB/octave slope.
public struct OnePoleFilter: Sendable {
    public enum Kind: Sendable { case lowPass, highPass }

    public let kind: Kind
    private let a: Float
    private var low: Float = 0

    public init(kind: Kind, cutoff: Double, sampleRate: Double) {
        self.kind = kind
        let clamped = min(max(cutoff, 1), sampleRate * 0.49)
        a = Float(exp(-2 * Double.pi * clamped / sampleRate))
    }

    public mutating func process(_ x: Float) -> Float {
        low = (1 - a) * x + a * low
        return kind == .lowPass ? low : x - low
    }
}

/// Second-order filter from the RBJ "Audio EQ Cookbook" (direct form I).
///
/// Used where a one-pole slope is too soft: shaping rain hiss, the murmur
/// band of a cafe, the rumble under a fire.
public struct BiquadFilter: Sendable {
    public enum Kind: Sendable { case lowPass, highPass, bandPass }

    private let b0, b1, b2, a1, a2: Float
    private var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

    /// - Parameter q: resonance; 0.707 is maximally flat (Butterworth).
    ///   For band-pass the peak gain is 0 dB and bandwidth is `frequency / q`.
    public init(kind: Kind, frequency: Double, q: Double = 0.7071, sampleRate: Double) {
        let f = min(max(frequency, 1), sampleRate * 0.49)
        let w0 = 2 * Double.pi * f / sampleRate
        let cosW = cos(w0)
        let alpha = sin(w0) / (2 * max(q, 0.01))
        let nb0, nb1, nb2: Double
        switch kind {
        case .lowPass:
            nb0 = (1 - cosW) / 2; nb1 = 1 - cosW; nb2 = (1 - cosW) / 2
        case .highPass:
            nb0 = (1 + cosW) / 2; nb1 = -(1 + cosW); nb2 = (1 + cosW) / 2
        case .bandPass:
            nb0 = alpha; nb1 = 0; nb2 = -alpha
        }
        let a0 = 1 + alpha
        b0 = Float(nb0 / a0); b1 = Float(nb1 / a0); b2 = Float(nb2 / a0)
        a1 = Float(-2 * cosW / a0); a2 = Float((1 - alpha) / a0)
    }

    public mutating func process(_ x: Float) -> Float {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x
        y2 = y1; y1 = y
        return y
    }
}

/// A gain that glides to its target instead of jumping, so fades and volume
/// changes never click.
///
/// Uses a raised-cosine (S-shaped) curve: zero slope at both ends means no
/// audible corner where the fade starts or lands, which a linear ramp has.
public struct GainRamp: Sendable {
    public private(set) var value: Float
    public private(set) var target: Float
    private var start: Float
    private var position = 0
    private var length = 0

    public init(value: Float = 0) {
        self.value = value
        target = value
        start = value
    }

    /// True while gliding toward `target`.
    public var isRamping: Bool { position < length }

    /// Begins gliding from the current value to `target` over `samples`.
    /// Retargeting mid-ramp starts from wherever the gain is now.
    public mutating func ramp(to target: Float, samples: Int) {
        start = value
        self.target = target
        position = 0
        length = max(samples, 0)
        if length == 0 { value = target }
    }

    /// Advances one sample and returns the gain to apply to it.
    public mutating func next() -> Float {
        guard position < length else { return value }
        position += 1
        let t = Float(position) / Float(length)
        let shaped = 0.5 - 0.5 * cos(Float.pi * t)
        value = start + (target - start) * shaped
        if position == length { value = target }
        return value
    }
}

/// Soft clipper that keeps summed layers inside -1 ... 1 without a hard
/// edge.
///
/// Exactly linear up to the knee at ±0.5, so normal levels (0.2 RMS) pass
/// untouched; only rare transient peaks bend, along a tanh curve that meets
/// the line with the same slope so the knee itself adds no distortion.
@inlinable
public func focusSoftClip(_ x: Float) -> Float {
    let knee: Float = 0.5
    let magnitude = abs(x)
    guard magnitude > knee else { return x }
    let bent = knee + (1 - knee) * tanh((magnitude - knee) / (1 - knee))
    return x < 0 ? -bent : bent
}
