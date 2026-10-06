import XCTest
import TabbiKitCore

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

    // MARK: - Blocks

    func testProseWithoutFencesIsOneTextBlock() {
        XCTAssertEqual(ClaudeAskMarkdown.blocks("One\n\n- two"), [.text("One\n\n- two")])
    }

    func testFencedCodeSplitsProseAndKeepsLanguageAndIndentation() {
        let blocks = ClaudeAskMarkdown.blocks("Try this:\n\n```swift\nfunc a() {\n    b()\n}\n```\n\nThat's it.")
        XCTAssertEqual(blocks, [
            .text("Try this:"),
            .code(language: "swift", code: "func a() {\n    b()\n}", isClosed: true),
            .text("That's it."),
        ])
    }

    func testFenceWithoutLanguageAndExtraInfo() {
        XCTAssertEqual(ClaudeAskMarkdown.blocks("```\nls\n```"), [.code(language: nil, code: "ls", isClosed: true)])
        XCTAssertEqual(ClaudeAskMarkdown.blocks("```sh title=x\nls\n```"),
                       [.code(language: "sh", code: "ls", isClosed: true)])
    }

    func testUnclosedFenceWhileStreamingRunsToTheEnd() {
        XCTAssertEqual(ClaudeAskMarkdown.blocks("Run:\n```sh\nswift build\nswift te"), [
            .text("Run:"),
            .code(language: "sh", code: "swift build\nswift te", isClosed: false),
        ])
        XCTAssertEqual(ClaudeAskMarkdown.blocks("Run:\n```"), [.text("Run:"), .code(language: nil, code: "", isClosed: false)])
    }

    func testIndentedFenceInAListLosesOnlyItsOwnIndent() {
        let blocks = ClaudeAskMarkdown.blocks("- Step:\n  ```\n  if x {\n      y\n  }\n  ```")
        XCTAssertEqual(blocks, [.text("- Step:"), .code(language: nil, code: "if x {\n    y\n}", isClosed: true)])
    }

    func testBlankLinesInsideCodeAreKept() {
        XCTAssertEqual(ClaudeAskMarkdown.blocks("```\na\n\nb\n```"), [.code(language: nil, code: "a\n\nb", isClosed: true)])
    }

    func testEmptyAnswerHasNoBlocks() {
        XCTAssertEqual(ClaudeAskMarkdown.blocks(""), [])
        XCTAssertEqual(ClaudeAskMarkdown.blocks("\n\n"), [])
    }
}
