import AppKit
import XCTest
import TabbiKitCore
@testable import Tabbi

/// The closed notch's equalizer plays as Core Animation keyframes
/// (`SpotifyEqualizerView`), so a playing track never wakes the app per
/// frame (drawn through a 30 fps `TimelineView` it cost about 3% CPU all
/// the time music played). These tests prove the bars hand their motion to
/// a repeating animation, keep it across repeated updates, and rest when
/// playback pauses.
@MainActor
final class SpotifyEqualizerViewTests: XCTestCase {
    func testPlayingBarsRunARepeatingSeamlessAnimation() throws {
        let view = SpotifyEqualizerView()
        view.setPlaying(true, animated: true)
        XCTAssertEqual(view.bars.count, SpotifyEqualizer.barCount)
        var firstValues: [NSNumber] = []
        for bar in view.bars {
            let animation = try XCTUnwrap(bar.animation(forKey: SpotifyEqualizerView.animationKey)
                as? CAKeyframeAnimation)
            XCTAssertEqual(animation.repeatCount, .infinity)
            XCTAssertLessThanOrEqual(animation.preferredFrameRateRange.maximum, 30)
            let values = try XCTUnwrap(animation.values as? [NSNumber])
            XCTAssertEqual(values.first, values.last, "the bar would jump when the loop restarts")
            XCTAssertGreaterThan(values.count, 100)
            firstValues.append(values[values.count / 2])
        }
        XCTAssertGreaterThan(Set(firstValues).count, 1, "bars should not move in lockstep")
    }

    func testUpdatesWhilePlayingKeepTheRunningAnimation() throws {
        let view = SpotifyEqualizerView()
        view.setPlaying(true, animated: true)
        let bar = try XCTUnwrap(view.bars.first)
        let running = try XCTUnwrap(bar.animation(forKey: SpotifyEqualizerView.animationKey))
        view.setPlaying(true, animated: true)
        XCTAssertTrue(bar.animation(forKey: SpotifyEqualizerView.animationKey) === running,
                      "a SwiftUI update restarted the bars' motion")
    }

    func testPausingRestsTheBars() {
        let view = SpotifyEqualizerView()
        view.setPlaying(true, animated: true)
        view.setPlaying(false, animated: false)
        let resting = SpotifyEqualizer.restingLevels()
        for (index, bar) in view.bars.enumerated() {
            XCTAssertNil(bar.animation(forKey: SpotifyEqualizerView.animationKey))
            XCTAssertEqual(bar.bounds.height, SpotifyEqualizerView.maxHeight * resting[index], accuracy: 1e-9)
        }
    }
}
