import Foundation

/// The user's focus sound choice: up to `maxLayers` sounds, each with its
/// own level. An empty mix means "Off".
///
/// Always sanitized (unique sounds, levels clamped to 0...1, at most three
/// layers), including when decoded from settings someone edited by hand.
public struct FocusMix: Codable, Equatable, Sendable {
    public struct Layer: Codable, Equatable, Sendable {
        public var sound: FocusSound
        /// Relative level within the mix, 0...1.
        public var level: Float

        public init(sound: FocusSound, level: Float = 1) {
            self.sound = sound
            self.level = level
        }
    }

    /// Three layers is enough for a scene (rain + fireplace + cafe) without
    /// turning into mud.
    public static let maxLayers = 3

    public static let off = FocusMix()

    public private(set) var layers: [Layer]

    public init(_ layers: [Layer] = []) {
        var seen = Set<FocusSound>()
        self.layers = layers
            .filter { seen.insert($0.sound).inserted }
            .prefix(Self.maxLayers)
            .map { Layer(sound: $0.sound, level: Self.clamp($0.level)) }
    }

    /// A mix of one sound at full level.
    public static func single(_ sound: FocusSound) -> FocusMix {
        FocusMix([Layer(sound: sound)])
    }

    public var isOff: Bool { layers.isEmpty }

    public var canAddLayer: Bool { layers.count < Self.maxLayers }

    public func contains(_ sound: FocusSound) -> Bool {
        layers.contains { $0.sound == sound }
    }

    /// The level of `sound`, or nil when it isn't in the mix.
    public func level(of sound: FocusSound) -> Float? {
        layers.first { $0.sound == sound }?.level
    }

    /// Adds `sound` at full level, or removes it if present. Returns false
    /// (and changes nothing) when adding would exceed `maxLayers`.
    @discardableResult
    public mutating func toggle(_ sound: FocusSound) -> Bool {
        if let index = layers.firstIndex(where: { $0.sound == sound }) {
            layers.remove(at: index)
            return true
        }
        guard canAddLayer else { return false }
        layers.append(Layer(sound: sound))
        return true
    }

    /// Sets the level of a sound already in the mix; ignored otherwise.
    public mutating func setLevel(_ level: Float, for sound: FocusSound) {
        guard let index = layers.firstIndex(where: { $0.sound == sound }) else { return }
        layers[index].level = Self.clamp(level)
    }

    /// Short label for pickers and tooltips, e.g. "Rain + Fireplace".
    public var summary: String {
        isOff ? "Off" : layers.map(\.sound.displayName).joined(separator: " + ")
    }

    /// Linear gain for each sound in the mix.
    ///
    /// Layers are uncorrelated, so their powers add: two full layers would be
    /// 3 dB louder than one. When the summed power exceeds a single full
    /// layer, every gain is scaled down so the blend stays at the level of
    /// one sound and the master volume means the same thing for any mix.
    public var gains: [FocusSound: Float] {
        let power = layers.reduce(Float(0)) { $0 + $1.level * $1.level }
        let scale = power > 1 ? 1 / power.squareRoot() : 1
        return Dictionary(uniqueKeysWithValues: layers.map { ($0.sound, $0.level * scale) })
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey { case layers }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try container.decodeIfPresent([Layer].self, forKey: .layers) ?? [])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(layers, forKey: .layers)
    }

    private static func clamp(_ level: Float) -> Float {
        level.isFinite ? min(max(level, 0), 1) : 1
    }
}

/// Renders a `FocusMix` for the audio engine: per-layer crossfades with each
/// sound's loudness trim, master volume, a 2 s fade in and out, and a soft
/// clip on the sum.
///
/// Every sound's generator is created up front, so changing the mix, the
/// volume or the transport never allocates; the render path is safe to run
/// on the real-time audio thread. Layers at zero gain aren't rendered, and
/// once stopped and faded out the mixer outputs exact silence for free.
public struct FocusMixer: Sendable {
    /// Fade in, fade out and crossfade time between mixes.
    public static let fadeSeconds = 2.0
    /// Volume moves glide this quickly: fast enough to feel immediate,
    /// slow enough that dragging a slider never zips or clicks.
    public static let volumeGlideSeconds = 0.05

