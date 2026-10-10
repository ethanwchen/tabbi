import XCTest
import TabbiKitCore
import TabbiKit
@testable import Tabbi

/// The panel size from Settings sizes the open notch for every tab, and a
/// tab's larger canvas (Ask Claude's chat view) still grows past it. Large
/// also draws the panels larger.
@MainActor
final class PanelSizeTests: XCTestCase {
    private func makeModel(_ size: PanelSize) -> NotchViewModel {
        let geometry = NotchGeometry(notchSize: CGSize(width: 185, height: 32), hasHardwareNotch: true,
                                     screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117), centerX: 864)
        let model = NotchViewModel(geometry: geometry, layout: ModuleLayout(catalog: ModuleList.catalog))
        model.panelSize = size
        return model
    }

    func testEachSizeOpensToItsCanvas() {
        for size in PanelSize.allCases {
            let model = makeModel(size)
            model.open()
            XCTAssertEqual(model.size, size.canvasSize, size.title)
        }
    }

    func testSizesGrowFromCompactToLargeAndRegularIsTheClassicCanvas() {
        let sizes = PanelSize.allCases.map(\.canvasSize)
        XCTAssertEqual(sizes.map(\.width), sizes.map(\.width).sorted())
        XCTAssertEqual(sizes.map(\.height), sizes.map(\.height).sorted())
        XCTAssertEqual(PanelSize.default, .regular)
        XCTAssertEqual(PanelSize.regular.canvasSize, Theme.Layout.expandedSize)
    }

    func testOnlyLargeMagnifiesThePanels() {
        XCTAssertEqual(PanelSize.regular.contentScale, 1)
        XCTAssertEqual(PanelSize.compact.contentScale, 1)
        XCTAssertGreaterThan(PanelSize.large.contentScale, 1)
    }

    /// Large draws every panel larger, but lays it out in no less room than
    /// Regular, so nothing that fits at Regular gets cut off at Large.
    func testLargeLaysPanelsOutInAtLeastRegularsRoom() {
        func room(_ size: PanelSize) -> CGSize {
            let model = makeModel(size)
            model.open()
            let header = max(model.geometry.notchSize.height, 32)
            let inset = (Theme.Layout.contentInset + Theme.Layout.openTopRadius) * 2
            let scale = size.contentScale
            return CGSize(width: (model.size.width - inset) / scale,
                          height: (model.size.height - header - Theme.Spacing.s - Theme.Spacing.l) / scale)
        }
        let regular = room(.regular)
        let large = room(.large)
        XCTAssertGreaterThanOrEqual(large.width, regular.width)
        XCTAssertGreaterThanOrEqual(large.height, regular.height)
    }

    func testALargerCanvasRequestStillGrowsACompactPanel() {
        let model = makeModel(.compact)
        model.open()
        model.requestOpenSize(ClaudeAskPanel.largeSize)
        XCTAssertGreaterThan(model.size.width, PanelSize.compact.canvasSize.width)
        model.requestOpenSize(nil)
        XCTAssertEqual(model.size, PanelSize.compact.canvasSize)
    }
}
