import XCTest
@testable import TabbiKitCore

/// Reordering tabs in Settings: by dragging a row, and one slot at a time
/// from the keyboard or VoiceOver. The header shortcut (the paw) never moves.
final class TabReorderTests: XCTestCase {
    /// A layout whose "pet" module opens from the header (key P), not a tab.
    private func layout(order: [ModuleID], disabled: Set<ModuleID> = []) -> ModuleLayout {
        let catalog = ModuleCatalog(["a", "b", "c", "d", "pet"].map { (id: ModuleID) in
            ModuleDescriptor(id: id, title: id.rawValue, symbol: "circle", category: .productivity,
                             accent: ModuleAccent(red: 1, green: 1, blue: 1),
                             headerShortcut: id == "pet" ? ModuleHeaderShortcut(label: "Your pet", key: "P") : nil)
        })
        return ModuleLayout(order: order, disabled: disabled, catalog: catalog)
    }

    func testMovingATabToASlotLandsItThereInBothDirections() {
        var tabs = layout(order: ["a", "b", "c", "d", "pet"])
        XCTAssertTrue(tabs.moveTab("a", to: 2))
        XCTAssertEqual(tabs.tabs, ["b", "c", "a", "d"])
        XCTAssertTrue(tabs.moveTab("d", to: 0))
        XCTAssertEqual(tabs.tabs, ["d", "b", "c", "a"])
        XCTAssertFalse(tabs.moveTab("c", to: 2), "dropping a row on its own slot changes nothing")
        XCTAssertTrue(tabs.moveTab("b", to: 99), "a slot past the end means the last one")
        XCTAssertEqual(tabs.tabs, ["d", "c", "a", "b"])
    }

    func testThePawAndLibraryModulesKeepTheirSlots() {
        var tabs = layout(order: ["a", "pet", "b", "c", "d"], disabled: ["c"])
        XCTAssertTrue(tabs.moveTab("d", to: 0))
        XCTAssertEqual(tabs.tabs, ["d", "a", "b"])
        XCTAssertEqual(tabs.order, ["d", "pet", "a", "c", "b"])
        XCTAssertEqual(tabs.headerShortcuts, ["pet"])
        XCTAssertFalse(tabs.moveTab("pet", to: 0), "the paw always sits at the end of the tab bar")
        XCTAssertFalse(tabs.moveTab("c", to: 0), "a library module is not a tab")
        XCTAssertEqual(tabs.order, ["d", "pet", "a", "c", "b"])
    }

    func testStepMovesStopAtEitherEnd() {
        var tabs = layout(order: ["a", "b", "c", "pet"])
        XCTAssertFalse(tabs.canMoveTab("a", by: -1))
        XCTAssertFalse(tabs.moveTab("a", by: -1))
        XCTAssertTrue(tabs.canMoveTab("a", by: 1))
        XCTAssertTrue(tabs.moveTab("a", by: 1))
        XCTAssertEqual(tabs.tabs, ["b", "a", "c"])
        XCTAssertTrue(tabs.moveTab("a", by: 1))
        XCTAssertEqual(tabs.tabs, ["b", "c", "a"])
        XCTAssertFalse(tabs.canMoveTab("a", by: 1), "the last tab can't pass the paw")
        XCTAssertFalse(tabs.moveTab("a", by: 1))
        XCTAssertFalse(tabs.canMoveTab("pet", by: -1))
        XCTAssertFalse(tabs.canMoveTab("b", by: 0))
    }

    func testTheLiftedRowFollowsThePointerButStaysInTheList() {
        var drag = RowReorderDrag(from: 1, count: 4, rowHeight: 40)
        drag.translation = 30
        XCTAssertEqual(drag.liftedOffset, 30)
        drag.translation = -500
        XCTAssertEqual(drag.liftedOffset, -40, "no higher than the first slot")
        drag.translation = 500
        XCTAssertEqual(drag.liftedOffset, 80, "no lower than the last slot")
        XCTAssertEqual(drag.target, 3)
    }

    func testTheTargetIsTheSlotUnderTheRowsCenter() {
        var drag = RowReorderDrag(from: 0, count: 3, rowHeight: 40)
        drag.translation = 19
        XCTAssertEqual(drag.target, 0)
        XCTAssertFalse(drag.movesRow)
        drag.translation = 21
        XCTAssertEqual(drag.target, 1)
        XCTAssertTrue(drag.movesRow)
    }

    func testPassedRowsSlideTowardTheGap() {
        var down = RowReorderDrag(from: 0, count: 4, rowHeight: 40, translation: 80)
        XCTAssertEqual(down.target, 2)
        XCTAssertEqual((0..<4).map(down.offset(at:)), [80, -40, -40, 0])
        down.translation = 0
        XCTAssertEqual((0..<4).map(down.offset(at:)), [0, 0, 0, 0])

        let up = RowReorderDrag(from: 3, count: 4, rowHeight: 40, translation: -85)
        XCTAssertEqual(up.target, 1)
        XCTAssertEqual((0..<4).map(up.offset(at:)), [0, 40, 40, -85])
    }

    func testReleasingOnTheTargetMatchesTheLayoutMove() {
        var tabs = layout(order: ["a", "b", "c", "d"])
        let drag = RowReorderDrag(from: 3, count: tabs.tabs.count, rowHeight: 36, translation: -70)
        tabs.moveTab(tabs.tabs[drag.from], to: drag.target)
        XCTAssertEqual(tabs.tabs, ["a", "d", "b", "c"])
    }
}
