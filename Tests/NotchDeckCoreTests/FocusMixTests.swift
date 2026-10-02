import XCTest
import NotchDeckCore

final class FocusMixTests: XCTestCase {
    private typealias Analysis = FocusSignalAnalysis
    private let rate = Analysis.sampleRate

    private func render(_ mixer: inout FocusMixer, seconds: Double) -> [Float] {
        var buffer = [Float](repeating: 0, count: Int(rate * seconds))
        mixer.fill(&buffer)
        return buffer
    }

    private func playingMixer(_ mix: FocusMix, volume: Float = 1) -> FocusMixer {
        var mixer = FocusMixer(sampleRate: rate, volume: volume)
        mixer.setMix(mix)
        mixer.play()
        return mixer
    }

    /// Largest sample-to-sample jump; a click shows up as a spike here.
    private func maxStep(_ x: [Float]) -> Float {
        zip(x, x.dropFirst()).map { abs($1 - $0) }.max() ?? 0
    }

    // MARK: - Mix model

    func testMixKeepsAtMostThreeUniqueLayersWithClampedLevels() {
        let mix = FocusMix([
            .init(sound: .rain, level: 1.5),
            .init(sound: .rain, level: 0.2),
            .init(sound: .fireplace, level: -1),
            .init(sound: .cafe, level: .nan),
            .init(sound: .brown),
        ])
        XCTAssertEqual(mix.layers.map(\.sound), [.rain, .fireplace, .cafe])
        XCTAssertEqual(mix.layers.map(\.level), [1, 0, 1])
        XCTAssertFalse(mix.canAddLayer)
    }

    func testTogglingAddsAndRemovesButRefusesAFourthLayer() {
        var mix = FocusMix.off
        XCTAssertTrue(mix.isOff)
        XCTAssertEqual(mix.summary, "Off")
        XCTAssertTrue(mix.toggle(.rain))
        XCTAssertTrue(mix.toggle(.fireplace))
        XCTAssertTrue(mix.toggle(.cafe))
        XCTAssertFalse(mix.toggle(.pink))
        XCTAssertFalse(mix.contains(.pink))
        XCTAssertEqual(mix.summary, "Rain + Fireplace + Cafe murmur")
        XCTAssertTrue(mix.toggle(.fireplace))
        XCTAssertEqual(mix.layers.map(\.sound), [.rain, .cafe])
    }

    func testSetLevelOnlyAffectsSoundsInTheMix() {
        var mix = FocusMix.single(.rain)
        mix.setLevel(0.4, for: .rain)
        mix.setLevel(0.9, for: .cafe)
        XCTAssertEqual(mix.level(of: .rain), 0.4)
        XCTAssertNil(mix.level(of: .cafe))
        mix.setLevel(3, for: .rain)
        XCTAssertEqual(mix.level(of: .rain), 1)
    }

    func testGainsKeepABlendAsLoudAsOneFullLayer() throws {
        XCTAssertEqual(FocusMix.single(.rain).gains, [.rain: 1])
        let quiet = FocusMix([.init(sound: .rain, level: 0.3), .init(sound: .cafe, level: 0.4)])
        XCTAssertEqual(quiet.gains[.rain], 0.3, "under one full layer, levels are left alone")
        let full = FocusMix([.init(sound: .rain), .init(sound: .fireplace)])
        let gains = try XCTUnwrap(full.gains[.rain])
        XCTAssertEqual(gains, 1 / Float(2).squareRoot(), accuracy: 1e-6)
        let power = full.gains.values.reduce(0) { $0 + $1 * $1 }
        XCTAssertEqual(power, 1, accuracy: 1e-5)
    }

