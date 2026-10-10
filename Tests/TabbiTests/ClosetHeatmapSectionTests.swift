import Combine
import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// The Closet opens on its study chart, which reads the same focused
/// minutes per day as the streak and follows new study as it is logged.
@MainActor
final class ClosetHeatmapSectionTests: XCTestCase {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("heatmap-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testTheClosetOpensOnTheChart() {
        let store = ClosetStore(storage: EditionStorage(root: folder), runMode: .live)
        XCTAssertEqual(ClosetSection.allCases.first, .activity, "the chart is the first section chip")
        XCTAssertEqual(store.section, .activity)
    }

    func testTodaysSquareFollowsNewStudy() {
        let store = ClosetStore(storage: EditionStorage(root: folder), runMode: .live)
        let activity = PassthroughSubject<ActivityRecord, Never>()
        store.follow(activity: activity.eraseToAnyPublisher())
        func today() -> StudyHeatmap.Day? {
            StudyHeatmap(minutesByDay: store.milestones.minutesByDay, weeks: 1, today: .now).weeks.last?
                .days.compactMap { $0 }.first(where: \.isToday)
        }
        XCTAssertEqual(today()?.level, 0)

        let start = Calendar.current.startOfDay(for: .now)
        activity.send(ActivityRecord(source: .focus, kind: .focusCompleted, start: start,
                                     end: start.addingTimeInterval(50 * 60), quantity: 50, unit: .minutes))
        XCTAssertEqual(today()?.minutes, 50)
        XCTAssertEqual(today()?.level, 3, "50 minutes is a real session's shade")
    }

    func testTheDemoChartShowsEveryShade() {
        let store = ClosetStore(storage: EditionStorage(root: folder), runMode: .demo)
        let heatmap = StudyHeatmap(minutesByDay: store.milestones.minutesByDay, weeks: 20, today: .now)
        let levels = Set(heatmap.weeks.flatMap(\.days).compactMap { $0?.level })
        XCTAssertEqual(levels, Set(0..<StudyHeatmap.levelCount))
        XCTAssertGreaterThan(heatmap.lastThirtyDaysMinutes, 0)
        XCTAssertTrue(store.streak.isActive, "the demo shows a streak going")
    }
}
