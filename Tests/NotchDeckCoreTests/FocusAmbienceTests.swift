import XCTest
import NotchDeckCore

final class FocusAmbienceTests: XCTestCase {
    private typealias Analysis = FocusSignalAnalysis

    private func samples(_ sound: FocusSound, seconds: Double = 10, seed: UInt64 = 42) -> [Float] {
        var generator = FocusSoundGenerator(sound: sound, sampleRate: Analysis.sampleRate, seed: seed)
        var buffer = [Float](repeating: 0, count: Int(Analysis.sampleRate * seconds))
        generator.fill(&buffer)
        // Skip the first half second so filter start-up doesn't skew results.
        return Array(buffer.dropFirst(Int(Analysis.sampleRate / 2)))
    }

    private func highPassed(_ x: [Float], above frequency: Double) -> [Float] {
        var filter = BiquadFilter(kind: .highPass, frequency: frequency, sampleRate: Analysis.sampleRate)
        return x.map { filter.process($0) }
    }

    /// dB of power at `low` over power at `high`.
    private func tilt(_ x: [Float], from low: Double, to high: Double) -> Double {
        Analysis.decibels(Analysis.power(of: x, near: low) / Analysis.power(of: x, near: high))
    }

    // MARK: - Every sound

    func testEverySoundPlaysAtTheSharedLevelWithoutDCOrSpikes() {
        for sound in FocusSound.allCases {
            let x = samples(sound)
            XCTAssertEqual(Analysis.rms(x), NoiseGenerator.targetRMS, accuracy: 0.03, "\(sound) level")
            XCTAssertEqual(Analysis.mean(x), 0, accuracy: 0.01, "\(sound) DC offset")
            // Transients may poke past 1; the mixer soft-clips. Nothing wild, though.
            XCTAssertLessThan(Analysis.peak(x), 1.6, "\(sound) peak")
        }
    }

    func testEverySoundIsDeterministicPerSeed() {
        for sound in FocusSound.allCases {
            var a = FocusSoundGenerator(sound: sound, sampleRate: Analysis.sampleRate, seed: 9)
            var b = FocusSoundGenerator(sound: sound, sampleRate: Analysis.sampleRate, seed: 9)
            var c = FocusSoundGenerator(sound: sound, sampleRate: Analysis.sampleRate, seed: 10)
            // Long enough for the cafe's talkers to start speaking.
            let first = (0..<96_000).map { _ in a.next() }
            XCTAssertEqual(first, (0..<96_000).map { _ in b.next() }, "\(sound)")
            XCTAssertNotEqual(first, (0..<96_000).map { _ in c.next() }, "\(sound)")
        }
    }

    func testSoundsHaveDistinctNamesAndSymbols() {
        let sounds = FocusSound.allCases
        XCTAssertEqual(Set(sounds.map(\.displayName)).count, sounds.count)
        XCTAssertEqual(Set(sounds.map(\.symbolName)).count, sounds.count)
        XCTAssertEqual(FocusSoundGenerator(sound: .rain, sampleRate: 48_000).sound, .rain)
    }

    // MARK: - Character of each ambience

    func testRainIsABrightHissWithDistinctDrops() {
        let rain = samples(.rain)
        let brown = samples(.brown)
        // Rain keeps far more top end than brown noise...
        XCTAssertGreaterThan(tilt(brown, from: 500, to: 4000) - tilt(rain, from: 500, to: 4000), 10)
        // ...and nearby drops stand out above the hiss as sharp ticks,
        // which steady pink noise never does.
        let rainSpikiness = Analysis.kurtosis(highPassed(rain, above: 2000))
        let pinkSpikiness = Analysis.kurtosis(highPassed(samples(.pink), above: 2000))
        XCTAssertGreaterThan(rainSpikiness, pinkSpikiness + 0.6)
    }

    func testFireplaceIsALowRumbleWithCrackles() {
        let fire = samples(.fireplace)
        XCTAssertGreaterThan(tilt(fire, from: 100, to: 1000), 20, "rumble dominates")
        // Crackles: the top end is near-silent between sharp bursts.
        XCTAssertGreaterThan(Analysis.kurtosis(highPassed(fire, above: 2000)), 20)
        // The roar breathes rather than holding a constant level.
        XCTAssertGreaterThan(
            Analysis.levelVariation(fire, windowSeconds: 1),
            3 * Analysis.levelVariation(samples(.pink), windowSeconds: 1))
    }

    func testCafeMurmurSitsInTheVoiceBandAndEbbs() {
        let cafe = samples(.cafe)
        // Distant voices: energy around vowel formants, little above them.
        XCTAssertGreaterThan(tilt(cafe, from: 500, to: 4000), 20)
        // Talkers start and stop, so the level ebbs and flows.
        XCTAssertGreaterThan(
            Analysis.levelVariation(cafe, windowSeconds: 1),
            3 * Analysis.levelVariation(samples(.pink), windowSeconds: 1))
    }
}
