import Accelerate
import AVFoundation
import Foundation
import TabbiKitCore

/// The tape's sound, synthesized so there is nothing to license and nothing
/// to download: a bed of tape hiss, a double beep when a camera picks up
/// motion, each object's own strike (a ceramic crash for the mug, a splash
/// for the bowl, a chomp, the fwip of tissues, digging and a thud, a vase
/// smashing), the same strike muffled when it happens off camera, and a
/// thud as the CAUGHT stamp lands. No music. The bracketed captions still
/// say every sound, so a muted tape loses nothing.
///
/// Every sound is mono 44.1 kHz floats from a fixed seed, so a tape sounds
/// the same each time and the export matches the player.
enum TapeSound {
    static let sampleRate = 44_100.0

    /// The samples of `cue`.
    static func samples(_ cue: PetCamTape.Cue) -> [Float] {
        switch cue {
        case .motion: beep()
        case .strike(let kind): strike(kind)
        case .offCamera(let kind): muffled(strike(kind))
        case .stamp: thud(amplitude: 0.75)
        }
    }

    /// `seconds` of tape hiss with a faint mains hum, quiet enough to sit
    /// under everything.
    static func hiss(seconds: Double) -> [Float] {
        var noise = PetCamRandom(seed: 0x4155, stream: "hiss")
        let count = Int(seconds * sampleRate)
        var out = [Float](repeating: 0, count: count)
        var low: Float = 0
        for index in 0..<count {
            let white = Float(noise.unit() * 2 - 1)
            low += 0.18 * (white - low)
            let hum = Float(sin(2 * .pi * 60 * Double(index) / sampleRate)) * 0.004
            out[index] = low * 0.006 + (white - low) * 0.0015 + hum * 0.15
        }
        return out
    }

    // MARK: Pieces

    private static func count(_ seconds: Double) -> Int { Int(seconds * sampleRate) }

    private static func tone(_ frequency: Double, seconds: Double, amplitude: Float, decay: Double? = nil,
                             attack: Double = 0.004) -> [Float] {
        (0..<count(seconds)).map { index in
            let t = Double(index) / sampleRate
            let rise = min(t / attack, 1)
            let fall = decay.map { exp(-t / $0) } ?? min((seconds - t) / 0.006, 1)
            return Float(sin(2 * .pi * frequency * t) * rise * fall) * amplitude
        }
    }

    /// Noise shaped by an envelope: `bright` keeps the hiss of it (0 is a
    /// dull thump, 1 a sharp burst).
    private static func burst(seconds: Double, amplitude: Float, decay: Double, bright: Float, seed: UInt64,
                              attack: Double = 0.002) -> [Float] {
        var noise = PetCamRandom(seed: seed, stream: "burst")
        var low: Float = 0
        return (0..<count(seconds)).map { index in
            let t = Double(index) / sampleRate
            let white = Float(noise.unit() * 2 - 1)
            low += 0.08 * (white - low)
            let shaped = low * (1 - bright) * 3 + (white - low) * bright
            return shaped * Float(min(t / attack, 1) * exp(-t / decay)) * amplitude
        }
    }

    /// `layer` mixed into `base` from `offset` seconds.
    private static func mix(_ base: [Float], _ layer: [Float], at offset: Double) -> [Float] {
        var out = base
        let start = count(offset)
        if out.count < start + layer.count { out += [Float](repeating: 0, count: start + layer.count - out.count) }
        for (index, value) in layer.enumerated() { out[start + index] += value }
        return out
    }

    private static func beep() -> [Float] {
        let one = tone(1_400, seconds: 0.07, amplitude: 0.16)
        return mix(one, one, at: 0.13)
    }

