import Combine
import XCTest
import TabbiKitCore
@testable import Tabbi

@MainActor
final class WidgetStateWriterTests: XCTestCase {
    private var folder: URL!
    private var reloads = 0
    private let focus = CurrentValueSubject<ProvidedFocus?, Never>(nil)
    private let log = ActivityLog(repository: nil)

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("WidgetStateWriter-\(UUID())")
        reloads = 0
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeWriter() -> WidgetStateWriter {
        let pet = ClosetStore(storage: EditionStorage(edition: .current), runMode: .demo)
        return WidgetStateWriter(folder: folder, pet: pet, focus: focus.eraseToAnyPublisher(), activityLog: log) {
            [weak self] in self?.reloads += 1
        }
    }

    /// Lets the writer's coalesced write run.
    private func settle() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }

    private var shared: WidgetState? { WidgetStateFile(folder: folder).read() }

    func testWritesOnLaunchAndReloadsOnlyOnChanges() async throws {
        let writer = makeWriter()
        await settle()
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(shared?.focusMinutes, 0)
        XCTAssertNil(shared?.timer)
        XCTAssertFalse(writer.write(), "nothing changed")
        XCTAssertEqual(reloads, 1)
    }

    func testSessionStartAndEndReachTheWidgetAsOneWriteEach() async throws {
        let writer = makeWriter()
        await settle()
        let end = Date().addingTimeInterval(1500)
        focus.send(ProvidedFocus(source: .focus, phase: .focus, label: "Focus", clock: .countdown(endsAt: end),
                                 phaseLength: 1500))
        await settle()
        XCTAssertEqual(reloads, 2)
        XCTAssertEqual(shared?.timer?.label, "Focus")

        // The session ends: the clock goes idle and the minutes are logged.
        focus.send(nil)
        log.record(ActivityRecord(source: .focus, kind: .focusCompleted, start: Date().addingTimeInterval(-1500),
                                  end: Date(), quantity: 25, unit: .minutes))
        await settle()
        XCTAssertEqual(reloads, 3, "one write for both changes")
        XCTAssertNil(shared?.timer)
        XCTAssertEqual(shared?.focusMinutes, 25)
        XCTAssertEqual(shared?.streakDays, 1)
        XCTAssertEqual(shared?.lastFocusDay, PlannerDayKey(date: Date()))

        // A break logged afterwards changes nothing the widget shows.
        log.record(ActivityRecord(source: .focus, kind: .breakTaken, start: Date(), quantity: 5, unit: .minutes))
        await settle()
        XCTAssertEqual(reloads, 3)
        withExtendedLifetime(writer) {}
    }
}
