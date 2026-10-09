import Foundation

// Procedural ambiences for focus mode: rain, fireplace, and a cafe.
//
// Each follows the layered recipes from Andy Farnell's "Designing Sound":
// a steady filtered-noise bed, slow random modulation so it never sounds
// like a loop, and sparse random events (drops, crackles, clinks) built from
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

// MARK: - Cafe

/// A two-pole resonator that can be retuned without resetting its state, so
/// a voice's formants glide from vowel to vowel the way a mouth moves,
/// instead of jumping (a fixed `BiquadFilter` would have to be rebuilt and
/// would click).
struct Resonator: Sendable {
    private var a1: Float = 0
    private var a2: Float = 0
    private var gain: Float = 0
    private var y1: Float = 0
    private var y2: Float = 0

    init(frequency: Float, bandwidth: Float, sampleRate: Double) {
        tune(frequency: frequency, bandwidth: bandwidth, sampleRate: sampleRate)
    }

    /// Peak gain stays near 1 whatever the frequency, so a vowel change
    /// shifts the colour of a voice but not its loudness.
    mutating func tune(frequency: Float, bandwidth: Float, sampleRate: Double) {
        let rate = Float(sampleRate)
        let r = exp(-Float.pi * bandwidth / rate)
        let theta = 2 * Float.pi * min(frequency, rate * 0.45) / rate
        a1 = -2 * r * cos(theta)
        a2 = r * r
        gain = (1 - r) * (1 - 2 * r * cos(2 * theta) + r * r).squareRoot()
    }

    mutating func process(_ x: Float) -> Float {
        let y = gain * x - a1 * y1 - a2 * y2
        y2 = y1
        y1 = y
        return y
    }
}

/// Formant frequencies (F1, F2, F3 in Hz) of common vowels for an adult
/// male voice, from Peterson and Barney's measurements. Other voices scale
/// them.
private let cafeVowels: [(Float, Float, Float)] = [
    (730, 1_090, 2_440),  // father
    (530, 1_840, 2_480),  // bed
    (270, 2_290, 3_010),  // see
    (570, 840, 2_410),    // law
    (300, 870, 2_240),    // boot
    (660, 1_720, 2_410),  // cat
    (500, 1_500, 2_500),  // the unstressed "uh"
    (440, 1_020, 2_240),  // book
]

/// One person talking a few tables away.
///
/// Built like a tiny speech synthesizer rather than a buzz: a soft glottal
/// pulse (a raised-cosine flow, far mellower than a sawtooth) with a little
/// breath, a pitch that rises on stressed syllables and falls toward the end
/// of each phrase, three formants that glide between real vowels, a short
/// consonant hiss at the start of most syllables, and phrases separated by
/// pauses. Heard through the room it reads as a human voice, but the
/// syllables are random, so no word is ever said.
struct Talker: Sendable {
    /// Samples between formant retunes: often enough for smooth glides,
    /// rare enough that the trigonometry stays cheap.
    private static let retuneInterval = 32

    private let sampleRate: Double
    /// Speaking pitch in Hz: men around 100-140, women around 180-240.
    private let basePitch: Float
    /// Vocal tract scale: shorter tracts (women's) have higher formants.
    private let formantScale: Float
    /// How close the talker sits: louder and brighter when near.
    let nearness: Float
    private var phase: Float = 0
    private var pitch: Float
    private var pitchTarget: Float
    private let pitchGlide: Float
    private var jitter: Drift
    private var formants: (Float, Float, Float)
    private var formantTargets: (Float, Float, Float)
    private let formantGlide: Float
    private var resonators: (Resonator, Resonator, Resonator)
    private var retuneCountdown = 0
    private var level: Float = 0
    private var levelTarget: Float = 0
    private let levelGlide: Float
    private var consonant = BurstVoice()
    private var muffle: OnePoleFilter
    private var syllableLength = 1
    private var syllablePosition = 0
    private var syllableLevel: Float = 0
    private var syllablesLeft = 0
    private var phraseLength = 1

