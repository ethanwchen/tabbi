import XCTest
@testable import TabbiKitCore

final class StreamingProcessTests: XCTestCase {
    private let sh = URL(fileURLWithPath: "/bin/sh")

    func testYieldsLinesIncludingUnterminatedLast() async throws {
        var lines: [String] = []
        for try await line in StreamingProcess.lines(executable: sh, arguments: ["-c", "printf 'a\\nb\\nc'"]) {
            lines.append(line)
        }
        XCTAssertEqual(lines, ["a", "b", "c"])
    }

    func testNonZeroExitThrowsWithStderr() async {
        do {
            for try await _ in StreamingProcess.lines(executable: sh, arguments: ["-c", "echo boom >&2; exit 3"]) {}
            XCTFail("expected failure")
        } catch let failure as ProcessFailure {
            XCTAssertEqual(failure.status, 3)
            XCTAssertEqual(failure.stderr, "boom")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    /// Output still being read when the process exits is never lost to the
    /// exit (the Claude CLI's last lines were, under load).
    func testOutputPrintedRightBeforeExitIsNeverDropped() async throws {
        let sh = sh
        let runs = try await withThrowingTaskGroup(of: [String].self) { group in
            for _ in 0..<100 {
                group.addTask {
                    var lines: [String] = []
                    for try await line in StreamingProcess.lines(executable: sh, arguments: ["-c", "seq 1 3000"]) {
                        lines.append(line)
                    }
                    return lines
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        let expected = (1...3000).map(String.init)
        XCTAssertEqual(runs.count, 100)
        XCTAssertEqual(runs.filter { $0 != expected }.map(\.count), [])
    }

    func testLineBufferSplitsAcrossChunks() {
        let buffer = LineBuffer()
        XCTAssertEqual(buffer.append(Data("ab".utf8)), [])
        XCTAssertEqual(buffer.append(Data("c\nde\n".utf8)), ["abc", "de"])
        XCTAssertNil(buffer.flush())
    }
}
