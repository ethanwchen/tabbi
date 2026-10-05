import CoreGraphics
import XCTest
@testable import TabbiKitCore

final class NotchVisibilityTests: XCTestCase {
    private let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let external = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
    private let ownPID: Int32 = 42

    private func isFullscreen(_ windows: [NotchVisibility.Window], on bounds: CGRect? = nil) -> Bool {
        NotchVisibility.isFullscreenAppActive(windows: windows, displayBounds: bounds ?? display, ownPID: ownPID)
    }

    func testAWindowCoveringTheWholeDisplayIsFullscreen() {
        XCTAssertTrue(isFullscreen([.init(ownerPID: 7, layer: 0, bounds: display)]))
    }

    func testAZoomedWindowBelowTheMenuBarIsNot() {
        let zoomed = CGRect(x: 0, y: 37, width: 1512, height: 945)
        XCTAssertFalse(isFullscreen([.init(ownerPID: 7, layer: 0, bounds: zoomed)]))
    }

    func testTheDesktopAndOverlaysDoNotCount() {
        XCTAssertFalse(isFullscreen([
            .init(ownerPID: 7, layer: -2147483623, bounds: display), // Finder's desktop
            .init(ownerPID: 8, layer: 25, bounds: display), // a status overlay
        ]))
    }

    func testInvisibleAndOwnWindowsDoNotCount() {
        XCTAssertFalse(isFullscreen([
            .init(ownerPID: 7, layer: 0, alpha: 0, bounds: display),
            .init(ownerPID: ownPID, layer: 0, bounds: display),
        ]))
    }

    func testAFullscreenAppOnAnotherDisplayDoesNotHideTheNotch() {
        let windows: [NotchVisibility.Window] = [.init(ownerPID: 7, layer: 0, bounds: external)]
        XCTAssertFalse(isFullscreen(windows))
        XCTAssertTrue(isFullscreen(windows, on: external))
    }

    func testNoDisplayMeansNoFullscreen() {
        XCTAssertFalse(isFullscreen([.init(ownerPID: 7, layer: 0, bounds: display)], on: .zero))
    }

    func testTheShortcutRevealsTheNotchOverAFullscreenApp() {
        XCTAssertFalse(NotchVisibility.isShown(hideInFullscreen: true, fullscreenAppActive: true, revealed: false))
        XCTAssertTrue(NotchVisibility.isShown(hideInFullscreen: true, fullscreenAppActive: true, revealed: true))
        XCTAssertTrue(NotchVisibility.isShown(hideInFullscreen: false, fullscreenAppActive: true, revealed: false))
        XCTAssertTrue(NotchVisibility.isShown(hideInFullscreen: true, fullscreenAppActive: false, revealed: false))
    }

    func testExternalDisplaysCanBeExcluded() {
        let builtIn = DisplayPreference.Screen(id: 1, isBuiltIn: true, isMain: false)
        let monitor = DisplayPreference.Screen(id: 2, isBuiltIn: false, isMain: true)
        let both = [builtIn, monitor]

        XCTAssertEqual(NotchVisibility.screen(for: .main, showOnExternalDisplays: true, in: both), monitor)
        XCTAssertEqual(NotchVisibility.screen(for: .main, showOnExternalDisplays: false, in: both), builtIn)
        XCTAssertEqual(NotchVisibility.screen(for: .specific(2), showOnExternalDisplays: false, in: both), builtIn)
        // Lid closed: only the monitor is connected.
        XCTAssertEqual(NotchVisibility.screen(for: .builtIn, showOnExternalDisplays: true, in: [monitor]), monitor)
        XCTAssertNil(NotchVisibility.screen(for: .builtIn, showOnExternalDisplays: false, in: [monitor]))
    }
}