    init(sampleRate: Double, random: inout NoiseRandom) {
        self.sampleRate = sampleRate
        let isHigher = random.nextUnit() < 0.5
        basePitch = isHigher ? 180 + 60 * random.nextUnit() : 100 + 40 * random.nextUnit()
        formantScale = isHigher ? 1.15 + 0.06 * random.nextUnit() : 0.97 + 0.06 * random.nextUnit()
        nearness = 0.45 + 0.55 * random.nextUnit()
        pitch = basePitch
        pitchTarget = basePitch
        pitchGlide = Float(1 - exp(-1 / (0.04 * sampleRate)))
        jitter = Drift(range: 0.985...1.015, seconds: 0.05, sampleRate: sampleRate)
        let vowel = cafeVowels[0]
        formants = (vowel.0 * formantScale, vowel.1 * formantScale, vowel.2 * formantScale)
        formantTargets = formants
        formantGlide = Float(1 - exp(-Double(Self.retuneInterval) / (0.03 * sampleRate)))
        resonators = (
            Resonator(frequency: formants.0, bandwidth: 90, sampleRate: sampleRate),
            Resonator(frequency: formants.1, bandwidth: 110, sampleRate: sampleRate),
            Resonator(frequency: formants.2, bandwidth: 160, sampleRate: sampleRate))
        levelGlide = Float(1 - exp(-1 / (0.018 * sampleRate)))
        // Farther talkers lose more of their top end to the room.
        muffle = OnePoleFilter(kind: .lowPass, cutoff: Double(1_500 + 2_500 * nearness), sampleRate: sampleRate)
        // Start somewhere in a pause so talkers never begin in unison.
        syllableLength = Int(Double(random.nextUnit()) * sampleRate * 0.8) + 1
    }

    mutating func next(_ random: inout NoiseRandom) -> Float {
        syllablePosition += 1
        if syllablePosition >= syllableLength { startSyllable(&random) }

        // The vowel sounds in the middle of the syllable; the gaps on either
        // side give speech its four or five beats a second.
        let t = Float(syllablePosition) / Float(syllableLength)
        levelTarget = t > 0.12 && t < 0.78 ? syllableLevel : 0
        level += (levelTarget - level) * levelGlide
        pitch += (pitchTarget - pitch) * pitchGlide

        retuneCountdown -= 1
        if retuneCountdown <= 0 {
            retuneCountdown = Self.retuneInterval
            formants.0 += (formantTargets.0 - formants.0) * formantGlide
            formants.1 += (formantTargets.1 - formants.1) * formantGlide
            formants.2 += (formantTargets.2 - formants.2) * formantGlide
            resonators.0.tune(frequency: formants.0, bandwidth: 90, sampleRate: sampleRate)
            resonators.1.tune(frequency: formants.1, bandwidth: 110, sampleRate: sampleRate)
            resonators.2.tune(frequency: formants.2, bandwidth: 160, sampleRate: sampleRate)
        }

        var output = consonant.next(&random)
        if level > 1e-4 {
            phase += pitch * jitter.next(&random) / Float(sampleRate)
            if phase >= 1 { phase -= 1 }
            // A raised-cosine glottal flow, open for 60% of each period, as
            // it radiates from the lips (its slope): one smooth sine cycle
            // per pulse, with a little breath while the folds are open.
            let openQuotient: Float = 0.6
            let opening = phase < openQuotient ? 2 * Float.pi * phase / openQuotient : 0
            let source = sin(opening) + random.nextBipolar() * (0.05 + 0.1 * (0.5 - 0.5 * cos(opening)))
            let voiced = resonators.0.process(source)
                + resonators.1.process(source) * 0.6
                + resonators.2.process(source) * 0.25
            output += voiced * level
        } else {
            // Keep the resonators ringing out quietly instead of freezing them.
            _ = resonators.0.process(0)
            _ = resonators.1.process(0)
            _ = resonators.2.process(0)
        }
        return muffle.process(output) * nearness
    }

    private mutating func startSyllable(_ random: inout NoiseRandom) {
        syllablePosition = 0
        guard syllablesLeft > 0 else {
            // A pause between phrases (listening, sipping), then a new
            // phrase of 4-14 syllables.
            syllableLength = Int(sampleRate * Double(0.4 + 2 * random.nextUnit()))
            syllableLevel = 0
            syllablesLeft = 4 + Int(random.nextUnit() * 11)
            phraseLength = syllablesLeft
            return
        }
        syllablesLeft -= 1
        syllableLength = Int(sampleRate * Double(0.13 + 0.15 * random.nextUnit()))
        let stressed = random.nextUnit() < 0.3
        syllableLevel = (stressed ? 0.85 : 0.45) + 0.15 * random.nextUnit()
        // Pitch falls gently across a phrase, and stressed syllables lift it.
        let progress = 1 - Float(syllablesLeft) / Float(max(phraseLength, 1))
        let declination: Float = 1.08 - 0.16 * progress
        pitchTarget = basePitch * declination * (stressed ? 1.12 : 0.97 + 0.06 * random.nextUnit())
        let vowel = cafeVowels[Int(random.nextUnit() * Float(cafeVowels.count)) % cafeVowels.count]
        formantTargets = (vowel.0 * formantScale, vowel.1 * formantScale, vowel.2 * formantScale)
        if random.nextUnit() < 0.7 {
            // A consonant: a breath of hiss (s, t, f, k) leading into the vowel.
            consonant.trigger(
                level: 0.1 + 0.15 * random.nextUnit(),
                decaySeconds: 0.015 + 0.035 * random.nextUnit(),
                frequency: 2_200 + 3_500 * random.nextUnit(),
                q: 1.2,
                sampleRate: sampleRate)
        }
    }
}

