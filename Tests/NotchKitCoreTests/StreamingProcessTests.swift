import XCTest
@testable import NotchKitCore

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

    func testLineBufferSplitsAcrossChunks() {
        let buffer = LineBuffer()
        XCTAssertEqual(buffer.append(Data("ab".utf8)), [])
        XCTAssertEqual(buffer.append(Data("c\nde\n".utf8)), ["abc", "de"])
        XCTAssertNil(buffer.flush())
    }
}
