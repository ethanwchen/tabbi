import XCTest
import NotchDeckCore

final class FocusPlayerInfoTests: XCTestCase {
    func testReadsEachPlayerState() {
        XCTAssertEqual(FocusPlayerInfo.state(from: ["Player State": "Playing"]), .playing)
        XCTAssertEqual(FocusPlayerInfo.state(from: ["Player State": "Paused"]), .paused)
        XCTAssertEqual(FocusPlayerInfo.state(from: ["Player State": "Stopped"]), .stopped)
    }

    func testIgnoresMissingOrUnknownState() {
        XCTAssertNil(FocusPlayerInfo.state(from: nil))
        XCTAssertNil(FocusPlayerInfo.state(from: ["Name": "Song"]))
        XCTAssertNil(FocusPlayerInfo.state(from: ["Player State": "Buffering"]))
        XCTAssertNil(FocusPlayerInfo.state(from: ["Player State": 1]))
    }

    func testNamesEachAppsNotification() {
        XCTAssertEqual(FocusPlayerInfo.notificationName(for: .spotify).rawValue, "com.spotify.client.PlaybackStateChanged")
        XCTAssertEqual(FocusPlayerInfo.notificationName(for: .music).rawValue, "com.apple.Music.playerInfo")
    }
}
