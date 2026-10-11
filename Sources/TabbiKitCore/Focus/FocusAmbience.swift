import Foundation

// Procedural ambiences for focus mode: rain and fireplace. The cafe is a
// recording (FocusRecording.swift), since no synthesized crowd sounded human.
//
// Each follows the layered recipes from Andy Farnell's "Designing Sound":
// a steady filtered-noise bed, slow random modulation so it never sounds
// like a loop, and sparse random events (drops, crackles) built from
// short decaying bursts. Like the noise colors, every ambience is calibrated
// to `NoiseGenerator.targetRMS` so layers mix at predictable levels. All of
// it is allocation-free per sample so it can run on the audio thread.

/// A smoothly wandering random value, used for gusts of rain, flicker of a
/// fire, and the ebb of a room's chatter.
struct Drift: Sendable {
    private var value: Float
    private var target: Float
    private let lower: Float
    private let span: Float
    private let smoothing: Float
    private let meanHold: Float
    private var countdown = 0

    /// - Parameter seconds: rough time scale of a change; a new target is
    ///   picked every 0.5–1.5× this, and the value glides there.
    init(range: ClosedRange<Float>, seconds: Double, sampleRate: Double) {
        lower = range.lowerBound
        span = range.upperBound - range.lowerBound
        value = lower + span / 2
        target = value
        meanHold = Float(seconds * sampleRate)
        smoothing = Float(1 - exp(-2 / (seconds * sampleRate)))
    }

    mutating func next(_ random: inout NoiseRandom) -> Float {
        countdown -= 1
        if countdown <= 0 {
            target = lower + span * random.nextUnit()
            countdown = Int(meanHold * (0.5 + random.nextUnit()))
        }
        value += (target - value) * smoothing
        return value
    }
}

/// One short, exponentially decaying burst of band-passed noise: a raindrop
/// tick or a crackle of burning wood.
struct BurstVoice: Sendable {
    private(set) var level: Float = 0
    private var decay: Float = 0
    private var filter = BiquadFilter(kind: .bandPass, frequency: 1000, sampleRate: 48_000)

    var isActive: Bool { level > 1e-4 }

    mutating func trigger(level: Float, decaySeconds: Float, frequency: Float, q: Float, sampleRate: Double) {
        self.level = level
        decay = Float(exp(-1 / (Double(decaySeconds) * sampleRate)))
        filter = BiquadFilter(kind: .bandPass, frequency: Double(frequency), q: Double(q), sampleRate: sampleRate)
    }

    mutating func next(_ random: inout NoiseRandom) -> Float {
        guard isActive else { return 0 }
        let y = filter.process(random.nextBipolar() * level)
        level *= decay
        return y
    }
}

/// A fixed pool of burst voices; a new event takes a free voice or steals
/// the quietest one, so dense events never allocate.
struct BurstPool: Sendable {
    private var voices: [BurstVoice]

    init(size: Int) {
        voices = Array(repeating: BurstVoice(), count: size)
    }

    mutating func trigger(level: Float, decaySeconds: Float, frequency: Float, q: Float, sampleRate: Double) {
        var slot = 0
        for i in voices.indices where voices[i].level < voices[slot].level { slot = i }
        voices[slot].trigger(level: level, decaySeconds: decaySeconds, frequency: frequency, q: q, sampleRate: sampleRate)
    }

    mutating func next(_ random: inout NoiseRandom) -> Float {
        var sum: Float = 0
        for i in voices.indices { sum += voices[i].next(&random) }
        return sum
    }
}

// MARK: - Rain

/// Steady rain: a pink-noise hiss (the wash of countless distant drops), a
/// soft low wash, and individual nearby drops as resonant ticks whose rate
/// and loudness rise and fall with slow gusts.
struct RainSynth: Sendable {
    private let sampleRate: Double
    private var random: NoiseRandom
    private var hiss: NoiseGenerator
    private var hissHighPass: BiquadFilter
    private var hissLowPass: BiquadFilter
    private var wash: NoiseGenerator
    private var washLowPass: BiquadFilter
    private var gust: Drift
    private var drops = BurstPool(size: 12)
    private let dropChance: Float

    /// Calibrated so the long-term RMS matches `NoiseGenerator.targetRMS`.
    private static let outputGain: Float = 1.38

    init(sampleRate: Double, seed: UInt64) {
        self.sampleRate = sampleRate
        random = NoiseRandom(seed: seed ^ 0xA11)
        hiss = NoiseGenerator(color: .pink, sampleRate: sampleRate, seed: seed &+ 1)
        hissHighPass = BiquadFilter(kind: .highPass, frequency: 500, sampleRate: sampleRate)
        hissLowPass = BiquadFilter(kind: .lowPass, frequency: 9_000, sampleRate: sampleRate)
        wash = NoiseGenerator(color: .brown, sampleRate: sampleRate, seed: seed &+ 2)
        washLowPass = BiquadFilter(kind: .lowPass, frequency: 400, sampleRate: sampleRate)
        gust = Drift(range: 0.7...1.0, seconds: 3, sampleRate: sampleRate)
        dropChance = Float(60 / sampleRate)
    }

