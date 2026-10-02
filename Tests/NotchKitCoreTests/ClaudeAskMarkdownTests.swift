import XCTest
import NotchKitCore

final class ClaudeAskMarkdownTests: XCTestCase {
    func testLineBreaksSurviveParsing() {
        let text = String(ClaudeAskMarkdown.attributed("First line\n\nSecond line").characters)
        XCTAssertEqual(text, "First line\n\nSecond line")
    }

    func testBulletsBecomeDotsAndKeepIndent() {
        let text = String(ClaudeAskMarkdown.attributed("Options:\n- one\n* two\n  + nested").characters)
        XCTAssertEqual(text, "Options:\n• one\n• two\n  • nested")
    }

    func testBoldAndCodeAreStyled() {
        let attributed = ClaudeAskMarkdown.attributed("Use **this** or `that`")
        XCTAssertEqual(String(attributed.characters), "Use this or that")
        let intents = attributed.runs.compactMap { run -> (String, InlinePresentationIntent)? in
            guard let intent = run.inlinePresentationIntent else { return nil }
            return (String(attributed[run.range].characters), intent)
        }
        XCTAssertTrue(intents.contains { $0.0 == "this" && $0.1.contains(.stronglyEmphasized) })
        XCTAssertTrue(intents.contains { $0.0 == "that" && $0.1.contains(.code) })
    }

    func testHeadingsBecomeBoldLines() {
        let attributed = ClaudeAskMarkdown.attributed("## Summary\nBody")
        XCTAssertEqual(String(attributed.characters), "Summary\nBody")
        let firstRun = attributed.runs.first
        XCTAssertEqual(firstRun?.inlinePresentationIntent, .stronglyEmphasized)
    }

    func testHashtagWithoutSpaceIsNotAHeading() {
        XCTAssertEqual(String(ClaudeAskMarkdown.attributed("#hashtag").characters), "#hashtag")
    }

    func testCodeFencesAreDroppedAndLinesBecomeCode() {
        let attributed = ClaudeAskMarkdown.attributed("Run:\n```sh\nswift build\n```\nDone")
        XCTAssertEqual(String(attributed.characters), "Run:\nswift build\nDone")
        let code = attributed.runs.first { String(attributed[$0.range].characters) == "swift build" }
        XCTAssertEqual(code?.inlinePresentationIntent, .code)
    }

    func testUnfinishedMarkdownWhileStreamingStillRenders() {
        let text = String(ClaudeAskMarkdown.attributed("Partial **bold").characters)
        XCTAssertTrue(text.hasPrefix("Partial"))
    }
}
