import AVFoundation
import Foundation
import os

/// A focus sound recorded rather than synthesized: a seamless loop that
/// ships in TabbiKitCore's resource bundle (see docs/sounds.md for where
/// each one comes from and its license).
///
/// The loop is decoded once into memory as 16-bit mono, which halves the
/// footprint of floats (two minutes at 48 kHz is about 11 MB) and is still
/// far below the noise floor of any room recording. Decoding takes tens of
/// milliseconds, so it never happens on the audio thread: `FocusMixer`
/// loads a recording when a mix first asks for its sound, and
/// `FocusSoundEngine` does that before it takes the render lock.
public final class FocusRecording: Sendable {
    /// The recordings in the bundle, by the sound they play.
    public enum Name: String, CaseIterable, Sendable {
        case cafe

        var fileName: String { "\(rawValue).m4a" }
    }

    /// Bundle folder that holds the recordings (Package.swift copies it).
    static let folderName = "FocusRecordings"

    public let samples: [Int16]
    public let sampleRate: Double
    /// Multiplies the 16-bit samples (scaled to -1...1) up to
    /// `NoiseGenerator.targetRMS`, like every synthesized sound, so the
    /// file's own level never matters: `FocusSound.loudnessTrimDecibels`
    /// then sets its loudness.
    let gain: Float

    public var duration: Double { Double(samples.count) / sampleRate }

    init(samples: [Int16], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
        var power: Double = 0
        for sample in samples { power += Double(sample) * Double(sample) }
        let rms = samples.isEmpty ? 0 : (power / Double(samples.count)).squareRoot() / Double(Int16.max)
        gain = rms > 0 ? NoiseGenerator.targetRMS / Float(rms) : 0
    }

    private static let cache = OSAllocatedUnfairLock(initialState: [Name: FocusRecording]())

    /// The recording, decoded on first use and kept from then on. Nil when
    /// the file is missing or unreadable, in which case the sound is silent
    /// rather than crashing the app.
    public static func named(_ name: Name) -> FocusRecording? {
        if let cached = cache.withLock({ $0[name] }) { return cached }
        guard let url = url(of: name), let recording = decode(url) else { return nil }
        return cache.withLock { cache in
            // Another thread may have decoded it meanwhile; keep the first.
            if let existing = cache[name] { return existing }
            cache[name] = recording
            return recording
        }
    }

    /// The recording if it is already decoded, never decoding it. Safe to
    /// call while holding a lock the audio thread waits on.
    static func ifLoaded(_ name: Name) -> FocusRecording? {
        cache.withLock { $0[name] }
    }

    static func url(of name: Name) -> URL? {
        KitResources.bundle?.resourceURL?
            .appendingPathComponent(folderName)
            .appendingPathComponent(name.fileName)
    }

    /// Decodes any file AVFoundation reads into 16-bit mono, averaging the
    /// channels of a stereo file.
    static func decode(_ url: URL) -> FocusRecording? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              (try? file.read(into: buffer)) != nil,
              let channels = buffer.floatChannelData
        else { return nil }
        let count = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        let scale = Float(Int16.max) / Float(channelCount)
        let samples = [Int16](unsafeUninitializedCapacity: count) { output, initialized in
            for i in 0..<count {
                var sum: Float = 0
                for channel in 0..<channelCount { sum += channels[channel][i] }
                output[i] = Int16(max(min(sum * scale, Float(Int16.max)), -Float(Int16.max)))
            }
            initialized = count
        }
        return FocusRecording(samples: samples, sampleRate: format.sampleRate)
    }
}

/// Plays a `FocusRecording` round and round at any output rate.
///
/// The loops are edited so their end flows into their start, so wrapping
/// needs no crossfade here. A recording at another rate than the output is
/// resampled by linear interpolation, which is plenty for room ambience.
/// Each seed starts at a different point of the loop, so two mixers (or a
/// restart) don't always open on the same moment.
struct RecordingLoop: Sendable {
    let name: FocusRecording.Name
    private let outputRate: Double
    private let startFraction: Double
    /// The recording's samples (sharing its storage, never copied), held
    /// here rather than through the class so the render path does no
    /// reference counting.
    private var samples: [Int16] = []
    private var position: Double = 0
    private var step: Double = 1
    /// Takes a sample from 16 bits to `NoiseGenerator.targetRMS`.
    private var scale: Float = 0

    /// - Parameter loadsNow: decode the recording right away. The mixer
    ///   passes false and calls `prepare()` once a mix needs the sound.
    init(_ name: FocusRecording.Name, sampleRate: Double, seed: UInt64, loadsNow: Bool) {
        self.name = name
        outputRate = sampleRate
        var random = NoiseRandom(seed: seed ^ 0x100F)
        startFraction = Double(random.nextUnit())
        if loadsNow { attach(FocusRecording.named(name)) }
    }

    /// Takes the recording if it's decoded already; decodes it otherwise.
    mutating func prepare() {
        guard samples.isEmpty else { return }
        attach(FocusRecording.ifLoaded(name) ?? FocusRecording.named(name))
    }

    private mutating func attach(_ recording: FocusRecording?) {
        guard let recording, !recording.samples.isEmpty else { return }
        samples = recording.samples
        scale = recording.gain / Float(Int16.max)
        step = recording.sampleRate / outputRate
        position = (startFraction * Double(recording.samples.count)).rounded(.down)
    }

    mutating func next() -> Float {
        let count = samples.count
        guard count > 0 else { return 0 }
        let index = Int(position)
        let fraction = Float(position - Double(index))
        let a = Float(samples[index])
        let b = Float(samples[index + 1 == count ? 0 : index + 1])
        position += step
        if position >= Double(count) { position -= Double(count) }
        return (a + (b - a) * fraction) * scale
    }
}