/// A short ring of crockery: a cup on a saucer or a spoon on a mug, from
/// three inharmonic sine partials whose ratios suit thick ceramic.
struct ClinkVoice: Sendable {
    private var phases: (Float, Float, Float) = (0, 0, 0)
    private var increments: (Float, Float, Float) = (0, 0, 0)
    private(set) var level: Float = 0
    private var decay: Float = 0

    var isActive: Bool { level > 1e-4 }

    mutating func trigger(frequency: Float, level: Float, decaySeconds: Float, sampleRate: Double) {
        let base = frequency / Float(sampleRate)
        increments = (base, base * 2.32, base * 4.25)
        phases = (0, 0, 0)
        self.level = level
        decay = Float(exp(-1 / (Double(decaySeconds) * sampleRate)))
    }

    mutating func next() -> Float {
        guard isActive else { return 0 }
        let y = sin(2 * Float.pi * phases.0)
            + 0.45 * sin(2 * Float.pi * phases.1)
            + 0.2 * sin(2 * Float.pi * phases.2)
        phases.0 = (phases.0 + increments.0).truncatingRemainder(dividingBy: 1)
        phases.1 = (phases.1 + increments.1).truncatingRemainder(dividingBy: 1)
        phases.2 = (phases.2 + increments.2).truncatingRemainder(dividingBy: 1)
        let out = y * level
        level *= decay
        return out
    }
}

/// A feedback comb filter with damping in its loop (one line of a
/// Schroeder reverb). Its buffer is allocated once, up front.
struct DampedComb: Sendable {
    private var buffer: [Float]
    private var index = 0
    private var stored: Float = 0
    private let feedback: Float
    private let damping: Float

    init(delay: Int, feedback: Float, damping: Float) {
        buffer = [Float](repeating: 0, count: max(delay, 1))
        self.feedback = feedback
        self.damping = damping
    }

    mutating func process(_ x: Float) -> Float {
        let y = buffer[index]
        stored = y * (1 - damping) + stored * damping
        buffer[index] = x + stored * feedback
        index += 1
        if index == buffer.count { index = 0 }
        return y
    }
}

/// A Schroeder all-pass, which smears echoes into a smooth tail.
struct AllPassDiffuser: Sendable {
    private var buffer: [Float]
    private var index = 0
    private let gain: Float = 0.5

    init(delay: Int) {
        buffer = [Float](repeating: 0, count: max(delay, 1))
    }

    mutating func process(_ x: Float) -> Float {
        let delayed = buffer[index]
        let y = delayed - gain * x
        buffer[index] = x + gain * delayed
        index += 1
        if index == buffer.count { index = 0 }
        return y
    }
}

/// A small, soft room (about 0.7 s of tail): what turns a few separate
/// voices into one cafe and blurs any syllable into murmur.
struct CafeRoom: Sendable {
    private var combs: [DampedComb]
    private var diffusers: [AllPassDiffuser]

    init(sampleRate: Double) {
        // Freeverb's mutually prime delays, scaled from 44.1 kHz.
        let scale = sampleRate / 44_100
        combs = [1_116, 1_277, 1_422, 1_557].map {
            DampedComb(delay: Int(Double($0) * scale), feedback: 0.74, damping: 0.4)
        }
        diffusers = [556, 225].map { AllPassDiffuser(delay: Int(Double($0) * scale)) }
    }

    mutating func process(_ x: Float) -> Float {
        var y: Float = 0
        for i in combs.indices { y += combs[i].process(x) }
        y *= 0.25
        for i in diffusers.indices { y = diffusers[i].process(y) }
        return y
    }
}

/// A busy cafe: sixteen people talking at nearby tables, the room they sit
/// in, a low hum of ventilation and fridges, and now and then a cup set on
/// a saucer or a spoon stirring a mug.
///
/// Everything is synthesized here, from no recordings, so the sound has no
/// licence other than the app's own (see docs/sounds.md).
struct CafeSynth: Sendable {
    private static let talkerCount = 16

