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

    // The window lists below are what a 14-inch MacBook Pro (1512x982,
    // 37 pt menu bar beside the camera housing) reports. The menu bar window
    // stays listed in a fullscreen space, so only the status items and the
    // Dock tell the desktop apart from it.
    private var menuBar: NotchVisibility.Window {
        .init(ownerPID: 1, layer: NotchVisibility.menuBarLayer, bounds: CGRect(x: 0, y: 0, width: 1512, height: 37))
    }

    private var clock: NotchVisibility.Window {
        .init(ownerPID: 2, layer: NotchVisibility.statusItemLayer, bounds: CGRect(x: 1365, y: 0, width: 147, height: 37))
    }

    private var dock: NotchVisibility.Window {
        .init(ownerPID: 3, layer: NotchVisibility.dockLayer, bounds: display)
    }

    private let belowNotch = CGRect(x: 0, y: 37, width: 1512, height: 945)

    func testAZoomedWindowOnTheDesktopIsNot() {
        XCTAssertFalse(isFullscreen([clock, menuBar, dock, .init(ownerPID: 7, layer: 0, bounds: belowNotch)]))
    }

    func testAZoomedWindowWithOnlyTheDockShownIsNot() {
        XCTAssertFalse(isFullscreen([menuBar, dock, .init(ownerPID: 7, layer: 0, bounds: belowNotch)]))
    }

    func testAZoomedWindowWithOnlyStatusItemsShownIsNot() {
        XCTAssertFalse(isFullscreen([clock, menuBar, .init(ownerPID: 7, layer: 0, bounds: belowNotch)]))
    }

    func testAFullscreenSpaceOnANotchedDisplayIsFullscreen() {
        // The fullscreen app's hidden title bar strip and reveal window come
        // along with alpha 0, and the menu bar window is still listed.
        XCTAssertTrue(isFullscreen([
            .init(ownerPID: 7, layer: 26, alpha: 0, bounds: CGRect(x: 0, y: 0, width: 1512, height: 37)),
            menuBar,
            .init(ownerPID: 7, layer: 0, alpha: 0, bounds: CGRect(x: 0, y: 37, width: 1512, height: 32)),
            .init(ownerPID: 7, layer: 0, bounds: belowNotch),
        ]))
    }

    func testDesktopChromeOnAnotherDisplayDoesNotKeepTheNotchShown() {
        let otherClock = NotchVisibility.Window(ownerPID: 2, layer: NotchVisibility.statusItemLayer,
                                                bounds: CGRect(x: 3925, y: 0, width: 147, height: 25))
        let otherDock = NotchVisibility.Window(ownerPID: 3, layer: NotchVisibility.dockLayer, bounds: external)
        XCTAssertTrue(isFullscreen([otherClock, otherDock, menuBar, .init(ownerPID: 7, layer: 0, bounds: belowNotch)]))
    }

    func testOwnStatusWindowsDoNotKeepTheNotchShown() {
        let ownOverlay = NotchVisibility.Window(ownerPID: ownPID, layer: NotchVisibility.statusItemLayer,
                                                bounds: CGRect(x: 428, y: 0, width: 656, height: 276))
        XCTAssertTrue(isFullscreen([ownOverlay, menuBar, .init(ownerPID: 7, layer: 0, bounds: belowNotch)]))
    }

    func testAWindowThatLeavesPartOfTheDisplayUncoveredIsNot() {
        let halfWidth = CGRect(x: 0, y: 37, width: 756, height: 945)
        let shortWindow = CGRect(x: 0, y: 37, width: 1512, height: 600)
        XCTAssertFalse(isFullscreen([.init(ownerPID: 7, layer: 0, bounds: halfWidth),
                                     .init(ownerPID: 8, layer: 0, bounds: shortWindow)]))
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
