import XCTest
import TabbiKitCore
import TabbiKit
@testable import Tabbi

/// While a takeover (first-run setup) fills the notch, the notch opens on
/// it and stays open, and tab keys leave the tabs alone.
@MainActor
final class NotchTakeoverTests: XCTestCase {
    private func makeModel() -> NotchViewModel {
        let geometry = NotchGeometry(notchSize: CGSize(width: 185, height: 32), hasHardwareNotch: true,
                                     screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117), centerX: 864)
        return NotchViewModel(geometry: geometry, layout: ModuleLayout(catalog: ModuleList.catalog))
    }

    func testTakeoverOpensAndPinsTheNotch() {
        let model = makeModel()
        model.showsTakeover = true
        XCTAssertTrue(model.isOpen)
        XCTAssertTrue(model.isPinned)
        model.showsTakeover = false
        XCTAssertTrue(model.isOpen, "the tabs show where setup was")
        XCTAssertFalse(model.isPinned)
    }

    func testReopeningDuringATakeoverPinsAgain() {
        let model = makeModel()
        model.showsTakeover = true
        model.close()
        XCTAssertFalse(model.isPinned)
        model.open()
        XCTAssertTrue(model.isPinned)
    }

    func testTabKeysPauseDuringATakeover() {
        let model = makeModel()
        let selected = model.selected
        model.showsTakeover = true
        model.selectNext()
        model.selectPrevious()
        XCTAssertFalse(model.select(shortcut: 2))
        XCTAssertEqual(model.selected, selected)
        model.showsTakeover = false
        XCTAssertTrue(model.select(shortcut: 2))
    }
}