    private let sampleRate: Double
    private var random: NoiseRandom
    private var talkers: [Talker]
    private var voiceHighPass: BiquadFilter
    private var distance: BiquadFilter
    private var crowd: Drift
    /// Running power of the voices, for leveling them (see `next`).
    private var voicePower: Float
    private let levelingAttack: Float
    private let levelingRelease: Float
    private var room: CafeRoom
    private var roomTone: NoiseGenerator
    private var roomLowPass: BiquadFilter
    private var clinks: [ClinkVoice]
    private let clinkChance: Float
    /// Remaining clinks of a spoon stirring, and samples until the next.
    private var stirsLeft = 0
    private var stirGap = 0

    /// Calibrated so the long-term RMS matches `NoiseGenerator.targetRMS`.
    private static let outputGain: Float = 1.62
    /// RMS the leveled crowd of voices is held at.
    private static let voiceLevel: Float = 0.12

    init(sampleRate: Double, seed: UInt64) {
        self.sampleRate = sampleRate
        var random = NoiseRandom(seed: seed ^ 0xCAFE)
        talkers = (0..<Self.talkerCount).map { _ in Talker(sampleRate: sampleRate, random: &random) }
        self.random = random
        // Distant voices carry little chest rumble, and none of the growl
        // that low pitches through a resonant filter would otherwise add.
        voiceHighPass = BiquadFilter(kind: .highPass, frequency: 160, sampleRate: sampleRate)
        distance = BiquadFilter(kind: .lowPass, frequency: 4_000, sampleRate: sampleRate)
        crowd = Drift(range: 0.92...1.06, seconds: 6, sampleRate: sampleRate)
        voicePower = Self.voiceLevel * Self.voiceLevel
        levelingAttack = Float(1 - exp(-1 / (0.3 * sampleRate)))
        levelingRelease = Float(1 - exp(-1 / (3 * sampleRate)))
        room = CafeRoom(sampleRate: sampleRate)
        roomTone = NoiseGenerator(color: .pink, sampleRate: sampleRate, seed: seed &+ 5)
        roomLowPass = BiquadFilter(kind: .lowPass, frequency: 250, sampleRate: sampleRate)
        clinks = Array(repeating: ClinkVoice(), count: 3)
        clinkChance = Float(0.25 / sampleRate)
    }

    mutating func next() -> Float {
        var voices: Float = 0
        for i in talkers.indices { voices += talkers[i].next(&random) }
        voices = distance.process(voiceHighPass.process(voices))
        // A leveler evens out a table that happens to sit close or a lull
        // when everyone pauses at once, so the cafe keeps one steady
        // loudness while each voice still comes and goes. It reacts fast
        // to a swell (0.3 s) and slowly to a lull (3 s), so it never pumps
        // a sudden loud voice up.
        let power = voices * voices
        voicePower += (power - voicePower) * (power > voicePower ? levelingAttack : levelingRelease)
        let leveling = min(max(Self.voiceLevel / (voicePower + 1e-9).squareRoot(), 0.5), 2)
        voices *= leveling * crowd.next(&random)

        if stirsLeft == 0, random.nextUnit() < clinkChance {
            if random.nextUnit() < 0.35 {
                // A spoon stirring: a few quick, quiet taps on one mug.
                stirsLeft = 3 + Int(random.nextUnit() * 4)
                stirGap = 0
            } else {
                clink(frequency: 2_000 + 1_800 * random.nextUnit(), level: 0.04 + 0.05 * random.nextUnit())
            }
        }
        if stirsLeft > 0 {
            stirGap -= 1
            if stirGap <= 0 {
                clink(frequency: 3_000 + 400 * random.nextUnit(), level: 0.012 + 0.012 * random.nextUnit())
                stirsLeft -= 1
                stirGap = Int(Float(sampleRate) * (0.14 + 0.08 * random.nextUnit()))
            }
        }
        var crockery: Float = 0
        for i in clinks.indices { crockery += clinks[i].next() }

        let dry = voices + crockery * 0.6
        var y = dry * 0.55 + room.process(dry) * 0.9
        y += roomLowPass.process(roomTone.next()) * 0.1
        return y * Self.outputGain
    }

    private mutating func clink(frequency: Float, level: Float) {
        var slot = 0
        for i in clinks.indices where clinks[i].level < clinks[slot].level { slot = i }
        clinks[slot].trigger(
            frequency: frequency,
            level: level,
            decaySeconds: 0.04 + 0.12 * random.nextUnit(),
            sampleRate: sampleRate)
    }
}
