import AVFoundation
import XCTest
import TabbiKitCore
@testable import TabbiKit

/// The cafe loop decodes off the main thread (about 45 ms, a visible hitch
/// when a session starts), and the sound starts once it is ready.
@MainActor
final class FocusSoundEngineDecodeTests: XCTestCase {
    func testPlayingTheCafeDecodesInTheBackgroundAndThenPlays() throws {
        FocusRecording.releaseDecoded()
        let (engine, buffer) = try offlineEngine()

        let started = Date()
        engine.setMix(.single(.cafe))
        engine.play()
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.03, "play() waited for the decode")
        XCTAssertTrue(engine.isDecoding, "the cafe decodes in the background")

        XCTAssertTrue(waitUntil(seconds: 10) { !engine.isDecoding }, "the decode never finished")
        XCTAssertTrue(engine.engine.isRunning, "playback starts once the cafe is decoded")
        // Past the 2 s fade in, the cafe is audible.
        for _ in 0..<3 { _ = try render(engine.engine, into: buffer) }
        XCTAssertGreaterThan(try render(engine.engine, into: buffer), 0.01)
        engine.stop()
    }

    func testCallsMadeWhileDecodingAreNotLost() throws {
        FocusRecording.releaseDecoded()
        let (engine, _) = try offlineEngine()
        engine.setMix(.single(.cafe))
        engine.play()
        XCTAssertTrue(engine.isDecoding)
        // Picked rain and stopped before the cafe was ready: rain, stopped.
        engine.setMix(.single(.rain))
        engine.stop()
        XCTAssertTrue(waitUntil(seconds: 10) { !engine.isDecoding })
        XCTAssertEqual(engine.mix, .single(.rain))
        XCTAssertFalse(engine.isPlaying)
    }

    func testAnAlreadyDecodedCafeStartsAtOnce() throws {
        _ = FocusMixer.preloadRecordings(for: .single(.cafe))
        let (engine, _) = try offlineEngine()
        engine.setMix(.single(.cafe))
        engine.play()
        XCTAssertFalse(engine.isDecoding)
        XCTAssertTrue(engine.engine.isRunning)
        engine.stop()
    }

    // MARK: Helpers

    /// One second per render, rendered offline with no audio device.
    private func offlineEngine() throws -> (FocusSoundEngine, AVAudioPCMBuffer) {
        let audio = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: FocusSoundEngine.sampleRate, channels: 1)!
        try audio.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 48_000)
        let engine = FocusSoundEngine(volume: 1, engine: audio)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.manualRenderingFormat, frameCapacity: 48_000))
        return (engine, buffer)
    }

    /// Renders one second and returns its RMS.
    private func render(_ engine: AVAudioEngine, into buffer: AVAudioPCMBuffer) throws -> Float {
        _ = try engine.renderOffline(48_000, to: buffer)
        let samples = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
        return (samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1))).squareRoot()
    }

    private func waitUntil(seconds: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        return condition()
    }
}
