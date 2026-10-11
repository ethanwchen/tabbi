import XCTest
import TabbiKitCore

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

    // MARK: - Cafe (a recording)

    private func cafeRecording() throws -> FocusRecording {
        try XCTUnwrap(FocusRecording.named(.cafe), "cafe.m4a ships in the resource bundle and decodes")
    }

    func testCafeRecordingShipsAsAOneToThreeMinuteLoop() throws {
        let recording = try cafeRecording()
        XCTAssertEqual(recording.sampleRate, 48_000, "the mixer's rate, so it plays without resampling")
        XCTAssertGreaterThanOrEqual(recording.duration, 60)
        XCTAssertLessThanOrEqual(recording.duration, 180)
        XCTAssertEqual(FocusSound.cafe.recording, .cafe)
        XCTAssertNil(FocusSound.rain.recording)
    }

    /// The loop's end must flow into its start: the step across the seam is
    /// no bigger than the recording's ordinary sample-to-sample steps, and
    /// the room is just as loud on both sides of it.
    func testCafeLoopHasNoSeam() throws {
        let samples = try cafeRecording().samples.map { Float($0) / Float(Int16.max) }
        let steps = zip(samples.dropFirst(), samples).map { abs($0 - $1) }.sorted()
        let seamStep = abs(samples[0] - samples[samples.count - 1])
        XCTAssertLessThanOrEqual(seamStep, steps[steps.count * 999 / 1000], "no click at the loop point")
        let side = Int(Analysis.sampleRate * 2)
        let before = Analysis.rms(Array(samples.suffix(side)))
        let after = Analysis.rms(Array(samples.prefix(side)))
        XCTAssertEqual(Analysis.decibels(Double(after * after) / Double(before * before)), 0, accuracy: 3, "no jump in level")
    }

    /// The old synthesized cafe was a few robotic voices that dropped out
    /// into near silence (the room fell by 16 dB) and muffled everything
    /// above 1 kHz, which made it sound ghostly. The recording keeps a steady
    /// room and no clatter stands out of it.
    func testCafeIsASteadyRoomWithNoSuddenClatter() throws {
        let cafe = Array(try cafeRecording().samples.map { Float($0) / Float(Int16.max) })
        let second = Int(Analysis.sampleRate)
        let levels = stride(from: 0, to: cafe.count - second, by: second).map {
            20 * log10(Double(Analysis.rms(Array(cafe[$0 ..< $0 + second]))))
        }.sorted()
        let median = levels[levels.count / 2]
        XCTAssertLessThan(levels.last! - median, 6, "no second is much louder than the room")
        XCTAssertGreaterThan(levels.first! - median, -8, "the room never falls silent")
        // Voices, not a muffled rumble: the speech band carries real energy.
        let x = samples(.cafe, seconds: 30)
        XCTAssertLessThan(tilt(x, from: 500, to: 2000), 25)
    }

    func testCafeEveryStartAndRatePlaysAtTheSharedLevel() {
        for seed: UInt64 in [1, 7, 99] {
            XCTAssertEqual(Analysis.rms(samples(.cafe, seed: seed)), NoiseGenerator.targetRMS, accuracy: 0.03, "seed \(seed)")
        }
        // Another output rate resamples on the fly, at the same level.
        var generator = FocusSoundGenerator(sound: .cafe, sampleRate: 44_100, seed: 3)
        var buffer = [Float](repeating: 0, count: 44_100 * 10)
        generator.fill(&buffer)
        XCTAssertEqual(Analysis.rms(buffer), NoiseGenerator.targetRMS, accuracy: 0.03)
    }

    /// The mixer builds every generator up front but must not decode a
    /// recording nobody picked; it stays silent until prepared.
    func testARecordedSoundWaitsToBePrepared() {
        var generator = FocusSoundGenerator(sound: .cafe, sampleRate: 48_000, loadsRecording: false)
        XCTAssertEqual((0..<1_000).map { _ in generator.next() }.allSatisfy { $0 == 0 }, true)
        generator.prepareRecording()
        var buffer = [Float](repeating: 0, count: 48_000)
        generator.fill(&buffer)
        XCTAssertGreaterThan(Analysis.rms(buffer), 0.05)
    }
}
