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
/// at, with its peaks kept under -1 dBFS.
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
        let weighted = kWeighted(samples, rate: rate)
        let size = Int(length * rate), step = Int(0.1 * rate)
        guard weighted.count >= size else {
            return weighted.isEmpty ? [] : [weighted.reduce(0) { $0 + $1 * $1 } / Double(weighted.count)]
        }
        var squares = [Double](repeating: 0, count: weighted.count + 1)
        for (index, value) in weighted.enumerated() { squares[index + 1] = squares[index] + value * value }
        return stride(from: 0, through: weighted.count - size, by: step).map {
            (squares[$0 + size] - squares[$0]) / Double(size)
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
        let shelf = (b: [(vh + vb * k / q + k * k) / a0, 2 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0],
                     a: [1, 2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0])
        // Stage two, a high pass at about 38 Hz.
        f0 = 38.13547087602444
        q = 0.5003270373238773
        k = tan(Double.pi * f0 / rate)
        let p0 = 1 + k / q + k * k
        let pass = (b: [1.0, -2.0, 1.0], a: [1, 2 * (k * k - 1) / p0, (1 - k / q + k * k) / p0])
        return filter(filter(samples.map(Double.init), shelf), pass)
    }

    private static func filter(_ x: [Double], _ c: (b: [Double], a: [Double])) -> [Double] {
        var y = [Double](repeating: 0, count: x.count)
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for index in x.indices {
            let out = c.b[0] * x[index] + c.b[1] * x1 + c.b[2] * x2 - c.a[1] * y1 - c.a[2] * y2
            x2 = x1; x1 = x[index]; y2 = y1; y1 = out
            y[index] = out
        }
        return y
    }

    /// `samples` brought to `target` LUFS with no sample over `ceiling`
    /// (a look-ahead limiter catches the strikes), a few passes so the
    /// limiting does not leave it short.
    static func master(_ samples: [Float], target: Double = -14, ceiling: Float = 0.8,
                       rate: Double = TapeSound.sampleRate) -> [Float] {
        var out = samples
        for _ in 0..<12 {
            let measured = integrated(out, rate: rate)
            guard measured > -69 else { return out }
            let gain = Float(pow(10, (target - measured) / 20))
            out = limited(out.map { $0 * gain }, ceiling: ceiling, rate: rate)
            if abs(integrated(out, rate: rate) - target) < 0.15 { break }
        }
        return out
    }

    private static func limited(_ samples: [Float], ceiling: Float, rate: Double) -> [Float] {
        let look = Int(0.005 * rate), release = Float(1 - exp(-1 / (0.08 * rate)))
        let needed = samples.map { min(1, ceiling / max(abs($0), 1e-9)) }
        // The lowest gain needed anywhere in the next few milliseconds, so
        // the gain is already down when a hit arrives, then a smooth release.
        var ahead = [Float](repeating: 1, count: samples.count)
        var window: [Int] = []
        for index in stride(from: samples.count - 1, through: 0, by: -1) {
            while let last = window.last, needed[last] >= needed[index] { window.removeLast() }
            window.append(index)
            while let first = window.first, first > index + look { window.removeFirst() }
            ahead[index] = needed[window[0]]
        }
        var gain: Float = 1
        return samples.indices.map { index in
            gain = ahead[index] < gain ? ahead[index] : gain + (ahead[index] - gain) * release
            return max(min(samples[index] * gain, ceiling), -ceiling)
        }
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
