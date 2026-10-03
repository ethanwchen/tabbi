@preconcurrency import AVFoundation
import NotchKitCore
import os

/// Plays a `FocusMix` through AVAudioEngine, generated live by `FocusMixer`.
///
/// The engine only runs while sound is audible: `play()` starts it and the
/// mixer fades in; `stop()` fades out over 2 s and the engine shuts down once
/// the mixer reports exact silence, so an idle focus mode costs no CPU and
/// keeps no audio device awake. The mixer renders at a fixed 48 kHz mono and
/// AVAudioEngine converts to whatever the output device wants, so swapping
/// headphones mid-session never needs a new mixer.
@MainActor
public final class FocusSoundEngine {
    public static let sampleRate = 48_000.0

    /// The mixer lives in a heap box so the render callback can mutate it in
    /// place (no copy-on-write of its generator arrays on the audio thread).
    /// The lock is held only for tiny main-thread edits and one render slice.
    private final class MixerBox: @unchecked Sendable {
        var mixer: FocusMixer
        let lock = OSAllocatedUnfairLock()

        init(mixer: FocusMixer) { self.mixer = mixer }

        func withMixer<T>(_ body: (inout FocusMixer) -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body(&mixer)
        }
    }

    public let engine: AVAudioEngine
    private let box: MixerBox
    private let source: AVAudioSourceNode
    private var shutdownTask: Task<Void, Never>?
    private var configurationObserver: NSObjectProtocol?

    public private(set) var mix: FocusMix = .off
    public private(set) var volume: Float
    /// True between `play()` and `stop()`, i.e. while sound is (or is fading) in.
    public private(set) var isPlaying = false

    /// - Parameter engine: injectable so a harness can put it in manual
    ///   (offline) rendering mode before the first `play()`.
    public init(volume: Float = FocusSettings.default.volume, engine: AVAudioEngine = AVAudioEngine()) {
        self.engine = engine
        self.volume = volume
        let box = MixerBox(mixer: FocusMixer(sampleRate: Self.sampleRate, volume: volume, seed: UInt64.random(in: 1...UInt64.max)))
        self.box = box
        let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)!
        source = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let first = buffers.first, let data = first.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            let count = Int(frameCount)
            box.withMixer { $0.render(into: data, count: count) }
            // A mono format has one buffer, but copy defensively if not.
            for buffer in buffers.dropFirst() {
                buffer.mData?.copyMemory(from: data, byteCount: count * MemoryLayout<Float>.size)
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)

        // A device change (headphones unplugged, AirPods connected) stops
        // the engine; restart it so focus sound continues on the new output.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleConfigurationChange() }
        }
    }

    deinit {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        engine.stop()
    }

    /// Changes the sounds; crossfades over 2 s while playing. Switching to
    /// Off while playing fades out and shuts the engine down; picking a
    /// sound again fades back in.
    public func setMix(_ mix: FocusMix) {
        self.mix = mix
        box.withMixer { $0.setMix(mix) }
        if isPlaying { updateTransport() }
    }

    /// Sets the 0...1 master volume; glides over 50 ms so sliders never zip.
    public func setVolume(_ volume: Float) {
        self.volume = box.withMixer {
            $0.setVolume(volume)
            return $0.volume
        }
    }

    /// Fades in over 2 s (starting the engine) when the mix has any sound.
    public func play() {
        isPlaying = true
        updateTransport()
    }

    /// Fades out over 2 s, then stops the engine.
    public func stop() {
        guard isPlaying else { return }
        isPlaying = false
        updateTransport()
    }

    /// True when the mixer is producing exact silence (stopped and faded out).
    public var isSilent: Bool { box.withMixer { $0.isSilent } }

    /// The mixer plays only when we're playing *and* there's something to
    /// hear, so an Off mix lets the engine shut down mid-session.
    private func updateTransport() {
        if isPlaying && !mix.isOff {
            shutdownTask?.cancel()
            shutdownTask = nil
            box.withMixer { $0.play() }
            startEngineIfNeeded()
        } else {
            box.withMixer { $0.stop() }
            scheduleShutdownWhenSilent()
        }
    }

    private func startEngineIfNeeded() {
        guard !engine.isRunning else { return }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            // No output device or audio is unavailable; focus mode still
            // runs its playlist and Do Not Disturb parts without sound.
            Self.log.error("Focus sound engine failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Polls a few times a second until the fade-out lands, then stops the
    /// engine. Cancelled when playback resumes before then, and ends early
    /// if the engine stops by itself (for example on a device change).
    private func scheduleShutdownWhenSilent() {
        guard shutdownTask == nil, engine.isRunning else { return }
        shutdownTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.engine.isRunning {
                    self.shutdownTask = nil
                    return
                }
                if self.isSilent {
                    self.engine.stop()
                    self.shutdownTask = nil
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func handleConfigurationChange() {
        guard isPlaying, !mix.isOff else { return }
        startEngineIfNeeded()
    }

    private static let log = Logger(subsystem: "NotchDeck", category: "FocusSound")
}
