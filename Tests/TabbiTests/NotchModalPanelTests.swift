import AppKit
import XCTest
@testable import TabbiKit

/// The open notch floats above other windows, so it closes for an open or
/// save panel or an app-modal alert (AI Usage's folder picker, the crash
/// report question) instead of covering it, and stays for anything else.
@MainActor
final class NotchModalPanelTests: XCTestCase {
    func testOpenAndSavePanelsAndModalAlertsMakeTheNotchWay() {
        XCTAssertTrue(NotchController.isModalPanel(NSOpenPanel()))
        XCTAssertTrue(NotchController.isModalPanel(NSSavePanel()))
        let alert = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        alert.level = .modalPanel
        XCTAssertTrue(NotchController.isModalPanel(alert))
    }

    func testOrdinaryWindowsKeepTheNotchOpen() {
        let settings = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        XCTAssertFalse(NotchController.isModalPanel(settings))
        let floating = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel], backing: .buffered, defer: true)
        floating.level = .statusBar
        XCTAssertFalse(NotchController.isModalPanel(floating))
    }
}
