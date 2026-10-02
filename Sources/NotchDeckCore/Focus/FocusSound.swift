import Foundation

/// A procedurally generated focus sound. "Off" is not a case: it is an
/// empty mix, so a mix of layers covers every choice uniformly.
public enum FocusSound: String, CaseIterable, Codable, Sendable, Identifiable {
    case brown
    case pink
    case white
    case rain
    case fireplace
    case cafe

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .brown: "Brown noise"
        case .pink: "Pink noise"
        case .white: "White noise"
        case .rain: "Rain"
        case .fireplace: "Fireplace"
        case .cafe: "Cafe murmur"
        }
    }

    /// SF Symbol shown next to the sound in pickers.
    public var symbolName: String {
        switch self {
        case .brown: "water.waves"
        case .pink: "wind"
        case .white: "waveform"
        case .rain: "cloud.rain"
        case .fireplace: "flame"
        case .cafe: "cup.and.saucer"
        }
    }
}

/// Renders any `FocusSound`, sample by sample, at about
/// `NoiseGenerator.targetRMS`.
///
/// Holds one optional synth per kind rather than an enum with payloads:
/// mutating an optional in place never copies, whereas pulling a payload out
/// of an enum would copy its voice arrays (and allocate) on every sample.
public struct FocusSoundGenerator: Sendable {
    public let sound: FocusSound
    private var noise: NoiseGenerator?
    private var rain: RainSynth?
    private var fireplace: FireplaceSynth?
    private var cafe: CafeSynth?

    public init(sound: FocusSound, sampleRate: Double, seed: UInt64 = 0x5EED) {
        self.sound = sound
        switch sound {
        case .brown: noise = NoiseGenerator(color: .brown, sampleRate: sampleRate, seed: seed)
        case .pink: noise = NoiseGenerator(color: .pink, sampleRate: sampleRate, seed: seed)
        case .white: noise = NoiseGenerator(color: .white, sampleRate: sampleRate, seed: seed)
        case .rain: rain = RainSynth(sampleRate: sampleRate, seed: seed)
        case .fireplace: fireplace = FireplaceSynth(sampleRate: sampleRate, seed: seed)
        case .cafe: cafe = CafeSynth(sampleRate: sampleRate, seed: seed)
        }
    }

    public mutating func next() -> Float {
        switch sound {
        case .brown, .pink, .white: noise?.next() ?? 0
        case .rain: rain?.next() ?? 0
        case .fireplace: fireplace?.next() ?? 0
        case .cafe: cafe?.next() ?? 0
        }
    }

    /// Fills `buffer` with consecutive samples.
    public mutating func fill(_ buffer: inout [Float]) {
        for i in buffer.indices { buffer[i] = next() }
    }
}