    private static func thud(amplitude: Float) -> [Float] {
        // A low hit that drops in pitch, with a click on top.
        var phase = 0.0
        let body: [Float] = (0..<count(0.32)).map { index in
            let t = Double(index) / sampleRate
            phase += 2 * .pi * (48 + 50 * exp(-t / 0.05)) / sampleRate
            return Float(sin(phase) * exp(-t / 0.09)) * amplitude
        }
        return mix(body, burst(seconds: 0.03, amplitude: amplitude * 0.5, decay: 0.008, bright: 0.6, seed: 9), at: 0)
    }

    private static func strike(_ kind: PetCamObjectKind) -> [Float] {
        switch kind {
        case .mug:
            // A ceramic crash: a burst and two ringing partials.
            let crash = burst(seconds: 0.45, amplitude: 0.5, decay: 0.09, bright: 0.85, seed: 1)
            let ring = mix(tone(2_150, seconds: 0.5, amplitude: 0.12, decay: 0.12),
                           tone(3_320, seconds: 0.4, amplitude: 0.08, decay: 0.08), at: 0)
            return mix(crash, ring, at: 0.005)
        case .vase:
            // A bigger smash, then shards settling.
            var out = burst(seconds: 0.5, amplitude: 0.55, decay: 0.12, bright: 0.9, seed: 2)
            for (offset, seed) in [(0.16, UInt64(21)), (0.27, 22), (0.36, 23)] {
                out = mix(out, burst(seconds: 0.08, amplitude: 0.22, decay: 0.02, bright: 1, seed: seed), at: offset)
            }
            return mix(out, tone(2_800, seconds: 0.35, amplitude: 0.07, decay: 0.07), at: 0.01)
        case .fishbowl:
            // A splash that swells, with a bloop.
            let splash = burst(seconds: 0.7, amplitude: 0.42, decay: 0.2, bright: 0.45, seed: 3, attack: 0.04)
            var phase = 0.0
            let bloop: [Float] = (0..<count(0.1)).map { index in
                let t = Double(index) / sampleRate
                phase += 2 * .pi * (300 + 6_000 * t) / sampleRate
                return Float(sin(phase) * exp(-t / 0.04)) * 0.2
            }
            return mix(splash, bloop, at: 0.02)
        case .donut:
            // Two chomps.
            let chomp = burst(seconds: 0.16, amplitude: 0.6, decay: 0.04, bright: 0.15, seed: 4)
            return mix(chomp, chomp, at: 0.24)
        case .tissues:
            // Fwip, fwip, fwip: rising bursts of bright noise.
            var out: [Float] = []
            for (step, seed) in [(0.0, UInt64(51)), (0.17, 52), (0.34, 53)] {
                out = mix(out, burst(seconds: 0.12, amplitude: 0.32, decay: 0.05, bright: 1, seed: seed, attack: 0.06),
                          at: step)
            }
            return out
        case .plant:
            // Dig, dig, then the pot goes over.
            var out = burst(seconds: 0.1, amplitude: 0.3, decay: 0.03, bright: 0.7, seed: 61)
            out = mix(out, burst(seconds: 0.1, amplitude: 0.3, decay: 0.03, bright: 0.7, seed: 62), at: 0.16)
            return mix(out, thud(amplitude: 0.55), at: 0.4)
        case .sock:
            // A soft rustle of cotton, then a muffled thump as it hits the floor.
            let rustle = burst(seconds: 0.35, amplitude: 0.28, decay: 0.12, bright: 0.35, seed: 71, attack: 0.05)
            return mix(rustle, thud(amplitude: 0.3), at: 0.3)
        case .keys:
            // Jingle jangle: bright metal ticks on a ring, then the drop.
            var out: [Float] = []
            for (step, frequency) in [(0.0, 4_200.0), (0.05, 5_100), (0.11, 3_700), (0.18, 4_800), (0.26, 4_400)] {
                out = mix(out, tone(frequency, seconds: 0.18, amplitude: 0.13, decay: 0.05), at: step)
            }
            out = mix(out, burst(seconds: 0.06, amplitude: 0.22, decay: 0.02, bright: 1, seed: 72), at: 0.32)
            return out
        case .yarn:
            // Thwap, thwap: two soft paw strikes on a ball.
            let thwap = burst(seconds: 0.09, amplitude: 0.45, decay: 0.025, bright: 0.25, seed: 73)
            return mix(thwap, thwap, at: 0.2)
        case .egg:
            // Splat: a wet low burst with the crack of the shell first.
            let crack = burst(seconds: 0.03, amplitude: 0.35, decay: 0.008, bright: 1, seed: 74)
            let splat = burst(seconds: 0.3, amplitude: 0.5, decay: 0.07, bright: 0.2, seed: 75, attack: 0.01)
            return mix(crack, splat, at: 0.02)
        case .banana:
            // Squish: a slow, dull, wet burst.
            return burst(seconds: 0.4, amplitude: 0.5, decay: 0.12, bright: 0.12, seed: 76, attack: 0.06)
        case .pencils:
            // Clatter: a run of wooden clicks across the floor.
            var out = thud(amplitude: 0.3)
            for (step, seed) in [(0.03, UInt64(81)), (0.09, 82), (0.13, 83), (0.2, 84), (0.24, 85), (0.33, 86)] {
                out = mix(out, burst(seconds: 0.03, amplitude: 0.3, decay: 0.008, bright: 0.85, seed: seed), at: step)
            }
            return out
        }
    }

