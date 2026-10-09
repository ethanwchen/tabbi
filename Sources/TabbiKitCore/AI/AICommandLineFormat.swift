import Foundation

/// How Tabbi runs each command line tool and reads its output, kept pure so
/// the flags and decoders are unit tested.
///
/// Every tool runs non-interactively in a fresh temporary folder (so no
/// project instructions are picked up) with its tools turned off or
/// read-only, answers in JSON lines, and exits.
public enum AICommandLineFormat {
    /// The arguments and stdin for one run.
    public struct Invocation: Hashable, Sendable {
        public var arguments: [String]
        public var input: Data?

        public init(arguments: [String], input: Data? = nil) {
            self.arguments = arguments
            self.input = input
        }
    }

    /// The run for `request`. `imagePaths` are the last message's images,
    /// already written to files under the working folder and given relative
    /// to it (Codex and Gemini CLI take images as files and Gemini only
    /// reads files inside its folder; Claude Code reads them from stdin).
    public static func invocation(for provider: AIProviderID, _ request: AIRequest, imagePaths: [String] = []) throws -> Invocation {
        let model = request.resolvedModel(for: provider)
        let resume = request.resumeSessionID.flatMap { $0.isEmpty ? nil : $0 }
        switch provider {
        case .claudeCLI:
            var arguments = [
                "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                "--include-partial-messages",
                // No built-in tools and none of the user's MCP servers: it
                // can only answer in text.
                "--tools", "", "--strict-mcp-config",
            ]
            if !model.isEmpty { arguments += ["--model", model] }
            if let system = request.system, !system.isEmpty { arguments += ["--system-prompt", system] }
            if let resume { arguments += ["--resume", resume] }
            if let schema = request.responseSchema, !schema.isEmpty { arguments += ["--json-schema", schema] }
            let last = request.messages.last
            let input = try claudeInputLine(prompt: prompt(for: request), images: last?.images ?? [])
            return Invocation(arguments: arguments, input: input)

        case .codexCLI:
            var arguments = ["exec", "--json", "--skip-git-repo-check", "--sandbox", "read-only"]
            if !model.isEmpty { arguments += ["--model", model] }
            for path in imagePaths { arguments += ["--image", path] }
            if let resume { arguments += ["resume", resume] }
            // After `--`, a question that starts with `-` is never a flag.
            return Invocation(arguments: arguments + ["--", promptWithSystem(for: request)])

        case .geminiCLI:
            var arguments = ["--output-format", "stream-json"]
            if !model.isEmpty { arguments += ["--model", model] }
            if let resume { arguments += ["--resume", resume] }
            // `@file` is how Gemini CLI attaches a file from its folder.
            let references = imagePaths.map { "@\($0)" }.joined(separator: " ")
            let text = promptWithSystem(for: request)
            // One `--prompt=` argument, so text that starts with `-` stays text.
            return Invocation(arguments: arguments + ["--prompt=\(references.isEmpty ? text : "\(references) \(text)")"])

        case .anthropic, .openAI, .gemini, .ollama:
            preconditionFailure("\(provider) is not a command line tool")
        }
    }

    /// The question as one line of `--input-format stream-json` input: a
    /// user message whose content is each image (base64 PNG) followed by
    /// the text, the documented way to give the CLI an image. It goes to the
    /// local process's stdin, so the image never touches a file the CLI
    /// could be pointed at, and nothing is sent anywhere but through it.
    public static func claudeInputLine(prompt: String, images: [Data]) throws -> Data {
        let content = images.map { InputMessage.Block.image(base64: $0.base64EncodedString()) }
            + [.text(prompt)]
        let message = InputMessage(message: .init(content: content))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(message) + Data("\n".utf8)
    }

    /// `{"type":"user","message":{"role":"user","content":[...]}}`
    private struct InputMessage: Encodable {
        struct Message: Encodable {
            var role = "user"
            var content: [Block]
        }

        struct Block: Encodable {
            struct Source: Encodable {
                var type = "base64"
                var media_type = ClaudeAskAttachment.mediaType
                var data: String
            }

            var type: String
            var text: String?
            var source: Source?

            static func text(_ text: String) -> Block { Block(type: "text", text: text) }
            static func image(base64: String) -> Block { Block(type: "image", source: Source(data: base64)) }
        }

