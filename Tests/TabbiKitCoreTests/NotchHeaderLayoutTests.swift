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

    func testHiddenTabsKeepTheirOrderAndMarkMoreWhileOpen() {
        let header = layout(tabs: 8, notch: CGSize(width: 185, height: 32))
        let tabs = ["now", "system", "usage", "today", "ask", "focus", "anki", "party"]
        XCTAssertEqual(header.overflowTabs(tabs), Array(tabs[header.visibleTabCount...]))
        XCTAssertEqual(header.overflowTabs(tabs).count + header.visibleTabCount, tabs.count)
        XCTAssertEqual(header.overflowSelection(in: tabs, selected: "party"), "party",
                       "an open hidden tab selects the more button")
        XCTAssertNil(header.overflowSelection(in: tabs, selected: "now"), "a visible tab keeps its own pill")
        XCTAssertNil(header.overflowSelection(in: tabs, selected: nil))
        let roomy = layout(tabs: 3, notch: nil)
        XCTAssertEqual(roomy.overflowTabs(["a", "b", "c"]), [])
        XCTAssertNil(roomy.overflowSelection(in: ["a", "b", "c"], selected: "c"))
    }

    func testOverflowFollowsThePanelWidth() {
        // Five tabs (Med School) fit on Regular and Large, while Compact moves
        // the last two behind "more" and keeps the gear and paw.
        let notch = CGSize(width: 185, height: 32)
        func header(_ size: PanelSize, tabs: Int) -> NotchHeaderLayout {
            NotchHeaderLayout(canvasWidth: size.canvasSize.width, notchSize: notch, headerHeight: 32,
                              tabCount: tabs, shortcutCount: 1, titleWidth: 76)
        }
        XCTAssertFalse(header(.compact, tabs: 4).hasOverflow)
        XCTAssertFalse(header(.regular, tabs: 5).hasOverflow)
        XCTAssertFalse(header(.large, tabs: 5).hasOverflow)
        let compact = header(.compact, tabs: 5)
        XCTAssertTrue(compact.hasOverflow)
        XCTAssertEqual(compact.visibleTabCount, 3)
        XCTAssertEqual(compact.shortcutFrames.count, 1)
        XCTAssertLessThan(compact.gearFrame.maxX, compact.shortcutFrames[0].minX)
        for size in PanelSize.allCases {
            for tabs in 1...12 {
                let shown = header(size, tabs: tabs)
                XCTAssertGreaterThan(shown.visibleTabCount, 0, "\(size), \(tabs) tabs")
                XCTAssertEqual(shown.hasOverflow, shown.visibleTabCount < tabs, "\(size), \(tabs) tabs")
                XCTAssertGreaterThanOrEqual(header(.large, tabs: tabs).visibleTabCount, shown.visibleTabCount)
            }
        }
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

    func testATitleShowsWholeOrNotAtAll() throws {
        let notch = CGSize(width: 210, height: 32)
        let short = layout(tabs: 4, notch: notch, title: 30)
        XCTAssertEqual(short.titleFrame?.width, 30, "a short title shows whole")
        XCTAssertEqual(short.titleScale, 1)

        let long = layout(tabs: 4, notch: notch, title: 120)
        XCTAssertNil(long.titleFrame, "a title that can't fit whole is dropped, not clipped")
        XCTAssertEqual(long.titleScale, 1)

        let crowded = layout(tabs: 4, notch: notch, shortcuts: 3, title: 120)
        XCTAssertNil(crowded.titleFrame, "the title goes before anything collides")
        XCTAssertEqual(crowded.shortcutFrames.count, 3)
    }

    func testCompactCanvasDropsTitlesThatWouldClip() {
        // "Now Playing" (about 76pt) beside a 14"/16" MacBook Pro notch on the
        // Compact canvas, where the regular canvas fits it.
        let notch = CGSize(width: 185, height: 32)
        let compact = NotchHeaderLayout(canvasWidth: PanelSize.compact.canvasSize.width, notchSize: notch,
                                        headerHeight: 32, tabCount: 4, shortcutCount: 1, titleWidth: 76)
        XCTAssertNil(compact.titleFrame)
        XCTAssertNotNil(layout(tabs: 4, notch: notch, title: 76).titleFrame)
    }

    func testASlightlyLongTitleShrinksInsteadOfTruncating() throws {
        // "Claude Usage" in the 13pt title type, beside a 14"/16" MacBook Pro notch.
        let header = layout(tabs: 4, notch: CGSize(width: 185, height: 32), title: 87.4)
        let title = try XCTUnwrap(header.titleFrame)
        XCTAssertLessThan(header.titleScale, 1)
        XCTAssertGreaterThanOrEqual(header.titleScale, NotchHeaderLayout.Metrics().minTitleScale)
        XCTAssertGreaterThanOrEqual(title.width, 87.4 * header.titleScale - 0.5, "the shrunk title fits whole")

        XCTAssertEqual(layout(tabs: 4, notch: CGSize(width: 185, height: 32), title: 40).titleScale, 1,
                       "a title that fits keeps its full size")
    }
}
