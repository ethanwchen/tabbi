import XCTest
import TabbiKitCore

/// The open notch header keeps every control clear of the camera cutout at
/// any tab count, tightening the tabs before any of them overflow.
final class NotchHeaderLayoutTests: XCTestCase {
    private let canvas: CGFloat = 560
    private let header: CGFloat = 32
    /// Real notch widths (narrow, 14"/16" MacBook Pro, wide) and a notchless display.
    private let notches: [CGSize?] = [CGSize(width: 160, height: 32), CGSize(width: 185, height: 32),
                                      CGSize(width: 210, height: 38), nil]

    private func layout(tabs: Int, notch: CGSize?, shortcuts: Int = 1,
                        title: CGFloat = 90) -> NotchHeaderLayout {
        NotchHeaderLayout(canvasWidth: canvas, notchSize: notch, headerHeight: max(notch?.height ?? 0, header),
                          tabCount: tabs, shortcutCount: shortcuts, titleWidth: title)
    }

    func testNoControlMeetsTheNotchAtAnyTabCount() {
        let metrics = NotchHeaderLayout.Metrics()
        for notch in notches {
            for tabs in 1...12 {
                for shortcuts in 0...1 {
                    let header = layout(tabs: tabs, notch: notch, shortcuts: shortcuts)
                    let label = "\(tabs) tabs, \(shortcuts) shortcuts, notch \(notch.map { "\($0.width)" } ?? "none")"
                    // The cutout plus its safe margin, or the bare center on a notchless display.
                    let keepOut = header.cutout?.insetBy(dx: -metrics.cutoutMargin, dy: 0)
                        ?? CGRect(x: canvas / 2, y: 0, width: 0, height: 32)
                    for frame in header.controlFrames {
                        XCTAssertFalse(frame.intersects(keepOut), "\(label): \(frame) meets \(keepOut)")
                        XCTAssertGreaterThanOrEqual(frame.minX, metrics.outerInset, label)
                        XCTAssertLessThanOrEqual(frame.maxX, canvas - metrics.outerInset, label)
                    }
                    for tab in header.tabFrames + [header.moreFrame].compactMap({ $0 }) {
                        XCTAssertGreaterThanOrEqual(tab.width, metrics.minTabWidth, label)
                        XCTAssertGreaterThanOrEqual(tab.height, 24, label)
                        XCTAssertLessThanOrEqual(tab.maxX, header.leadingZone.maxX, label)
                    }
                    XCTAssertEqual(header.hasOverflow, header.visibleTabCount < tabs, label)
                    XCTAssertGreaterThan(header.visibleTabCount, 0, label)
                    XCTAssertEqual(header.shortcutFrames.count, shortcuts, label)
                }
            }
        }
    }

    func testControlsDoNotOverlapEachOther() {
        for notch in notches {
            for tabs in 1...12 {
                let frames = layout(tabs: tabs, notch: notch).controlFrames
                for (index, frame) in frames.enumerated() {
                    for other in frames[(index + 1)...] {
                        XCTAssertFalse(frame.intersects(other), "\(tabs) tabs: \(frame) overlaps \(other)")
                    }
                }
            }
        }
    }

    func testFewTabsKeepFullSize() {
        let header = layout(tabs: 4, notch: CGSize(width: 185, height: 32))
        XCTAssertEqual(header.tabWidth, 28)
        XCTAssertEqual(header.tabSpacing, 2)
        XCTAssertFalse(header.hasOverflow)
    }

    func testTabsTightenBeforeTheyOverflow() {
        let notch = CGSize(width: 185, height: 32)
        let five = layout(tabs: 5, notch: notch)
        XCTAssertFalse(five.hasOverflow, "Med School's five tabs fit by shrinking a little")
        XCTAssertLessThan(five.tabWidth, 28)
        let six = layout(tabs: 6, notch: notch)
        XCTAssertFalse(six.hasOverflow)
        XCTAssertEqual(six.tabWidth, 24)
        XCTAssertEqual(six.tabSpacing, 0)
    }

    func testTabsThatDoNotFitMoveBehindMore() throws {
        let header = layout(tabs: 10, notch: CGSize(width: 185, height: 32))
        XCTAssertTrue(header.hasOverflow)
        XCTAssertEqual(header.visibleTabCount, 5)
        let more = try XCTUnwrap(header.moreFrame)
        XCTAssertEqual(more.minX, try XCTUnwrap(header.tabFrames.last).maxX, "more follows the last tab")
    }

    func testOverflowListOpensBelowTheNotchAndTheMoreButton() throws {
        for notch in notches {
            let header = layout(tabs: 10, notch: notch)
            let more = try XCTUnwrap(header.moreFrame)
            let top = try XCTUnwrap(header.moreListTop)
            XCTAssertGreaterThan(top, more.maxY)
            XCTAssertGreaterThan(top, header.cutout?.maxY ?? 0, "a taller notch pushes the list below it")
        }
        XCTAssertNil(layout(tabs: 3, notch: CGSize(width: 185, height: 32)).moreListTop)
    }

    func testNotchlessDisplayFitsMoreTabs() {
        let notched = layout(tabs: 7, notch: CGSize(width: 185, height: 32))
        let notchless = layout(tabs: 7, notch: nil)
        XCTAssertTrue(notched.hasOverflow)
        XCTAssertFalse(notchless.hasOverflow)
        XCTAssertNil(notchless.cutout)
    }

    func testShortcutSitsAtTheFarRightAfterTheGear() throws {
        let header = layout(tabs: 4, notch: CGSize(width: 185, height: 32))
        let paw = try XCTUnwrap(header.shortcutFrames.last)
        XCTAssertEqual(paw.maxX, canvas - NotchHeaderLayout.Metrics().outerInset)
        XCTAssertLessThan(header.gearFrame.maxX, paw.minX)
        XCTAssertLessThan(try XCTUnwrap(header.titleFrame).maxX, header.gearFrame.minX)
    }

    func testLongTitleTruncatesAndATooNarrowOneIsDropped() throws {
        let notch = CGSize(width: 210, height: 32)
        let long = layout(tabs: 4, notch: notch, title: 120)
        let title = try XCTUnwrap(long.titleFrame)
        XCTAssertLessThan(title.width, 120, "a long title truncates")
        XCTAssertGreaterThanOrEqual(title.minX, long.trailingZone.minX)

        let short = layout(tabs: 4, notch: notch, title: 30)
        XCTAssertEqual(short.titleFrame?.width, 30, "a short title shows whole")

        let crowded = layout(tabs: 4, notch: notch, shortcuts: 3, title: 120)
        XCTAssertNil(crowded.titleFrame, "the title goes before anything collides")
        XCTAssertEqual(crowded.shortcutFrames.count, 3)
    }
}
