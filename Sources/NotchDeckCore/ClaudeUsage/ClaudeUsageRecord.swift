import Foundation

/// Token counts of one or more assistant messages.
public struct ClaudeTokenUsage: Equatable, Sendable, Codable {
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheCreation: Int

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheCreation: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheCreation = cacheCreation
    }

    public static let zero = ClaudeTokenUsage()

    /// Every token the model processed, including cache reads and writes.
    public var total: Int { input + output + cacheRead + cacheCreation }

    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheCreation: lhs.cacheCreation + rhs.cacheCreation
        )
    }

    public static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }
}

/// One assistant message from a Claude Code session transcript
/// (`~/.claude/projects/**/*.jsonl`).
public struct ClaudeUsageRecord: Equatable, Sendable {
    /// API message id. Claude Code writes one line per content block, all
    /// sharing the message id and its usage, so this is the dedupe key.
    public var messageID: String
    public var model: String
    public var timestamp: Date
    public var usage: ClaudeTokenUsage

    public init(messageID: String, model: String, timestamp: Date, usage: ClaudeTokenUsage) {
        self.messageID = messageID
        self.model = model
        self.timestamp = timestamp
        self.usage = usage
    }

    /// Parses one transcript line. Returns nil for anything that isn't an
    /// assistant message with usage, including malformed JSON and the
    /// `<synthetic>` placeholder messages Claude Code writes for local errors.
    public static func parse(line: some StringProtocol) -> ClaudeUsageRecord? {
        // Cheap prefilter: most lines are user turns, tool results, or metadata.
        guard line.contains("\"assistant\""), line.contains("\"usage\"") else { return nil }
        guard let data = String(line).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              let id = message["id"] as? String,
              let model = message["model"] as? String, !model.hasPrefix("<"),
              let usage = message["usage"] as? [String: Any],
              let timestampText = object["timestamp"] as? String,
              let timestamp = parseTimestamp(timestampText)
        else { return nil }

        func count(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
        return ClaudeUsageRecord(
            messageID: id,
            model: model,
            timestamp: timestamp,
            usage: ClaudeTokenUsage(
                input: count("input_tokens"),
                output: count("output_tokens"),
                cacheRead: count("cache_read_input_tokens"),
                cacheCreation: count("cache_creation_input_tokens")
            )
        )
    }

    private static func parseTimestamp(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date
        }
        return try? Date(text, strategy: Date.ISO8601FormatStyle())
    }
}
