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

    private func isShown(_ mode: NotchMode = .alwaysVisible, hideInFullscreen: Bool = true,
                         fullscreen: Bool = false, revealed: Bool = false,
                         pointerNear: Bool = false, isOpen: Bool = false) -> Bool {
        NotchVisibility.isShown(mode: mode, hideInFullscreen: hideInFullscreen, fullscreenAppActive: fullscreen,
                                revealed: revealed, pointerNear: pointerNear, isOpen: isOpen)
    }

    func testTheShortcutRevealsTheNotchOverAFullscreenApp() {
        XCTAssertFalse(isShown(fullscreen: true))
        XCTAssertTrue(isShown(fullscreen: true, revealed: true))
        XCTAssertTrue(isShown(hideInFullscreen: false, fullscreen: true))
        XCTAssertTrue(isShown())
    }

    func testAlwaysVisibleIsDrawnWithoutThePointer() {
        XCTAssertTrue(isShown(.alwaysVisible))
    }

    func testShowOnHoverIsDrawnOnlyWhileThePointerIsNearOrTheNotchIsOpen() {
        XCTAssertFalse(isShown(.showOnHover))
        XCTAssertTrue(isShown(.showOnHover, pointerNear: true))
        XCTAssertTrue(isShown(.showOnHover, isOpen: true), "an open notch stays until it closes")
        XCTAssertTrue(isShown(.showOnHover, revealed: true))
    }

    func testHiddenIgnoresThePointerAndShowsOnlyForTheShortcut() {
        XCTAssertFalse(isShown(.hidden))
        XCTAssertFalse(isShown(.hidden, pointerNear: true))
        XCTAssertTrue(isShown(.hidden, revealed: true))
        XCTAssertTrue(isShown(.hidden, isOpen: true))
    }

    func testAFullscreenAppHidesTheNotchInEveryModeUnlessRevealed() {
        for mode in NotchMode.allCases {
            XCTAssertFalse(isShown(mode, fullscreen: true, pointerNear: true, isOpen: true), "\(mode)")
            XCTAssertTrue(isShown(mode, fullscreen: true, revealed: true), "\(mode)")
        }
    }

    func testHoverZoneWidensTheClosedNotchAndReachesTheTop() {
        // A 200x32 notch at the top of a 900 pt tall screen.
        let notch = CGRect(x: 620, y: 868, width: 200, height: 32)
        let zone = NotchVisibility.hoverZone(closedNotch: notch)
        XCTAssertEqual(zone.maxY, notch.maxY)
        XCTAssertEqual(zone.minX, notch.minX - NotchVisibility.hoverZoneMargin.width)
        XCTAssertEqual(zone.maxX, notch.maxX + NotchVisibility.hoverZoneMargin.width)
        XCTAssertEqual(zone.minY, notch.minY - NotchVisibility.hoverZoneMargin.height)
        XCTAssertTrue(NotchVisibility.hoverZone(closedNotch: .zero).isNull)
    }

    func testThePointerStaysNearOnTheDrawnShapeButNotBesideAHiddenOne() {
        let zone = NotchVisibility.hoverZone(closedNotch: CGRect(x: 620, y: 868, width: 200, height: 32))
        let wing = CGPoint(x: 880, y: 890) // beside the notch, on a preview wing
        let shape = CGRect(x: 540, y: 868, width: 360, height: 32)
        XCTAssertTrue(NotchVisibility.isPointerNear(CGPoint(x: 720, y: 899), hoverZone: zone, drawnShape: nil))
        XCTAssertFalse(NotchVisibility.isPointerNear(wing, hoverZone: zone, drawnShape: nil))
        XCTAssertTrue(NotchVisibility.isPointerNear(wing, hoverZone: zone, drawnShape: shape))
        XCTAssertFalse(NotchVisibility.isPointerNear(CGPoint(x: 720, y: 500), hoverZone: zone, drawnShape: shape))
    }

    func testModesKeepTheirStoredNames() {
        XCTAssertEqual(NotchMode.allCases.map(\.rawValue), ["always", "hover", "hidden"])
        XCTAssertEqual(NotchMode.default, .alwaysVisible)
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
