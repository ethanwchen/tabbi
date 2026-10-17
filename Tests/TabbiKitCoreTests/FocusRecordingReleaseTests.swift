import XCTest
@testable import TabbiKitCore

/// A stopped focus sound holds no decoded audio: the cafe loop is 11 MB,
/// which used to stay in memory for the rest of the day after one session.
final class FocusRecordingReleaseTests: XCTestCase {
    private static let sampleRate = 48_000.0

    func testReleasedRecordingIsDecodedAgainTheSame() throws {
        let first = try XCTUnwrap(FocusRecording.named(.cafe))
        FocusRecording.releaseDecoded()
        XCTAssertNil(FocusRecording.ifLoaded(.cafe))
        let second = try XCTUnwrap(FocusRecording.named(.cafe))
        XCTAssertFalse(first === second, "a released recording is decoded afresh")
        XCTAssertEqual(first.samples, second.samples)
        XCTAssertEqual(first.sampleRate, second.sampleRate)
    }

    func testMixerLetsGoOfTheCafeAndPlaysItAgainWhenPrepared() {
        var mixer = FocusMixer(sampleRate: Self.sampleRate, volume: 1, seed: 7)
        mixer.setMix(.single(.cafe))
        mixer.play()
        XCTAssertGreaterThan(rms(&mixer, seconds: 3), 0.01, "the cafe plays")

        mixer.stop()
        _ = rms(&mixer, seconds: FocusMixer.fadeSeconds + 0.1)
        XCTAssertTrue(mixer.isSilent)
        mixer.releaseRecordings()
        FocusRecording.releaseDecoded()

        // Without its recording the cafe is silent; prepared again, it plays.
        mixer.play()
        XCTAssertEqual(rms(&mixer, seconds: 3), 0)
        mixer.stop()
        _ = rms(&mixer, seconds: FocusMixer.fadeSeconds + 0.1)
        mixer.prepareRecordings()
        mixer.play()
        XCTAssertGreaterThan(rms(&mixer, seconds: 3), 0.01, "the cafe plays again after prepareRecordings")
    }

    /// RMS of the last second of `seconds` rendered, past the fade in.
    private func rms(_ mixer: inout FocusMixer, seconds: Double) -> Float {
        var buffer = [Float](repeating: 0, count: Int(Self.sampleRate * seconds))
        mixer.fill(&buffer)
        let tail = buffer.suffix(Int(Self.sampleRate))
        return (tail.reduce(0) { $0 + $1 * $1 } / Float(tail.count)).squareRoot()
    }
}
