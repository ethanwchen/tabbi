import AppKit
import XCTest
import TabbiKitCore
@testable import TabbiKit
@testable import Tabbi

/// A menu opened from the open notch (Party's birth month and year, a
/// right-click menu) must not close it: reaching for an item takes the
/// pointer below the notch's shape, and closing there threw the pick away,
/// so Party could only be joined by typing into the menu. This drives the
/// real `NotchController` through a real `NSMenu` tracking loop.
@MainActor
final class NotchMenuHoldTests: XCTestCase {
    private func makeController() -> NotchController {
        let types: [any NotchModule.Type] = [ClosetModule.self]
        let settings = SettingsStore.ephemeral(catalog: ModuleList.catalog(of: types))
        let services = AppServices(settings: settings, moduleTypes: types, environment: ["TABBI_DEMO": "1"], arguments: [])
        // The demo's weekly recap would take the notch over (and pin it) on open.
        if let recap = services.recaps.store.unseen { services.recaps.store.markSeen(recap.week) }
        return NotchController(content: ModuleViews.notchContent(services: services),
                               inputs: ModuleViews.notchInputs(services: services))
    }

    /// The middle of the open notch and a point well below it, in screen coordinates.
    private func points(_ model: NotchViewModel) -> (inside: NSPoint, outside: NSPoint) {
        let g = model.geometry
        let top = g.screenFrame.maxY
        return (NSPoint(x: g.centerX, y: top - model.openSize.height / 2),
                NSPoint(x: g.centerX, y: top - model.openSize.height - 120))
    }

    /// Waits past the pointer-exit close delay (600 ms).
    private func waitPastCloseDelay() async throws {
        try await Task.sleep(for: .milliseconds(900))
    }

    /// Opens a real menu from the panel and, inside its tracking loop, moves
    /// the pointer to `point` (as reaching for an item does) and picks the
    /// first item.
    private func pickFromMenu(on controller: NotchController, movingTo point: NSPoint) throws -> Bool {
        let view = try XCTUnwrap(controller.panelForTesting.contentView)
        let menu = NSMenu()
        var picked = false
        let item = ClosureMenuItem(title: "May") { picked = true }
        menu.addItem(item)
        let timer = Timer(timeInterval: 0.2, repeats: false) { _ in
            MainActor.assumeIsolated {
                controller.pointerMoved(to: point)
                menu.performActionForItem(at: 0)
                menu.cancelTracking()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.midX, y: view.bounds.midY), in: view)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        return picked
    }

    func testPickingFromAMenuBelowTheNotchKeepsItOpen() async throws {
        let controller = makeController()
        let model = controller.model
        let (inside, outside) = points(model)
        model.open()
        controller.pointerMoved(to: inside)
        defer { model.close() }

        XCTAssertTrue(try pickFromMenu(on: controller, movingTo: outside), "The menu's item ran")
        try await waitPastCloseDelay()
        XCTAssertTrue(model.isOpen, "Reaching for a menu item below the notch keeps it open")

        // After the pick the pointer is still below the notch; moving there
        // keeps it open until the pointer has been back over the notch.
        controller.pointerMoved(to: NSPoint(x: outside.x + 40, y: outside.y))
        try await waitPastCloseDelay()
        XCTAssertTrue(model.isOpen, "Still open with the pointer where the menu was")

        // Back over the notch and away again closes it as always.
        controller.pointerMoved(to: inside)
        controller.pointerMoved(to: outside)
        try await waitPastCloseDelay()
        XCTAssertFalse(model.isOpen, "Leaving the notch closes it again once the menu is done")
    }

    func testLeavingTheNotchWithoutAMenuStillClosesIt() async throws {
        let controller = makeController()
        let model = controller.model
        let (inside, outside) = points(model)
        model.open()
        controller.pointerMoved(to: inside)
        controller.pointerMoved(to: outside)
        try await waitPastCloseDelay()
        XCTAssertFalse(model.isOpen)
    }
}

/// A menu item that runs a closure.
private final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void

    init(title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func fire() { run() }
}
