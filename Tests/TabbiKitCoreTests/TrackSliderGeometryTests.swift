import XCTest
@testable import TabbiKitCore

/// The notch's track sliders keep the whole knob on the track and its
/// center under the pointer.
final class TrackSliderGeometryTests: XCTestCase {
    /// The mixer's volume slider: 234 pt wide, a 10 pt (grown) knob.
    private let mixer = TrackSliderGeometry(width: 234, knobDiameter: 10)

    func testTheKnobStaysOnTheTrackAtBothEnds() {
        for fraction in [0, 0.001, 0.25, 0.5, 0.999, 1] {
            let center = mixer.knobCenter(at: fraction)
            XCTAssertGreaterThanOrEqual(center - mixer.knobRadius, 0, "fraction \(fraction)")
            XCTAssertLessThanOrEqual(center + mixer.knobRadius, mixer.width, "fraction \(fraction)")
        }
        XCTAssertEqual(mixer.knobOffset(at: 0), 0, "flush with the leading end at 0")
        XCTAssertEqual(mixer.knobOffset(at: 1) + mixer.knobDiameter, mixer.width, "flush with the trailing end at 1")
    }

    func testOutOfRangeValuesPinTheKnobToTheEnds() {
        XCTAssertEqual(mixer.knobCenter(at: -0.5), mixer.knobCenter(at: 0))
        XCTAssertEqual(mixer.knobCenter(at: 7), mixer.knobCenter(at: 1))
        XCTAssertEqual(mixer.knobCenter(at: .nan), mixer.knobCenter(at: 0))
    }

    func testTheKnobCenterFollowsThePointerExactly() {
        // Every x a drag can reach between the ends puts the knob's center
        // right under the pointer: no lag, no jump.
        var x = mixer.knobRadius
        while x <= mixer.width - mixer.knobRadius {
            XCTAssertEqual(mixer.knobCenter(at: mixer.fraction(atX: x)), x, accuracy: 1e-9, "x \(x)")
            x += 0.5
        }
    }

    func testThePointerMovesTheValueContinuously() {
        // Equal pointer steps make equal value steps: the mapping is linear,
        // so the knob glides rather than snapping.
        let step = mixer.fraction(atX: 101) - mixer.fraction(atX: 100)
        XCTAssertEqual(step, 1 / mixer.travel, accuracy: 1e-12)
        XCTAssertEqual(mixer.fraction(atX: 151) - mixer.fraction(atX: 150), step, accuracy: 1e-12)
    }

    func testAPointerPastEitherEndPinsTheValue() {
        XCTAssertEqual(mixer.fraction(atX: -40), 0)
        XCTAssertEqual(mixer.fraction(atX: 2), 0, "inside the knob's radius at the start is still 0")
        XCTAssertEqual(mixer.fraction(atX: 232), 1, "inside the knob's radius at the end is already 1")
        XCTAssertEqual(mixer.fraction(atX: 900), 1)
        XCTAssertEqual(mixer.fraction(atX: -.infinity), 0)
        XCTAssertEqual(mixer.fraction(atX: .infinity), 1)
        XCTAssertEqual(mixer.fraction(atX: .nan), 0)
    }

    func testTheFillRunsToTheKnobsCenterAndIsEmptyAtZero() {
        XCTAssertEqual(mixer.fillWidth(at: 0), 0)
        XCTAssertEqual(mixer.fillWidth(at: 0.5), mixer.knobCenter(at: 0.5))
        XCTAssertEqual(mixer.fillWidth(at: 1), mixer.width - mixer.knobRadius)
    }

    func testDegenerateTracksNeverInvertTheRange() {
        let tiny = TrackSliderGeometry(width: 6, knobDiameter: 10)
        XCTAssertEqual(tiny.knobRadius, 3)
        XCTAssertEqual(tiny.travel, 0)
        XCTAssertEqual(tiny.knobCenter(at: 1), 3)
        XCTAssertEqual(tiny.fraction(atX: 1), 0)
        XCTAssertEqual(tiny.fraction(atX: 5), 1)

        let empty = TrackSliderGeometry(width: -20, knobDiameter: .nan)
        XCTAssertEqual(empty.width, 0)
        XCTAssertEqual(empty.knobDiameter, 0)
        XCTAssertEqual(empty.fillWidth(at: 1), 0)

        let bare = TrackSliderGeometry(width: 200, knobDiameter: 0)
        XCTAssertEqual(bare.fraction(atX: 50), 0.25, "without a knob it maps the full width")
        XCTAssertEqual(bare.fillWidth(at: 1), 200)
    }
}
