import XCTest
@testable import TabbiKitCore

final class RowViewportTests: XCTestCase {
    func testAListEndsOnTheLastWholeRow() {
        XCTAssertEqual(RowViewport.height(fitting: 119, rowHeight: 22), 110)
        XCTAssertEqual(RowViewport.height(fitting: 131.9, rowHeight: 22), 110)
    }

    func testAnExactFitKeepsEveryRow() {
        XCTAssertEqual(RowViewport.height(fitting: 132, rowHeight: 22), 132)
    }

    func testASpaceShorterThanOneRowIsKept() {
        XCTAssertEqual(RowViewport.height(fitting: 15, rowHeight: 22), 15)
        XCTAssertEqual(RowViewport.height(fitting: -4, rowHeight: 22), 0)
    }

    func testAnInvalidRowHeightLeavesTheSpaceAsIs() {
        XCTAssertEqual(RowViewport.height(fitting: 100, rowHeight: 0), 100)
    }
}
