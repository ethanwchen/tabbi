import Darwin
import XCTest
@testable import TabbiKitCore

/// Regression test for the launch memory blow-up: scanning a week of
/// transcripts (about a gigabyte on a heavy user's Mac) once grew the app's
/// footprint by as much as it read. Scans a synthetic corpus of a few hundred
/// megabytes and checks both the totals and the peak footprint growth.
final class ClaudeUsageScanMemoryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("scan-memory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testLargeCorpusScanKeepsPeakMemoryBounded() async throws {
        let fileCount = 40
        let messagesPerFile = 400
        let corpusBytes = try writeCorpus(fileCount: fileCount, messagesPerFile: messagesPerFile)
        XCTAssertGreaterThan(corpusBytes, 250 << 20, "the corpus must dwarf the memory bound")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = try Date("2026-10-01T23:00:00Z", strategy: Date.ISO8601FormatStyle())
        let scanner = ClaudeUsageLogScanner(root: root, indexURL: root.appendingPathComponent("index.json"))

        let sampler = FootprintSampler()
        let stats = await scanner.scan(now: now, calendar: calendar)
        let growth = sampler.stop()

        // Every message is written twice (two content blocks) and counted once.
        XCTAssertEqual(stats.lastSevenDays.messages, fileCount * messagesPerFile)
        XCTAssertEqual(stats.today.messages, fileCount * messagesPerFile / 2)
        XCTAssertEqual(stats.lastSevenDays.tokens.total, fileCount * messagesPerFile * 1_110)
        XCTAssertLessThan(growth, 60 << 20, "peak footprint grew by \(growth >> 20) MB scanning \(corpusBytes >> 20) MB")
    }

    /// Mostly large tool-result lines (which a heavy session is made of),
    /// one multi-megabyte line per file, and assistant lines with usage
    /// split between today and earlier this week. Returns the corpus size.
    private func writeCorpus(fileCount: Int, messagesPerFile: Int) throws -> Int {
        let toolResult = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":""#
            + String(repeating: "lorem ipsum ", count: 1_400) + #""}]},"timestamp":"2026-10-01T10:00:00Z"}"#
        let huge = #"{"type":"user","message":{"content":""# + String(repeating: "A", count: 3 << 20) + #""}}"#
        let content = String(repeating: "x", count: 1_500)
        var total = 0
        for file in 0..<fileCount {
            let url = root.appendingPathComponent("session-\(file).jsonl")
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try autoreleasepool {
                try handle.write(contentsOf: Data((huge + "\n").utf8))
                for message in 0..<messagesPerFile {
                    let day = message.isMultiple(of: 2) ? "2026-10-01" : "2026-09-28"
                    let line = #"{"type":"assistant","message":{"model":"claude-opus-4-5","id":"msg_\#(file)_\#(message)","content":[{"type":"text","text":"\#(content)"}],"usage":{"input_tokens":10,"output_tokens":100,"cache_read_input_tokens":1000,"cache_creation_input_tokens":0}},"timestamp":"\#(day)T09:00:00Z"}"#
                    try handle.write(contentsOf: Data((line + "\n" + line + "\n" + toolResult + "\n").utf8))
                }
            }
            total += Int(try handle.offset())
        }
        return total
    }
}