    /// Heard through a wall: dull, at half the strike's peak.
    private static func muffled(_ samples: [Float]) -> [Float] {
        var low: Float = 0
        let dull = samples.map { value in
            low += 0.1 * (value - low)
            return low
        }
        let peak = dull.map(abs).max() ?? 0
        guard peak > 0 else { return dull }
        let gain = 0.5 * (samples.map(abs).max() ?? 0) / peak
        return dull.map { $0 * gain }
    }
}

/// Loudness as EBU R128 and ITU-R BS.1770 measure it, for one channel:
/// K-weighting (a high shelf and a high pass), 400 ms blocks every 100 ms,
/// an absolute gate at -70 LUFS and a relative gate 10 LU under the mean.
/// The share clip is mastered with it to -14 LUFS, the level the feeds play
/// at, with its true peak (the peak between the samples, read four times
/// oversampled as BS.1770 reads it) held at -3 dBTP, so the AAC encoder's
/// own overshoot still leaves the clip under -1 dBTP.
enum Loudness {
    /// Integrated loudness of `samples` in LUFS (-70 for silence).
    static func integrated(_ samples: [Float], rate: Double = TapeSound.sampleRate) -> Double {
        let blocks = blockPowers(samples, rate: rate, length: 0.4)
        let loud = blocks.filter { level($0) > -70 }
        guard !loud.isEmpty else { return -70 }
        let relative = level(loud.reduce(0, +) / Double(loud.count)) - 10
        let gated = loud.filter { level($0) > relative }
        guard !gated.isEmpty else { return -70 }
        return level(gated.reduce(0, +) / Double(gated.count))
    }

    /// The loudest 400 ms (momentary loudness) of `samples`, in LUFS.
    static func maximumMomentary(_ samples: [Float], rate: Double = TapeSound.sampleRate) -> Double {
        blockPowers(samples, rate: rate, length: 0.4).map(level).max() ?? -70
    }

    private static func level(_ power: Double) -> Double { -0.691 + 10 * log10(max(power, 1e-12)) }

    /// Mean square of the K-weighted signal in each `length` block, every
    /// 100 ms.
    private static func blockPowers(_ samples: [Float], rate: Double, length: Double) -> [Double] {
        let squares = vDSP.square(kWeighted(samples, rate: rate))
        let size = Int(length * rate), step = Int(0.1 * rate)
        guard squares.count >= size else {
            return squares.isEmpty ? [] : [vDSP.sum(squares) / Double(squares.count)]
        }
        return stride(from: 0, through: squares.count - size, by: step).map {
            vDSP.sum(squares[$0..<($0 + size)]) / Double(size)
        }
    }

