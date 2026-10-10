import XCTest
import AppKit
import TabbiKit

/// General's privacy switches: the notch panel leaves screen captures and
/// Mission Control only when the user asks, and both switch back.
@MainActor
final class NotchPanelPrivacyTests: XCTestCase {
    func testPanelShowsInCapturesAndMissionControlByDefault() {
        let panel = NotchPanel(contentRect: .zero)
        panel.applyPrivacy(hideFromScreenCapture: false, hideInMissionControl: false)
        XCTAssertNotEqual(panel.sharingType, .none)
        XCTAssertTrue(panel.collectionBehavior.contains(.stationary))
        XCTAssertFalse(panel.collectionBehavior.contains(.transient))
    }

    func testHidingAndShowingAgain() {
        let panel = NotchPanel(contentRect: .zero)
        panel.applyPrivacy(hideFromScreenCapture: true, hideInMissionControl: true)
        XCTAssertEqual(panel.sharingType, .none)
        XCTAssertTrue(panel.collectionBehavior.contains(.transient))
        XCTAssertFalse(panel.collectionBehavior.contains(.stationary), "the two Mission Control behaviors exclude each other")
        XCTAssertTrue(panel.collectionBehavior.isSuperset(of: [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]),
                      "the rest of the panel's behavior is kept")

        panel.applyPrivacy(hideFromScreenCapture: false, hideInMissionControl: false)
        XCTAssertEqual(panel.sharingType, .readOnly)
        XCTAssertTrue(panel.collectionBehavior.contains(.stationary))
        XCTAssertFalse(panel.collectionBehavior.contains(.transient))
    }
}
