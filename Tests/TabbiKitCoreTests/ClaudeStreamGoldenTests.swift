import Foundation
import TabbiKitCore
import XCTest

/// Pins the `claude -p --output-format stream-json` parser and the Ask Claude
/// reducer to the golden fixture `shared/fixtures/claude-stream/stream-json.json`.
///
/// The Windows port reads the same lines and steps, runs them through its own
/// parser and reducer, and compares with the recorded results, so the two apps
/// read the CLI's output the same way.
/// Run with `TABBI_RECORD_FIXTURES=1` to rewrite it after an intended change.
final class ClaudeStreamGoldenTests: XCTestCase {
    func testStreamParsingMatchesGoldenFixture() throws {
        let url = ClaudeStreamGoldenFixture.folder.appendingPathComponent("stream-json.json")
        let current = ClaudeStreamGoldenFixture.current()
        if ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1" {
            try FileManager.default.createDirectory(at: ClaudeStreamGoldenFixture.folder, withIntermediateDirectories: true)
            try PetGoldenFixtures.encode(current).write(to: url)
            return
        }
        let stored = try JSONDecoder().decode(ClaudeStreamGoldenFixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(stored.lines.map(\.name), current.lines.map(\.name))
        for (old, new) in zip(stored.lines, current.lines) {
            XCTAssertEqual(old, new, "Line \(old.name) parses differently")
        }
        XCTAssertEqual(stored.conversations.map(\.name), current.conversations.map(\.name))
        for (old, new) in zip(stored.conversations, current.conversations) {
            XCTAssertEqual(old, new, "Conversation \(old.name) folds differently")
        }
        XCTAssertEqual(stored, current, "The stream parsing no longer matches \(url.lastPathComponent)")
    }

    /// The fixture's own inputs, replayed: a port that reads only the inputs
    /// from the file gets the recorded outputs.
    func testStoredInputsReplayToStoredOutputs() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1", "Recording")
        let url = ClaudeStreamGoldenFixture.folder.appendingPathComponent("stream-json.json")
        let stored = try JSONDecoder().decode(ClaudeStreamGoldenFixture.self, from: Data(contentsOf: url))
        for line in stored.lines {
            XCTAssertEqual(ClaudeStreamGoldenFixture.Event(ClaudeStreamEvent.parse(line: line.line)), line.event, line.name)
        }
        for conversation in stored.conversations {
            let inputs = conversation.steps.map(\.input)
            XCTAssertEqual(ClaudeStreamGoldenFixture.run(inputs), conversation.steps, conversation.name)
        }
    }
}

/// Raw CLI lines with the event each parses to, and Ask Claude exchanges as
/// a list of steps (begin a question, feed a line, the stream ends, stop) with
/// the chat after each step.
struct ClaudeStreamGoldenFixture: Codable, Equatable {
    static let schemaName = "tabbi.claude-stream.golden"

