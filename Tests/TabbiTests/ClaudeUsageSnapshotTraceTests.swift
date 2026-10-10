// The Usage tab isn't in the App Store build (`ModuleList` leaves it out).
#if !APPSTORE
import XCTest
import TabbiKitCore
@testable import Tabbi

/// A snapshot run must leave no trace, so rendering Claude Usage reads the
/// user's transcripts without saving a scan index in the data folder, and
/// never probes the CLI (a probe spends a sliver of the user's usage).
@MainActor
final class ClaudeUsageSnapshotTraceTests: XCTestCase {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClaudeUsageSnapshotTraceTests-\(UUID().uuidString)", isDirectory: true)
    private var storage: EditionStorage { EditionStorage(root: folder.appendingPathComponent("Data")) }
    nonisolated private var transcripts: URL { folder.appendingPathComponent("projects", isDirectory: true) }
    private var index: URL { ClaudeUsageLogScanner.indexURL(in: storage) }

    /// One transcript with a single assistant message from right now.
    override func setUpWithError() throws {
        let project = transcripts.appendingPathComponent("demo", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let now = ISO8601DateFormatter().string(from: Date())
        let line = #"{"type":"assistant","message":{"model":"claude-sonnet-4-5","id":"m1","usage":{"input_tokens":10,"output_tokens":20}},"timestamp":"\#(now)"}"#
        try Data((line + "\n").utf8).write(to: project.appendingPathComponent("session.jsonl"))
        addTeardownBlock { [folder] in try? FileManager.default.removeItem(at: folder) }
    }

    private func waitForStats(_ store: ClaudeUsageStore) async throws -> ClaudeLocalStats {
        for _ in 0..<200 {
            if let stats = store.stats { return stats }
            try await Task.sleep(for: .milliseconds(10))
        }
        return try XCTUnwrap(store.stats)
    }

    func testASnapshotRunShowsStatsWithoutSavingTheIndexOrProbing() async throws {
        let store = ClaudeUsageStore(storage: storage, runMode: RunMode(isSnapshot: true), transcripts: transcripts)
        let stats = try await waitForStats(store)
        XCTAssertEqual(stats.today.messages, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: index.path))

        store.refresh()
        XCTAssertFalse(store.isFetching)
    }

    func testALiveRunSavesTheIndex() async throws {
        let store = ClaudeUsageStore(storage: storage, runMode: .live, transcripts: transcripts)
        _ = try await waitForStats(store)
        XCTAssertTrue(FileManager.default.fileExists(atPath: index.path))
    }
}
#endif
