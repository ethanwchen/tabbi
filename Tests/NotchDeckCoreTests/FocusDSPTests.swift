import XCTest
import NotchDeckCore

final class FocusDSPTests: XCTestCase {
    private let sampleRate = 48_000.0

    // MARK: - Helpers

    private func samples(_ color: NoiseColor, seconds: Double = 4) -> [Float] {
        var generator = NoiseGenerator(color: color, sampleRate: sampleRate, seed: 42)
        var buffer = [Float](repeating: 0, count: Int(sampleRate * seconds))
        generator.fill(&buffer)
        // Skip the first half second so filter start-up doesn't skew results.
        return Array(buffer.dropFirst(Int(sampleRate / 2)))
    }

    private func rms(_ x: [Float]) -> Float { FocusSignalAnalysis.rms(x) }

    private func power(of x: [Float], near frequency: Double) -> Double {
        FocusSignalAnalysis.power(of: x, near: frequency)
    }

    private func decibels(_ ratio: Double) -> Double { FocusSignalAnalysis.decibels(ratio) }

    // MARK: - Noise spectra

    func testWhiteNoiseIsFlat() {
        let x = samples(.white)
        let drop = decibels(power(of: x, near: 250) / power(of: x, near: 4000))
        XCTAssertEqual(drop, 0, accuracy: 1)
    }

    func testPinkNoiseFallsThreeDecibelsPerOctave() {
        let x = samples(.pink)
        // 250 Hz -> 4 kHz is four octaves: 12 dB.
        let drop = decibels(power(of: x, near: 250) / power(of: x, near: 4000))
        XCTAssertEqual(drop, 12, accuracy: 1.5)
    }

    func testBrownNoiseFallsSixDecibelsPerOctave() {
        let x = samples(.brown)
        // 250 Hz -> 2 kHz is three octaves: 18 dB.
        let drop = decibels(power(of: x, near: 250) / power(of: x, near: 2000))
        XCTAssertEqual(drop, 18, accuracy: 1.5)
    }

    func testEveryColorPlaysAtTheSameLevelWithoutDCOrClipping() {
        for color in NoiseColor.allCases {
            let x = samples(color)
            XCTAssertEqual(rms(x), NoiseGenerator.targetRMS, accuracy: 0.015, "\(color) level")
            let mean = x.reduce(0, +) / Float(x.count)
            XCTAssertEqual(mean, 0, accuracy: 0.02, "\(color) DC offset")
            XCTAssertLessThan(x.map(abs).max() ?? 0, 1, "\(color) peak")
        }
    }

    func testSameSeedRepeatsAndDifferentSeedsDiffer() {
        var a = NoiseGenerator(color: .pink, sampleRate: sampleRate, seed: 7)
        var b = NoiseGenerator(color: .pink, sampleRate: sampleRate, seed: 7)
        var c = NoiseGenerator(color: .pink, sampleRate: sampleRate, seed: 8)
        let first = (0..<64).map { _ in a.next() }
        XCTAssertEqual(first, (0..<64).map { _ in b.next() })
        XCTAssertNotEqual(first, (0..<64).map { _ in c.next() })
    }

    func testRandomStaysInRangeEvenWithZeroSeed() {
        var random = NoiseRandom(seed: 0)
        var seen = Set<Float>()
        for _ in 0..<10_000 {
            let unit = random.nextUnit()
            XCTAssertTrue((0..<1).contains(unit))
            seen.insert(unit)
        }
        XCTAssertGreaterThan(seen.count, 9_900)
    }

    // MARK: - Filters

    /// Steady-state amplitude gain for a sine, from RMS so sparse sampling
    /// of high frequencies doesn't miss the peaks.
    private func sineGain(_ filter: inout BiquadFilter, frequency: Double) -> Float {
        var settled: [Float] = []
        for i in 0..<Int(sampleRate / 2) {
            let y = filter.process(Float(sin(2 * Double.pi * frequency * Double(i) / sampleRate)))
            if i >= Int(sampleRate / 4) { settled.append(y) }
        }
        return rms(settled) * Float(2).squareRoot()
    }