    static var folder: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/claude-stream")
    }

    /// A parsed event in a neutral form: `type` is the case name, and only
    /// the fields that case carries are present.
    struct Event: Codable, Equatable {
        struct Window: Codable, Equatable {
            var utilization: Double
            /// Seconds since 1970, as the CLI writes it.
            var resetsAt: Double?
        }

        var type: String
        var sessionID: String?
        var text: String?
        var isError: Bool?
        var status: String?
        var fiveHour: Window?
        var sevenDay: Window?

        init(type: String) { self.type = type }

        init(_ event: ClaudeStreamEvent) {
            switch event {
            case .sessionStarted(let id):
                self.init(type: "sessionStarted")
                sessionID = id
            case .rateLimit(let snapshot):
                self.init(type: "rateLimit")
                status = snapshot.status
                fiveHour = snapshot.fiveHour.map(Self.window)
                sevenDay = snapshot.sevenDay.map(Self.window)
            case .textDelta(let delta):
                self.init(type: "textDelta")
                text = delta
            case .assistantText(let message):
                self.init(type: "assistantText")
                text = message
            case .result(let result):
                self.init(type: "result")
                text = result.text
                sessionID = result.sessionID
                isError = result.isError
            case .other:
                self.init(type: "other")
            }
        }

        private static func window(_ window: ClaudeUsageWindow) -> Window {
            Window(utilization: window.utilization, resetsAt: window.resetsAt?.timeIntervalSince1970)
        }
    }

    struct Line: Codable, Equatable {
        var name: String
        var line: String
        var event: Event
    }

    /// What a step does: `begin` (with `prompt`), `line` (with `line`),
    /// `finish` (the stream ended), `cancel` (the user pressed stop), `retry`
    /// (take back the failed question) or `retryLostSession` (take it back
    /// only when the CLI no longer has the session, dropping the session).
    struct Input: Codable, Equatable {
        var action: String
        var prompt: String?
        var line: String?

        static func begin(_ prompt: String) -> Input { Input(action: "begin", prompt: prompt) }
        static func line(_ line: String) -> Input { Input(action: "line", line: line) }
        static let finish = Input(action: "finish")
        static let cancel = Input(action: "cancel")
        static let retry = Input(action: "retry")
        static let retryLostSession = Input(action: "retryLostSession")
    }

    struct Message: Codable, Equatable {
        var role: String
        var text: String
        var status: String
    }

    /// The chat after one step. `sent` is what `begin` returned (the trimmed
    /// prompt, absent when it refused) or the question a retry took back
    /// (absent when there was none); it is absent on other steps.
    struct Step: Codable, Equatable {
        var input: Input
        var sent: String?
        var messages: [Message]
        /// `idle`, `streaming` or `failed`.
        var phase: String
        /// The one-line reason shown when `phase` is `failed`.
        var failure: String?
        var sessionID: String?
    }

    struct Conversation: Codable, Equatable {
        var name: String
        var steps: [Step]
    }

    var schema = Self.schemaName
    var version = 1
    var lines: [Line]
    var conversations: [Conversation]

    static func current() -> ClaudeStreamGoldenFixture {
        ClaudeStreamGoldenFixture(
            lines: sampleLines.map { name, line in
                Line(name: name, line: line, event: Event(ClaudeStreamEvent.parse(line: line)))
            },
            conversations: sampleConversations.map { name, inputs in
                Conversation(name: name, steps: run(inputs))
            }
        )
    }

    /// Feeds `inputs` to a fresh conversation and records it after each one.
    static func run(_ inputs: [Input]) -> [Step] {
        var conversation = ClaudeAskConversation(chatID: UUID(), startedAt: Date(timeIntervalSince1970: 0))
        return inputs.map { input in
            var sent: String?
            switch input.action {
            case "begin": sent = conversation.begin(prompt: input.prompt ?? "")
            case "line": conversation.apply(ClaudeStreamEvent.parse(line: input.line ?? ""))
            case "finish": conversation.finish()
            case "cancel": conversation.cancel()
            case "retry": sent = conversation.takeRetryQuestion()?.text
            case "retryLostSession": sent = conversation.takeQuestionForLostSession()?.text
            default: XCTFail("Unknown action \(input.action)")
            }
            var failure: String?
            switch conversation.failure {
            case .noProvider, .notInstalled, .needsKey: failure = "needsSetup"
            case .process(let detail): failure = detail
            case nil: break
            }
            let phase: String
            switch conversation.phase {
            case .idle: phase = "idle"
            case .streaming: phase = "streaming"
            case .failed: phase = "failed"
            }
            return Step(
                input: input,
                sent: sent,
                messages: conversation.messages.map {
                    Message(role: $0.role.rawValue, text: $0.text, status: $0.status.rawValue)
                },
                phase: phase,
                failure: failure,
                sessionID: conversation.sessionID
            )
        }
    }

    // MARK: - Inputs

    /// Lines shaped like what `claude -p --output-format stream-json --verbose
    /// --include-partial-messages` prints, plus the malformed ones the parser
    /// must survive.
    static let sampleLines: [(String, String)] = [
        ("system-init",
         #"{"type":"system","subtype":"init","cwd":"/tmp","session_id":"7f1c2a90-0b6e-4c3f-9d1e-2a5b8c7d6e01","tools":["Read","Bash"],"model":"claude-sonnet-5-5","permissionMode":"default"}"#),
        ("system-init-without-session",
         #"{"type":"system","subtype":"init","cwd":"/tmp"}"#),
        ("system-init-session-not-a-string",
         #"{"type":"system","subtype":"init","session_id":5}"#),
        ("system-hook-is-other",
         #"{"type":"system","subtype":"hook_response","session_id":"s"}"#),
        ("rate-limit-both-windows",
         #"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","resetsAt":1790912400,"rateLimitType":"five_hour","unifiedWindows":{"five_hour":{"utilization":0.05,"resetsAt":1790912400},"seven_day":{"utilization":0.04,"resetsAt":1791460800}}},"session_id":"s"}"#),
        ("rate-limit-without-windows",
         #"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed"}}"#),
        ("rate-limit-over-limit-integer-utilization",
         #"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed_warning","unifiedWindows":{"five_hour":{"utilization":1},"seven_day":{"utilization":1.12,"resetsAt":1791460800.5}}}}"#),
        ("rate-limit-window-without-utilization",
         #"{"type":"rate_limit_event","rate_limit_info":{"unifiedWindows":{"five_hour":{"resetsAt":1790912400},"seven_day":{"utilization":"0.4"}}}}"#),
        ("rate-limit-without-info-is-other",
         #"{"type":"rate_limit_event","session_id":"s"}"#),
        ("text-delta",
         #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Spaced "}},"session_id":"s"}"#),
        ("text-delta-unicode-and-newlines",
         #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"résumé\n\n- café → \"quoted\""}}}"#),
        ("text-delta-empty",
         #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":""}}}"#),
        ("message-start-is-other",
         #"{"type":"stream_event","event":{"type":"message_start","message":{"id":"m","content":[]}}}"#),
        ("tool-input-delta-is-other",
         #"{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"path\":"}}}"#),
        ("assistant-joins-text-blocks",
         #"{"type":"assistant","message":{"id":"m","role":"assistant","content":[{"type":"text","text":"Hel"},{"type":"tool_use","id":"t","name":"Read","input":{}},{"type":"text","text":"lo"}]},"session_id":"s"}"#),
        ("assistant-thinking-then-text",
         #"{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"Let me think."},{"type":"text","text":"Done."}]}}"#),
        ("assistant-only-tool-use-is-other",
         #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t","name":"Bash","input":{"command":"ls"}}]}}"#),
        ("assistant-without-content-is-other",
         #"{"type":"assistant","message":{"role":"assistant"}}"#),
        ("user-tool-result-is-other",
         #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t","content":"ok"}]}}"#),
        ("result-success",
         #"{"type":"result","subtype":"success","is_error":false,"duration_ms":2310,"num_turns":1,"result":"Spaced repetition reviews cards just before you forget them.","session_id":"7f1c2a90-0b6e-4c3f-9d1e-2a5b8c7d6e01","total_cost_usd":0.0123}"#),
        ("result-success-empty-text",
         #"{"type":"result","subtype":"success","is_error":false,"result":"","session_id":"s1"}"#),
        ("result-error-subtype",
         #"{"type":"result","subtype":"error_max_turns","session_id":"s1"}"#),
        ("result-is-error-overrides-subtype",
         #"{"type":"result","subtype":"success","is_error":true,"result":"API Error: 529 Overloaded","session_id":"s1"}"#),
        ("result-without-subtype-or-flag",
         #"{"type":"result","result":"done"}"#),
        ("result-not-an-error-despite-subtype",
         #"{"type":"result","subtype":"error_during_execution","is_error":false,"result":"partial"}"#),
        ("padded-with-whitespace",
         "  {\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"padded\"}  "),
        ("empty-line", ""),
        ("plain-text", "Error: not logged in"),
        ("json-array", #"[{"type":"result"}]"#),
        ("json-string", #""result""#),
        ("no-type", #"{"no":"type"}"#),
        ("type-not-a-string", #"{"type":3}"#),
        ("unknown-type", #"{"type":"control_request","request":{}}"#),
        ("truncated-json", #"{"type":"result","subtype":"succ"#),
    ]

    static let sessionID = "7f1c2a90-0b6e-4c3f-9d1e-2a5b8c7d6e01"

    static func initLine(_ session: String) -> String {
        #"{"type":"system","subtype":"init","session_id":"\#(session)"}"#
    }

    static let rateLimitLine =
        #"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","unifiedWindows":{"five_hour":{"utilization":0.31,"resetsAt":1790912400}}}}"#

    static func deltaLine(_ text: String) -> String {
        #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"\#(text)"}}}"#
    }

    static func assistantLine(_ text: String) -> String {
        #"{"type":"assistant","message":{"content":[{"type":"text","text":"\#(text)"}]}}"#
    }

    static func resultLine(_ text: String?, session: String? = nil, error: Bool = false) -> String {
        var fields = [#""type":"result""#, #""subtype":"\#(error ? "error_during_execution" : "success")""#,
                      #""is_error":\#(error)"#]
        if let text { fields.append(#""result":"\#(text)""#) }
        if let session { fields.append(#""session_id":"\#(session)""#) }
        return "{" + fields.joined(separator: ",") + "}"
    }

    static let toolUseLine =
        #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t","name":"Read","input":{"file_path":"/tmp/notes.md"}}]}}"#
    static let toolResultLine =
        #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t","content":"notes"}]}}"#

    static let longError = String(repeating: "The model is overloaded right now, please try again later. ", count: 4)

    static let sampleConversations: [(String, [Input])] = [
        ("streamed-answer", [
            .begin("  What is spaced repetition?\n"),
            .line(initLine(sessionID)),
            .line(rateLimitLine),
            .line(deltaLine("Spaced ")),
            .line(deltaLine("repetition reviews ")),
            .line(deltaLine("cards just before you forget them.")),
            .line(assistantLine("Spaced repetition reviews cards just before you forget them.")),
            .line(resultLine("Spaced repetition reviews cards just before you forget them.", session: sessionID)),
        ]),
        ("tool-use-between-messages", [
            .begin("Summarize my notes"),
            .line(initLine(sessionID)),
            .line(deltaLine("Let me read them.")),
            .line(assistantLine("Let me read them.")),
            .line(toolUseLine),
            .line(toolResultLine),
            .line(deltaLine("They cover ")),
            .line(deltaLine("the Krebs cycle.")),
            .line(assistantLine("They cover the Krebs cycle.")),
            .line(resultLine("They cover the Krebs cycle.", session: sessionID)),
        ]),
        ("empty-result-keeps-streamed-text", [
            .begin("Hi"),
            .line(deltaLine("Hello")),
            .line(deltaLine(" there")),
            .line(resultLine("", session: "s2")),
        ]),
        ("error-result-summarized", [
            .begin("Hi"),
            .line(initLine("s3")),
            .line(deltaLine("Hel")),
            .line(resultLine(#"\n  \#(longError)\nSecond line"#, session: "s3", error: true)),
        ]),
        ("error-result-without-text", [
            .begin("Hi"),
            .line(resultLine(nil, error: true)),
        ]),
        ("stream-ends-without-result", [
            .begin("Hi"),
            .line(deltaLine("Partial answer")),
            .finish,
        ]),
        ("stream-ends-with-nothing", [
            .begin("Hi"),
            .line(initLine("s4")),
            .finish,
        ]),
        ("user-stops", [
            .begin("Write a long essay"),
            .line(assistantLine("First part.")),
            .line(deltaLine("Second")),
            .cancel,
            .line(deltaLine(" ignored")),
            .finish,
        ]),
        ("ignored-outside-an-exchange", [
            .line(initLine("early")),
            .line(deltaLine("early")),
            .finish,
            .cancel,
            .begin("   "),
            .begin("Hi"),
            .begin("Again"),
            .line(resultLine("Hello", session: "s5")),
            .line(resultLine("Late", session: "late")),
        ]),
        ("follow-up-keeps-session", [
            .begin("First"),
            .line(initLine("s6")),
            .line(resultLine("One", session: "s6")),
            .begin("Second"),
            .line(initLine("s6")),
            .line(resultLine("Two", session: "s7")),
        ]),
        ("new-question-after-failure", [
            .begin("First"),
            .line(resultLine("No conversation found with session ID: s8", session: "s8", error: true)),
            .begin("Second"),
            .line(resultLine("Answer")),
        ]),
        ("retry-failed-question", [
            .retry,
            .begin("First"),
            .line(resultLine("One", session: "s9")),
            .retry,
            .begin("Second"),
            .line(resultLine("API Error: 529 Overloaded", session: "s9", error: true)),
            .retryLostSession,
            .retry,
            .retry,
            .begin("Second"),
            .line(resultLine("Two", session: "s9")),
        ]),
        ("retry-lost-session", [
            .begin("Continue the quiz"),
            .line(initLine("gone")),
            .line(resultLine("No conversation found with session ID: gone", session: "gone", error: true)),
            .retryLostSession,
            .begin("Continue the quiz"),
            .line(initLine("s10")),
            .line(resultLine("Question 4: what does ATP stand for?", session: "s10")),
        ]),
    ]
}