    mutating func next() -> Float {
        let intensity = gust.next(&random)
        var y = hissLowPass.process(hissHighPass.process(hiss.next())) * 1.1 * intensity
        y += washLowPass.process(wash.next()) * 0.35
        if random.nextUnit() < dropChance * intensity {
            // Squaring skews toward quiet drops with the odd close, loud one.
            let loudness = random.nextUnit()
            drops.trigger(
                level: 0.2 + 1.1 * loudness * loudness,
                decaySeconds: 0.003 + 0.01 * random.nextUnit(),
                frequency: 1_800 + 5_000 * random.nextUnit(),
                q: 2 + 4 * random.nextUnit(),
                sampleRate: sampleRate)
        }
        y += drops.next(&random)
        return y * Self.outputGain
    }
}

// MARK: - Fireplace

/// A wood fire: a deep, slowly breathing roar, a flickering mid-band body,
/// a faint hiss, and bursty crackles with the occasional louder pop.
struct FireplaceSynth: Sendable {
    private let sampleRate: Double
    private var random: NoiseRandom
    private var roar: NoiseGenerator
    private var roarLowPass: BiquadFilter
    private var body: NoiseGenerator
    private var bodyBand: BiquadFilter
    private var hissHighPass: BiquadFilter
    private var breath: Drift
    private var flicker: Drift
    private var crackleRate: Drift
    private var crackles = BurstPool(size: 8)
    /// Remaining clicks in the current crackle cluster, and samples until the next.
    private var pendingClicks = 0
    private var clusterGap = 0

    private static let outputGain: Float = 1.06

    init(sampleRate: Double, seed: UInt64) {
        self.sampleRate = sampleRate
        random = NoiseRandom(seed: seed ^ 0xF12E)
        roar = NoiseGenerator(color: .brown, sampleRate: sampleRate, seed: seed &+ 3)
        roarLowPass = BiquadFilter(kind: .lowPass, frequency: 160, sampleRate: sampleRate)
        body = NoiseGenerator(color: .pink, sampleRate: sampleRate, seed: seed &+ 4)
        bodyBand = BiquadFilter(kind: .bandPass, frequency: 500, q: 0.8, sampleRate: sampleRate)
        hissHighPass = BiquadFilter(kind: .highPass, frequency: 3_000, sampleRate: sampleRate)
        breath = Drift(range: 0.55...1.0, seconds: 1.5, sampleRate: sampleRate)
        flicker = Drift(range: 0.2...1.0, seconds: 0.12, sampleRate: sampleRate)
        crackleRate = Drift(range: 1.5...9, seconds: 2.5, sampleRate: sampleRate)
    }

    mutating func next() -> Float {
        let glow = flicker.next(&random)
        var y = roarLowPass.process(roar.next()) * 1.2 * breath.next(&random)
        y += bodyBand.process(body.next()) * 0.6 * glow
        y += hissHighPass.process(random.nextBipolar()) * 0.04 * glow * glow

        // Crackles arrive in small clusters, like wood splitting.
        if pendingClicks == 0, random.nextUnit() < crackleRate.next(&random) / Float(sampleRate) {
            pendingClicks = 1 + Int(random.nextUnit() * 4)
            clusterGap = 0
        }
        if pendingClicks > 0 {
            clusterGap -= 1
            if clusterGap <= 0 {
                triggerCrackle()
                pendingClicks -= 1
                clusterGap = Int(Float(sampleRate) * (0.002 + 0.02 * random.nextUnit()))
            }
        }
        y += crackles.next(&random)
        return y * Self.outputGain
    }

    private mutating func triggerCrackle() {
        let loudness = random.nextUnit()
        if random.nextUnit() < 0.12 {
            // A deeper pop: a pocket of sap bursting.
            crackles.trigger(
                level: 0.6 + 0.8 * loudness,
                decaySeconds: 0.015 + 0.025 * random.nextUnit(),
                frequency: 250 + 450 * random.nextUnit(),
                q: 2,
                sampleRate: sampleRate)
        } else {
            crackles.trigger(
                level: 0.3 + 1.2 * loudness * loudness,
                decaySeconds: 0.0015 + 0.008 * random.nextUnit(),
                frequency: 1_200 + 4_300 * random.nextUnit(),
                q: 1.5 + 1.5 * random.nextUnit(),
                sampleRate: sampleRate)
        }
    }
}
