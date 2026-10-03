import Foundation

/// The three "colors" of broadband noise, each normalized to the same
/// loudness so switching between them doesn't jump in volume.
public enum NoiseColor: String, CaseIterable, Codable, Sendable {
    /// Flat spectrum: equal power per hertz. Bright, hissy.
    case white
    /// Power falls 3 dB per octave (1/f): equal power per octave. Balanced, like steady rain.
    case pink
    /// Power falls 6 dB per octave (1/f²). Deep, like a distant waterfall.
    case brown
}

/// Generates one color of noise, sample by sample, at a fixed RMS level.
public struct NoiseGenerator: Sendable {
    /// Every color targets this RMS so they sound about equally loud and
    /// leave headroom for mixing several layers.
    public static let targetRMS: Float = 0.2
    /// Uniform white in -1 ..< 1 has RMS 1/√3.
    private static let whiteRMS: Float = 1 / Float(3).squareRoot()

    public let color: NoiseColor
    private var random: NoiseRandom
    private var pink = PinkState()
    private var brown: Float = 0
    private let brownCoefficient: Float
    private let brownGain: Float
    private var lowCut: OnePoleFilter

    public init(color: NoiseColor, sampleRate: Double, seed: UInt64 = 0x5EED) {
        self.color = color
        random = NoiseRandom(seed: seed)
        // Brown noise is integrated white noise. A pure integrator drifts
        // without bound, so leak it: a one-pole low-pass with a corner far
        // below the audible range gives a true 1/f² slope across it.
        let leakCorner = 10.0, lowCutCorner = 20.0
        let a = exp(-2 * Double.pi * leakCorner / sampleRate)
        brownCoefficient = Float(a)
        // The leaky integrator shrinks white variance by (1-a)/(1+a); the
        // low cut then keeps leak/(leak+lowCut) of what's left (the integral
        // of the two one-pole responses), so undo both.
        let survivingPower = (1 - a) / (1 + a) * leakCorner / (leakCorner + lowCutCorner)
        brownGain = Float((1 / survivingPower).squareRoot())
        // Inaudible DC/sub-bass would only eat headroom and move speaker cones.
        lowCut = OnePoleFilter(kind: .highPass, cutoff: lowCutCorner, sampleRate: sampleRate)
    }

    public mutating func next() -> Float {
        let white = random.nextBipolar()
        let raw: Float
        switch color {
        case .white:
            raw = white / Self.whiteRMS
        case .pink:
            raw = pink.process(white)
        case .brown:
            brown = brownCoefficient * brown + (1 - brownCoefficient) * white
            raw = brown * brownGain / Self.whiteRMS
        }
        return color == .white ? raw * Self.targetRMS : lowCut.process(raw) * Self.targetRMS
    }

    /// Fills `buffer` with consecutive samples.
    public mutating func fill(_ buffer: inout [Float]) {
        for i in buffer.indices { buffer[i] = next() }
    }
}

/// Paul Kellet's "refined" pink filter: seven parallel one-pole stages whose
/// staggered corners sum to a 1/f slope within ±0.05 dB from 9 Hz to Nyquist
/// (designed at 44.1 kHz; the error at 48 kHz stays well under 0.5 dB).
struct PinkState: Sendable {
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0
    private var b4: Float = 0, b5: Float = 0, b6: Float = 0

    /// Normalizes the filter's output to unit RMS for unit-variance input
    /// (measured; the stage gains sum to an RMS of about 2.66).
    private static let outputGain: Float = 0.3754

    mutating func process(_ white: Float) -> Float {
        let w = white * Float(3).squareRoot() // unit variance
        b0 = 0.99886 * b0 + w * 0.0555179
        b1 = 0.99332 * b1 + w * 0.0750759
        b2 = 0.96900 * b2 + w * 0.1538520
        b3 = 0.86650 * b3 + w * 0.3104856
        b4 = 0.55000 * b4 + w * 0.5329522
        b5 = -0.7616 * b5 - w * 0.0168980
        let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362
        b6 = w * 0.115926
        return pink * Self.outputGain
    }
}