    /// The K-weighting filters at `rate`, derived the way libebur128 (and
    /// so ffmpeg's ebur128) derives them for any sample rate.
    private static func kWeighted(_ samples: [Float], rate: Double) -> [Double] {
        // Stage one, a high shelf of about +4 dB from 1.7 kHz.
        var f0 = 1681.974450955533, q = 0.7071752369554196
        var k = tan(Double.pi * f0 / rate)
        let vh = pow(10, 3.999843853973347 / 20), vb = pow(vh, 0.4996667741545416)
        let a0 = 1 + k / q + k * k
        let shelf = [(vh + vb * k / q + k * k) / a0, 2 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0,
                     2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0]
        // Stage two, a high pass at about 38 Hz.
        f0 = 38.13547087602444
        q = 0.5003270373238773
        k = tan(Double.pi * f0 / rate)
        let p0 = 1 + k / q + k * k
        let pass = [1, -2, 1, 2 * (k * k - 1) / p0, (1 - k / q + k * k) / p0]
        // Each section is b0, b1, b2, a1, a2 (a0 is 1).
        guard var filters = vDSP.Biquad(coefficients: shelf + pass, channelCount: 1, sectionCount: 2,
                                        ofType: Double.self) else { return samples.map(Double.init) }
        return filters.apply(input: vDSP.floatToDouble(samples))
    }

    /// `samples` brought to `target` LUFS with a true peak at or under
    /// `ceiling`: a gain, a soft saturation that rounds the strikes' peaks
    /// toward the ceiling (the quiet hiss passes through untouched), then a
    /// look-ahead limiter on the true peak, repeated until the loudness
    /// settles. Saturating rather than only limiting is what lets short,
    /// spiky hits reach the level without lifting the hiss with them; the
    /// limiter reads the peaks between the samples, which a crash's
    /// saturated noise throws several dB over its samples.
    static func master(_ samples: [Float], target: Double = -14, ceiling: Float = 0.708,
                       rate: Double = TapeSound.sampleRate) -> [Float] {
        func rendered(_ decibels: Double) -> [Float] {
            let drive = Float(pow(10, decibels / 20)) / ceiling
            let saturated = vDSP.multiply(ceiling, vForce.tanh(vDSP.multiply(drive, samples)))
            return limited(saturated, ceiling: ceiling, rate: rate)
        }
        // Loudness only rises with the gain, so a secant search on the gain
        // in dB settles in a few rounds.
        var gain = 0.0
        var out = rendered(gain)
        var error = integrated(out, rate: rate) - target
        guard error + target > -69 else { return out }
        var step = -error
        for _ in 0..<12 where abs(error) >= 0.05 {
            let before = (gain: gain, error: error)
            gain += step
            out = rendered(gain)
            error = integrated(out, rate: rate) - target
            let slope = (error - before.error) / (gain - before.gain)
            step = max(-24, min(24, slope > 0.05 ? -error / slope : -error))
        }
        return out
    }

    /// The true peak of `samples` in dBTP.
    static func truePeak(_ samples: [Float]) -> Double {
        samples.isEmpty ? -.infinity : 20 * log10(Double(max(vDSP.maximum(peaks(samples)), 1e-9)))
    }

    /// Each sample's true peak: the larger of the sample and the three
    /// points between it and the next, interpolated four times oversampled
    /// with a 16 tap windowed sinc.
    static func peaks(_ samples: [Float]) -> [Float] {
        let reach = 8
        var padded = [Float](repeating: 0, count: reach - 1)
        padded += samples
        padded += [Float](repeating: 0, count: reach)
        var envelope = vDSP.absolute(samples)
        var between = [Float](repeating: 0, count: samples.count)
        for phase in 1..<4 {
            let taps = interpolator(phase: phase, reach: reach)
            padded.withUnsafeBufferPointer { signal in
                taps.withUnsafeBufferPointer { filter in
                    between.withUnsafeMutableBufferPointer { result in
                        vDSP_conv(signal.baseAddress!, 1, filter.baseAddress!, 1, result.baseAddress!, 1,
                                  vDSP_Length(samples.count), vDSP_Length(taps.count))
                    }
                }
            }
            envelope = vDSP.maximum(envelope, vDSP.absolute(between))
        }
        return envelope
    }