        var type = "user"
        var message: Message
    }

    /// The text to send: the last message, or, for a new run of a chat that
    /// has history but no session to resume, the whole chat written out.
    public static func prompt(for request: AIRequest) -> String {
        guard let last = request.messages.last else { return "" }
        let earlier = request.messages.dropLast()
        guard request.resumeSessionID == nil, !earlier.isEmpty else { return last.text }
        let transcript = earlier.map { message in
            "\(message.role == .user ? "User" : "Assistant"): \(message.text)"
        }.joined(separator: "\n\n")
        return "The conversation so far:\n\n\(transcript)\n\nNow answer this:\n\n\(last.text)"
    }

    /// `prompt(for:)` with the instructions in front, for tools without a
    /// system prompt flag. A resumed session already has them.
    static func promptWithSystem(for request: AIRequest) -> String {
        let text = prompt(for: request)
        guard request.resumeSessionID == nil, let system = request.system, !system.isEmpty else { return text }
        return "\(system)\n\n\(text)"
    }

    /// The events in one line of `provider`'s JSON output. Unknown lines
    /// decode to nothing; a reported failure throws.
    public static func events(fromLine line: String, provider: AIProviderID) throws -> [AIStreamEvent] {
        switch provider {
        case .claudeCLI: return try claudeEvents(ClaudeStreamEvent.parse(line: line))
        case .codexCLI: return try codexEvents(json(line))
        case .geminiCLI: return try geminiEvents(json(line))
        case .anthropic, .openAI, .gemini, .ollama: return []
        }
    }

    private static func json(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func claudeEvents(_ event: ClaudeStreamEvent) throws -> [AIStreamEvent] {
        switch event {
        case .sessionStarted(let id): return id.map { [.sessionStarted($0)] } ?? []
        case .textDelta(let text): return [.textDelta(text)]
        case .result(let result):
            if result.isError { throw AIProviderError.service(detail: result.text ?? "Claude Code could not answer.") }
            return [.finished(text: result.text)]
        case .rateLimit, .assistantText, .other: return []
        }
    }

    /// `codex exec --json`: `thread.started`, then each finished item
    /// (`agent_message` is the answer), then `turn.completed` or
    /// `turn.failed`.
    private static func codexEvents(_ object: [String: Any]?) throws -> [AIStreamEvent] {
        guard let object, let type = object["type"] as? String else { return [] }
        switch type {
        case "thread.started":
            return (object["thread_id"] as? String).map { [.sessionStarted($0)] } ?? []
        case "item.completed":
            guard let item = object["item"] as? [String: Any],
                  ["agent_message", "assistant_message"].contains((item["type"] ?? item["item_type"]) as? String),
                  let text = item["text"] as? String, !text.isEmpty
            else { return [] }
            return [.textDelta(text)]
        case "turn.completed":
            return [.finished(text: nil)]
        case "turn.failed":
            let error = object["error"] as? [String: Any]
            throw AIProviderError.service(detail: (error?["message"] as? String) ?? "Codex could not answer.")
        case "error":
            throw AIProviderError.service(detail: (object["message"] as? String) ?? "Codex could not answer.")
        default:
            return []
        }
    }

    /// `gemini --output-format stream-json`: `init`, assistant `message`
    /// chunks, then `result`.
    private static func geminiEvents(_ object: [String: Any]?) throws -> [AIStreamEvent] {
        guard let object, let type = object["type"] as? String else { return [] }
        switch type {
        case "init":
            return (object["session_id"] as? String).map { [.sessionStarted($0)] } ?? []
        case "message":
            guard object["role"] as? String == "assistant",
                  let text = object["content"] as? String, !text.isEmpty
            else { return [] }
            return [.textDelta(text)]
        case "result":
            if let status = object["status"] as? String, status != "success" {
                let error = object["error"] as? [String: Any]
                throw AIProviderError.service(detail: (error?["message"] as? String) ?? "Gemini CLI could not answer.")
            }
            return [.finished(text: nil)]
        case "error":
            guard (object["severity"] as? String) != "warning" else { return [] }
            throw AIProviderError.service(detail: (object["message"] as? String) ?? "Gemini CLI could not answer.")
        default:
            return []
        }
    }
}
