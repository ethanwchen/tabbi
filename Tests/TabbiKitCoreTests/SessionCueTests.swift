import XCTest
@testable import TabbiKitCore

final class SessionCueTests: XCTestCase {
    func testOnlyAFreshFocusBlockCuesAStart() {
        XCTAssertEqual(SessionCue.start(wasIdle: true, isFocus: true), .focusStarted)
        XCTAssertNil(SessionCue.start(wasIdle: false, isFocus: true), "resuming after a pause")
        XCTAssertNil(SessionCue.start(wasIdle: true, isFocus: false), "starting a break")
    }

    func testOnlyABreakEndingCuesItsEnd() {
        XCTAssertEqual(SessionCue.phaseEnded(wasBreak: true), .breakOver)
        XCTAssertNil(SessionCue.phaseEnded(wasBreak: false), "a finished focus block celebrates instead")
    }

    func testStartSoundIsSofterThanCelebrationsAndFollowsSettings() throws {
        let sound = try XCTUnwrap(SessionCue.focusStarted.sound(isEnabled: true))
        let burst = try XCTUnwrap(CelebrationSound.cue(for: .burst, isEnabled: true, eventHasSound: false))
        XCTAssertLessThan(sound.volume, burst.volume)
        XCTAssertNil(SessionCue.focusStarted.sound(isEnabled: false))
        // The break's own chime is its sound.
        XCTAssertNil(SessionCue.breakOver.sound(isEnabled: true))
    }
}
