import XCTest
@testable import NotchKitCore

final class CoachAppListTests: XCTestCase {
    func testToggleDistractingAddsThenRemovesIgnoringCase() {
        var apps = CoachAppList()
        apps.toggleDistracting("com.hnc.Discord")
        XCTAssertTrue(apps.isDistracting("COM.HNC.DISCORD"))
        apps.toggleDistracting("com.hnc.discord")
        XCTAssertFalse(apps.isDistracting("com.hnc.Discord"))
        XCTAssertEqual(apps.category(of: "com.hnc.Discord"), .neutral)
    }

    func testToggleDistractingTakesAFocusAppOffTheFocusList() {
        var apps = CoachAppList()
        apps.toggleDistracting("net.ankiweb.anki")
        XCTAssertEqual(apps.category(of: "net.ankiweb.anki"), .distracting)
    }

    func testAddedDistractingListsOnlyAppsBeyondTheSuggestionsSorted() {
        var apps = CoachAppList()
        apps.markDistracting("com.valvesoftware.steam")
        apps.markDistracting("com.zeta.Game")
        apps.markDistracting("com.alpha.Video")
        XCTAssertEqual(apps.addedDistracting, ["com.alpha.video", "com.zeta.game"])
    }
}
