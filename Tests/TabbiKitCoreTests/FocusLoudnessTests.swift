import XCTest
import TabbiKitCore

/// Equal RMS is not equal loudness, so these measure what the ear hears
/// (BS.1770 integrated loudness) through the mixer the app plays.
final class FocusLoudnessTests: XCTestCase {
    private typealias Analysis = FocusSignalAnalysis

    /// Volume 0.7 keeps every sound under the soft clip's knee, so the
    /// measurement is of the trims, not of clipping.
    private static let volume: Float = 0.7
    private static var volumeDecibels: Double { 20 * log10(Double(FocusMixer.amplitude(forVolume: volume))) }

    private func loudness(of mix: FocusMix, seed: UInt64 = 42, seconds: Double = 10) -> Double {
        var mixer = FocusMixer(sampleRate: Analysis.sampleRate, volume: Self.volume, seed: seed)
        mixer.setMix(mix)
        mixer.play()
        var fadeIn = [Float](repeating: 0, count: Int(Analysis.sampleRate * (FocusMixer.fadeSeconds + 0.5)))
        mixer.fill(&fadeIn)
        var buffer = [Float](repeating: 0, count: Int(Analysis.sampleRate * seconds))
        mixer.fill(&buffer)
        return Analysis.loudness(buffer) - Self.volumeDecibels
    }

    func testEverySoundPlaysAtTheSameLoudness() {
        let levels = FocusSound.allCases.map { ($0, loudness(of: .single($0))) }
        for (sound, level) in levels {
            XCTAssertEqual(level, Double(FocusSound.loudnessTarget), accuracy: 1, "\(sound) loudness")
        }
        let values = levels.map(\.1)
        XCTAssertLessThan(values.max()! - values.min()!, 1.5, "switching sounds never jumps in level")
    }

    func testWhiteNoiseNoLongerOutshoutsBrownNoise() {
        // Raw, white measured about 8 LU above brown at the same RMS.
        XCTAssertEqual(loudness(of: .single(.white)), loudness(of: .single(.brown)), accuracy: 1)
    }

    func testABlendPlaysAtAboutTheLoudnessOfOneSound() {
        let scene = FocusMix([.init(sound: .rain), .init(sound: .fireplace), .init(sound: .cafe)])
        XCTAssertEqual(loudness(of: scene), Double(FocusSound.loudnessTarget), accuracy: 1.5)
    }

    func testTrimsStayWithinAFewDecibels() {
        for sound in FocusSound.allCases {
            XCTAssertLessThanOrEqual(abs(sound.loudnessTrimDecibels), 7, "\(sound) needs little gain change")
            XCTAssertEqual(sound.loudnessGain, pow(10, sound.loudnessTrimDecibels / 20), accuracy: 1e-6)
        }
    }
}