    func testBiquadLowPassPassesLowsAndCutsHighs() {
        var low = BiquadFilter(kind: .lowPass, frequency: 1000, sampleRate: sampleRate)
        XCTAssertEqual(sineGain(&low, frequency: 100), 1, accuracy: 0.02)
        var high = BiquadFilter(kind: .lowPass, frequency: 1000, sampleRate: sampleRate)
        // Two octaves above cutoff on a 12 dB/octave slope: about -24 dB.
        XCTAssertLessThan(sineGain(&high, frequency: 4000), 0.08)
        var corner = BiquadFilter(kind: .lowPass, frequency: 1000, sampleRate: sampleRate)
        XCTAssertEqual(sineGain(&corner, frequency: 1000), 0.707, accuracy: 0.02)
    }

    func testBiquadHighPassAndBandPass() {
        var high = BiquadFilter(kind: .highPass, frequency: 1000, sampleRate: sampleRate)
        XCTAssertLessThan(sineGain(&high, frequency: 250), 0.08)
        var pass = BiquadFilter(kind: .highPass, frequency: 1000, sampleRate: sampleRate)
        XCTAssertEqual(sineGain(&pass, frequency: 8000), 1, accuracy: 0.02)
        var band = BiquadFilter(kind: .bandPass, frequency: 1000, q: 2, sampleRate: sampleRate)
        XCTAssertEqual(sineGain(&band, frequency: 1000), 1, accuracy: 0.02)
        var off = BiquadFilter(kind: .bandPass, frequency: 1000, q: 2, sampleRate: sampleRate)
        XCTAssertLessThan(sineGain(&off, frequency: 8000), 0.1)
    }

    func testOnePoleSplitsSignalIntoComplementaryBands() {
        var low = OnePoleFilter(kind: .lowPass, cutoff: 500, sampleRate: sampleRate)
        var high = OnePoleFilter(kind: .highPass, cutoff: 500, sampleRate: sampleRate)
        var random = NoiseRandom(seed: 3)
        for _ in 0..<1000 {
            let x = random.nextBipolar()
            XCTAssertEqual(low.process(x) + high.process(x), x, accuracy: 1e-5)
        }
        var dc = OnePoleFilter(kind: .highPass, cutoff: 20, sampleRate: sampleRate)
        var y: Float = 1
        for _ in 0..<Int(sampleRate) { y = dc.process(1) }
        XCTAssertEqual(y, 0, accuracy: 1e-3)
    }

    // MARK: - Gain ramp

    func testRampGlidesSmoothlyAndLandsExactly() {
        var ramp = GainRamp(value: 0)
        let length = Int(sampleRate * 2)
        ramp.ramp(to: 1, samples: length)
        var previous: Float = 0
        var largestStep: Float = 0
        for _ in 0..<length {
            let value = ramp.next()
            XCTAssertGreaterThanOrEqual(value, previous)
            largestStep = max(largestStep, value - previous)
            previous = value
        }
        XCTAssertEqual(previous, 1)
        XCTAssertFalse(ramp.isRamping)
        // A linear 2 s fade steps 1/96000 per sample; the S-curve peaks at π/2 of that.
        XCTAssertLessThan(largestStep, 1.6 / Float(length))
        XCTAssertEqual(ramp.next(), 1)
    }

    func testRampStartsAndEndsWithoutACorner() {
        var ramp = GainRamp(value: 1)
        ramp.ramp(to: 0, samples: 1000)
        let firstStep = 1 - ramp.next()
        XCTAssertLessThan(firstStep, 1e-4)
        for _ in 0..<998 { _ = ramp.next() }
        let beforeLast = ramp.value
        XCTAssertLessThan(beforeLast - ramp.next(), 1e-4)
        XCTAssertEqual(ramp.value, 0)
    }

    func testRetargetingMidRampContinuesFromCurrentValue() {
        var ramp = GainRamp(value: 0)
        ramp.ramp(to: 1, samples: 100)
        for _ in 0..<50 { _ = ramp.next() }
        let midway = ramp.value
        XCTAssertEqual(midway, 0.5, accuracy: 0.01)
        ramp.ramp(to: 0, samples: 100)
        XCTAssertEqual(ramp.next(), midway, accuracy: 0.001)
        ramp.ramp(to: 0.3, samples: 0)
        XCTAssertEqual(ramp.value, 0.3)
        XCTAssertFalse(ramp.isRamping)
    }

    func testSoftClipIsTransparentWhenQuietAndBoundedWhenLoud() {
        XCTAssertEqual(focusSoftClip(0.1), 0.1, accuracy: 0.001)
        XCTAssertLessThan(focusSoftClip(5), 1)
        XCTAssertGreaterThan(focusSoftClip(-5), -1)
    }
}