    public private(set) var mix: FocusMix = .off
    public private(set) var volume: Float
    public private(set) var isPlaying = false

    private let fadeSamples: Int
    private let volumeGlideSamples: Int
    private var generators: [FocusSoundGenerator]
    private var layerGains: [GainRamp]
    private var volumeGain: GainRamp
    private var transportGain = GainRamp(value: 0)

    public init(sampleRate: Double, volume: Float = 0.6, seed: UInt64 = 0x5EED) {
        fadeSamples = Int(sampleRate * Self.fadeSeconds)
        volumeGlideSamples = Int(sampleRate * Self.volumeGlideSeconds)
        // Distinct seeds so two layers never share a random stream.
        generators = FocusSound.allCases.enumerated().map { index, sound in
            FocusSoundGenerator(sound: sound, sampleRate: sampleRate, seed: seed &+ UInt64(index) &* 0x9E37_79B9)
        }
        layerGains = FocusSound.allCases.map { _ in GainRamp(value: 0) }
        let clamped = Self.clampVolume(volume)
        self.volume = clamped
        volumeGain = GainRamp(value: Self.amplitude(forVolume: clamped))
    }

    /// True once stopped and fully faded out: the output is exact silence
    /// and the audio engine can be shut down.
    public var isSilent: Bool {
        !isPlaying && !transportGain.isRamping && transportGain.value == 0
    }

    /// Maps the 0...1 volume control to amplitude. Loudness is roughly
    /// logarithmic, so a squared curve makes the slider feel even across its
    /// travel instead of doing everything in the bottom quarter.
    public static func amplitude(forVolume volume: Float) -> Float {
        let v = clampVolume(volume)
        return v * v
    }

    /// Switches to `mix`. While playing, sounds leaving fade out and sounds
    /// arriving fade in over `fadeSeconds`; while stopped it applies at once,
    /// since the transport fade covers the next start.
    public mutating func setMix(_ mix: FocusMix) {
        self.mix = mix
        let gains = mix.gains
        let length = isSilent ? 0 : fadeSamples
        for (index, sound) in FocusSound.allCases.enumerated() {
            let target = (gains[sound] ?? 0) * sound.loudnessGain
            if layerGains[index].target != target {
                layerGains[index].ramp(to: target, samples: length)
            }
        }
    }

    public mutating func setVolume(_ volume: Float) {
        self.volume = Self.clampVolume(volume)
        volumeGain.ramp(to: Self.amplitude(forVolume: self.volume), samples: volumeGlideSamples)
    }

    /// Fades in over `fadeSeconds`, from wherever a fade out had reached.
    public mutating func play() {
        guard !isPlaying else { return }
        isPlaying = true
        transportGain.ramp(to: 1, samples: fadeSamples)
    }

    /// Fades out over `fadeSeconds`; `isSilent` turns true when it lands.
    public mutating func stop() {
        guard isPlaying else { return }
        isPlaying = false
        transportGain.ramp(to: 0, samples: fadeSamples)
    }

    public mutating func next() -> Float {
        if isSilent { return 0 }
        var sum: Float = 0
        for index in generators.indices {
            let gain = layerGains[index].next()
            // Skip silent layers; their generators just resume when needed.
            if gain == 0 && !layerGains[index].isRamping { continue }
            sum += generators[index].next() * gain
        }
        return focusSoftClip(sum * volumeGain.next() * transportGain.next())
    }

    /// Renders `count` samples into `buffer`. Meant for the audio render
    /// callback, so it takes a raw pointer and never allocates.
    public mutating func render(into buffer: UnsafeMutablePointer<Float>, count: Int) {
        for i in 0..<count { buffer[i] = next() }
    }

    /// Fills `buffer` with consecutive samples.
    public mutating func fill(_ buffer: inout [Float]) {
        for i in buffer.indices { buffer[i] = next() }
    }

    private static func clampVolume(_ volume: Float) -> Float {
        volume.isFinite ? min(max(volume, 0), 1) : 0
    }
}