    func testMixRoundTripsThroughJSONAndSanitizesHandEditedInput() throws {
        let mix = FocusMix([.init(sound: .rain, level: 0.7), .init(sound: .fireplace, level: 0.5)])
        let data = try JSONEncoder().encode(mix)
        XCTAssertEqual(try JSONDecoder().decode(FocusMix.self, from: data), mix)

        let edited = Data(#"{"layers":[{"sound":"cafe","level":4},{"sound":"cafe","level":0.1}]}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(FocusMix.self, from: edited), .single(.cafe))
        XCTAssertEqual(try JSONDecoder().decode(FocusMix.self, from: Data("{}".utf8)), .off)
    }

    // MARK: - Mixer

    func testStoppedMixerIsExactlySilent() {
        var mixer = FocusMixer(sampleRate: rate)
        mixer.setMix(.single(.rain))
        XCTAssertTrue(mixer.isSilent)
        XCTAssertTrue(render(&mixer, seconds: 0.5).allSatisfy { $0 == 0 })
    }

    func testPlayFadesInOverTwoSecondsWithoutAClick() {
        var mixer = playingMixer(.single(.brown))
        let x = render(&mixer, seconds: 4)
        let second = Int(rate)
        let start = Analysis.rms(Array(x[0..<second / 10]))
        let middle = Analysis.rms(Array(x[second..<second + second / 10]))
        let settled = Analysis.rms(Array(x[3 * second..<4 * second]))
        XCTAssertLessThan(start, 0.01, "starts from silence")
        XCTAssertGreaterThan(middle, settled * 0.3)
        XCTAssertLessThan(middle, settled * 0.8)
        XCTAssertEqual(settled, NoiseGenerator.targetRMS, accuracy: 0.03)
        // Brown noise moves slowly; a click at the start would be a large step.
        XCTAssertLessThan(maxStep(Array(x[0..<second])), 0.02)
    }

    func testStopFadesOutOverTwoSecondsThenGoesSilent() {
        var mixer = playingMixer(.single(.pink))
        _ = render(&mixer, seconds: 2.5)
        mixer.stop()
        XCTAssertFalse(mixer.isSilent, "still fading")
        let fade = render(&mixer, seconds: 2)
        XCTAssertTrue(mixer.isSilent)
        let second = Int(rate)
        let early = Analysis.rms(Array(fade[0..<second / 10]))
        let late = Analysis.rms(Array(fade[(19 * second / 10)...]))
        XCTAssertGreaterThan(early, 0.15)
        XCTAssertLessThan(late, 0.005)
        XCTAssertTrue(render(&mixer, seconds: 0.1).allSatisfy { $0 == 0 })
    }

    func testStoppingMidFadeInGlidesDownFromWhereItWas() {
        var mixer = playingMixer(.single(.brown))
        let rising = render(&mixer, seconds: 0.5)
        mixer.stop()
        let falling = render(&mixer, seconds: 0.5)
        // No jump at the reversal point.
        XCTAssertLessThan(abs(falling[0] - rising[rising.count - 1]), 0.01)
    }

    func testChangingTheMixCrossfadesBetweenSounds() {
        var mixer = playingMixer(.single(.brown))
        _ = render(&mixer, seconds: 2)
        let brown = render(&mixer, seconds: 0.5)
        mixer.setMix(.single(.white))
        let crossfade = render(&mixer, seconds: 2)
        let after = render(&mixer, seconds: 1)
        // Brown's step size is tiny; white's is huge. The crossfade must
        // start brown-like (no instant switch) and end fully white.
        XCTAssertLessThan(maxStep(Array(crossfade[0..<Int(rate) / 100])), maxStep(brown) * 1.2)
        XCTAssertEqual(Analysis.rms(after), NoiseGenerator.targetRMS, accuracy: 0.02)
        let brightness = Analysis.decibels(
            Analysis.power(of: after, near: 8_000) / Analysis.power(of: after, near: 250))
        XCTAssertEqual(brightness, 0, accuracy: 2, "only white noise remains")
    }

    func testFullBlendPlaysAtTheLevelOfOneSound() {
        var mixer = playingMixer(FocusMix([.init(sound: .brown), .init(sound: .pink), .init(sound: .white)]))
        _ = render(&mixer, seconds: 2.2)
        let x = render(&mixer, seconds: 3)
        XCTAssertEqual(Analysis.rms(x), NoiseGenerator.targetRMS, accuracy: 0.02)
        XCTAssertLessThanOrEqual(Analysis.peak(x), 1)
    }

    func testVolumeFollowsASquaredCurveAndGlides() {
        XCTAssertEqual(FocusMixer.amplitude(forVolume: 0.5), 0.25)
        XCTAssertEqual(FocusMixer.amplitude(forVolume: 2), 1)
        XCTAssertEqual(FocusMixer.amplitude(forVolume: -1), 0)

        var mixer = playingMixer(.single(.pink), volume: 1)
        _ = render(&mixer, seconds: 2.2)
        let loud = Analysis.rms(render(&mixer, seconds: 1))
        mixer.setVolume(0.5)
        XCTAssertEqual(mixer.volume, 0.5)
        let glide = render(&mixer, seconds: 0.01)
        XCTAssertGreaterThan(Analysis.rms(glide), loud * 0.3, "doesn't jump down at once")
        _ = render(&mixer, seconds: 0.1)
        let quiet = Analysis.rms(render(&mixer, seconds: 1))
        XCTAssertEqual(quiet / loud, 0.25, accuracy: 0.02)
    }

    func testOffMixPlaysSilence() {
        var mixer = playingMixer(.off)
        XCTAssertTrue(render(&mixer, seconds: 0.5).allSatisfy { $0 == 0 })
    }
}