    /// The taps that read the point `phase` quarters of a sample after
    /// each sample, from the `reach` samples on either side, normalized to
    /// unit gain.
    private static func interpolator(phase: Int, reach: Int) -> [Float] {
        let offset = Double(phase) / 4
        let taps = (0..<(2 * reach)).map { position -> Double in
            let t = Double(position - reach + 1) - offset
            let sinc = t == 0 ? 1 : sin(Double.pi * t) / (Double.pi * t)
            let window = 0.5 + 0.5 * cos(Double.pi * t / Double(reach))
            return sinc * window
        }
        let sum = taps.reduce(0, +)
        return taps.map { Float($0 / sum) }
    }

    private static func limited(_ samples: [Float], ceiling: Float, rate: Double) -> [Float] {
        let look = Int(0.005 * rate), release = Float(1 - exp(-1 / (0.08 * rate)))
        let floor = vDSP.clip(peaks(samples), to: 1e-9...Float.greatestFiniteMagnitude)
        let needed = vDSP.clip(vDSP.divide(ceiling, floor), to: 0...1)
        // The lowest gain needed anywhere in the next few milliseconds, so
        // the gain is already down when a hit arrives, then a smooth release.
        var ahead = [Float](repeating: 1, count: samples.count)
        // A queue of rising minima, its front at `head`.
        var window: [Int] = []
        var head = 0
        window.reserveCapacity(samples.count)
        for index in stride(from: samples.count - 1, through: 0, by: -1) {
            while window.count > head, needed[window[window.count - 1]] >= needed[index] { window.removeLast() }
            window.append(index)
            while window[head] > index + look { head += 1 }
            ahead[index] = needed[window[head]]
        }
        var gain: Float = 1
        let gains = ahead.map { needed in
            gain = needed < gain ? needed : gain + (needed - gain) * release
            return gain
        }
        return vDSP.clip(vDSP.multiply(samples, gains), to: -ceiling...ceiling)
    }
}

/// Plays a tape's sounds in the app. The audio session is ambient, so the
/// Ring/Silent switch silences it and it never stops someone's music.
@MainActor
final class TapeAudio {
    static let shared = TapeAudio()

    private let engine = AVAudioEngine()
    private let bed = AVAudioPlayerNode()
    private let cues = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: TapeSound.sampleRate, channels: 1)
    private var buffers: [PetCamTape.Cue: AVAudioPCMBuffer] = [:]
    private var running = false

    private init() {
        engine.attach(bed)
        engine.attach(cues)
        if let format {
            engine.connect(bed, to: engine.mainMixerNode, format: format)
            engine.connect(cues, to: engine.mainMixerNode, format: format)
        }
    }

    /// Starts the hiss under a tape that is about to play.
    func start() {
        guard !running, let hiss = buffer(TapeSound.hiss(seconds: 2)) else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
        } catch {
            return
        }
        running = true
        bed.scheduleBuffer(hiss, at: nil, options: .loops)
        bed.play()
        cues.play()
    }

    func play(_ cue: PetCamTape.Cue) {
        guard running else { return }
        if buffers[cue] == nil { buffers[cue] = buffer(TapeSound.samples(cue)) }
        guard let sound = buffers[cue] else { return }
        cues.scheduleBuffer(sound, at: nil, options: .interrupts)
    }

    func stop() {
        guard running else { return }
        running = false
        bed.stop()
        cues.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func buffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let format, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }
}
