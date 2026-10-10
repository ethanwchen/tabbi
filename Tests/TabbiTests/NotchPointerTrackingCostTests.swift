import XCTest
import TabbiKitCore
import TabbiKit
@testable import Tabbi

/// The notch follows the pointer with a global mouse monitor, so its hit
/// rect (`NotchViewModel.size`) is read on every mouse move anywhere on
/// screen, all day. Reading it must stay cheap, and the wing width it
/// remembers must follow the preview.
@MainActor
final class NotchPointerTrackingCostTests: XCTestCase {
    private let notch = CGSize(width: 185, height: 32)

    private func makeModel() -> NotchViewModel {
        let geometry = NotchGeometry(notchSize: notch, hasHardwareNotch: true,
                                     screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117), centerX: 864)
        return NotchViewModel(geometry: geometry, layout: ModuleLayout(catalog: ModuleList.catalog))
    }

    private func closedWidth(with preview: TickerItem?) -> CGFloat {
        notch.width + 2 * Theme.Layout.closedTopRadius
            + (preview.map { NotchPreviewLayout.wingWidth(for: $0) * 2 } ?? 0)
    }

    func testClosedSizeFollowsEveryPreviewChange() {
        let model = makeModel()
        XCTAssertEqual(model.size.width, closedWidth(with: nil))

        let meeting = TickerItem.meeting(TickerMeeting(title: "Design standup", timing: .startsIn(minutes: 4), canJoin: true))
        let tasks = TickerItem.tasks(remaining: 3)
        for preview in [meeting, tasks, meeting, nil] {
            model.preview = preview
            XCTAssertEqual(model.size.width, closedWidth(with: preview))
        }
    }

    func testReadingTheSizeWithAPreviewCostsNoMoreThanWithout() {
        let plain = makeModel()
        let previewed = makeModel()
        previewed.preview = .meeting(TickerMeeting(title: "Quarterly planning", timing: .startsIn(minutes: 4), canJoin: true))
        // Measuring the preview's text made each read several times slower
        // than a read with no preview. Comparing the two, at their best of
        // several interleaved rounds, keeps the check steady on a busy machine.
        func fastest(_ model: NotchViewModel) -> TimeInterval {
            let start = Date()
            var total: CGFloat = 0
            for _ in 0..<2_000 { total += model.size.width }
            XCTAssertGreaterThan(total, 0)
            return Date().timeIntervalSince(start)
        }
        var plainBest = TimeInterval.infinity
        var previewedBest = TimeInterval.infinity
        for _ in 0..<7 {
            plainBest = min(plainBest, fastest(plain))
            previewedBest = min(previewedBest, fastest(previewed))
        }
        XCTAssertLessThan(previewedBest, plainBest * 2)
    }
}
