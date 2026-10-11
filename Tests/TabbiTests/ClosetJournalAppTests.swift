import Combine
import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// A long focus block that runs out brings the pet back from its adventure:
/// a line goes into the saved journal and out through the gift integration
/// point (`adventureReturns`). Demo runs show a journal, snapshots save none.
@MainActor
final class ClosetJournalAppTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() async throws {
        cancellables = []
        try? FileManager.default.removeItem(at: root)
    }

    /// Runs a 25 minute block that ended a moment ago through the store.
    private func finishBlock(on store: ClosetStore) {
        let end = Date().addingTimeInterval(-1)
        let focus = PassthroughSubject<ProvidedFocus?, Never>()
        store.follow(focus: focus.eraseToAnyPublisher())
        focus.send(ProvidedFocus(source: .focus, phase: .focus, clock: .countdown(endsAt: end),
                                 phaseLength: 25 * 60))
        focus.send(ProvidedFocus(source: .focus, phase: .rest, clock: .countdown(endsAt: end.addingTimeInterval(300)),
                                 phaseLength: 300, completedFocusCount: 1))
    }

    func testAFinishedBlockWritesTheJournalAndSendsTheReturn() throws {
        let storage = EditionStorage(root: root)
        let store = ClosetStore(storage: storage, runMode: .live)
        store.reduceMotion = { false }
        XCTAssertNil(store.latestAdventure, "no adventures yet")
        var returns: [PetJournal.Entry] = []
        store.adventureReturns.sink { returns.append($0) }.store(in: &cancellables)

        finishBlock(on: store)

        XCTAssertEqual(returns.count, 1)
        XCTAssertEqual(store.journal.latest, returns.first)
        let line = try XCTUnwrap(store.latestAdventure)
        XCTAssertTrue(line.hasPrefix(store.profile.name + " "), line)
        let saved = try XCTUnwrap(PetJournal.load(from: ClosetStore.journalURL(in: storage)))
        XCTAssertEqual(saved, store.journal)
        XCTAssertEqual(ClosetStore(storage: storage, runMode: .live).journal, saved, "kept across launches")
    }

    func testUnderReduceMotionThePetStaysHomeAndWritesNothing() {
        let store = ClosetStore(storage: EditionStorage(root: root), runMode: .live)
        store.reduceMotion = { true }
        var returns = 0
        store.adventureReturns.sink { _ in returns += 1 }.store(in: &cancellables)
        finishBlock(on: store)
        XCTAssertEqual(returns, 0)
        XCTAssertTrue(store.journal.entries.isEmpty)
    }

    func testAnUnreadableJournalIsNeverOverwritten() throws {
        let storage = EditionStorage(root: root)
        let url = ClosetStore.journalURL(in: storage)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let store = ClosetStore(storage: storage, runMode: .live)
        store.reduceMotion = { false }
        finishBlock(on: store)
        XCTAssertEqual(store.journal.entries.count, 1, "the pet still tells about it this launch")
        XCTAssertEqual(try Data(contentsOf: url), Data("not json".utf8))
    }

    func testDemoShowsAJournalAndSnapshotsSaveNone() {
        XCTAssertNotNil(ClosetStore(storage: EditionStorage(root: root), runMode: .demo).latestAdventure)
        let snapshot = ClosetStore(storage: EditionStorage(root: root), runMode: RunMode(isDemo: false, isSnapshot: true))
        snapshot.reduceMotion = { false }
        finishBlock(on: snapshot)
        XCTAssertEqual(snapshot.journal.entries.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ClosetStore.journalURL(in: EditionStorage(root: root)).path))
    }
}
