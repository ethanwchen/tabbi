import XCTest
import TabbiKitCore

final class NotchPointerHoldTests: XCTestCase {
    func testAMenuOnTheOpenNotchHoldsItUntilThePointerIsBack() {
        var hold = NotchPointerHold()
        XCTAssertFalse(hold.holdsOpen)
        hold.menuBegan(notchIsOpen: true)
        XCTAssertTrue(hold.holdsOpen)
        hold.pointerEntered()
        XCTAssertTrue(hold.holdsOpen, "The menu is still open over the notch")
        hold.menuEnded()
        XCTAssertTrue(hold.holdsOpen, "Picked with the pointer still where the item was")
        hold.pointerEntered()
        XCTAssertFalse(hold.holdsOpen, "Back over the notch: leaving closes it again")
    }

    func testAMenuOnTheClosedNotchHoldsNothing() {
        var hold = NotchPointerHold()
        hold.menuBegan(notchIsOpen: false)
        XCTAssertFalse(hold.holdsOpen)
        hold.menuEnded()
        XCTAssertEqual(hold, NotchPointerHold())
    }

    func testClosingTheNotchEndsTheHold() {
        var hold = NotchPointerHold()
        hold.menuBegan(notchIsOpen: true)
        hold.notchClosed()
        XCTAssertFalse(hold.holdsOpen)
        hold.menuEnded()
        XCTAssertEqual(hold.openMenus, 0)
    }

    func testNestedMenusHoldUntilTheLastCloses() {
        var hold = NotchPointerHold()
        hold.menuBegan(notchIsOpen: true)
        hold.menuBegan(notchIsOpen: true)
        hold.menuEnded()
        hold.pointerEntered()
        XCTAssertTrue(hold.holdsOpen)
        hold.menuEnded()
        hold.pointerEntered()
        XCTAssertFalse(hold.holdsOpen)
    }
}
