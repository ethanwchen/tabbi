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
        parse(bytes: Data(String(line).utf8))
    }

    /// Parses one transcript line given as UTF-8 bytes.
    ///
    /// The byte-level path matters: a week of transcripts can be close to a
    /// gigabyte, and most lines are user turns or tool results. Rejecting them
    /// with a raw byte search before any String or JSON work makes the first
    /// scan several times faster.
    public static func parse(bytes: some ContiguousBytes) -> ClaudeUsageRecord? {
        let decoded: Line? = bytes.withUnsafeBytes { buffer in
            guard contains(buffer, assistantMarker), contains(buffer, usageMarker),
                  let base = buffer.baseAddress
            else { return nil }
            let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: base), count: buffer.count, deallocator: .none)
            return try? decoder.decode(Line.self, from: data)
        }
        guard let line = decoded,
              line.type == "assistant",
              let message = line.message,
              let id = message.id,
              let model = message.model, !model.hasPrefix("<"),
              let usage = message.usage,
              let timestampText = line.timestamp,
              let timestamp = parseTimestamp(timestampText)
        else { return nil }

        return ClaudeUsageRecord(
            messageID: id,
            model: model,
            timestamp: timestamp,
            usage: ClaudeTokenUsage(
                input: usage.input ?? 0,
                output: usage.output ?? 0,
                cacheRead: usage.cacheRead ?? 0,
                cacheCreation: usage.cacheCreation ?? 0
            )
        )
    }

    /// Only the fields we need; JSONDecoder skips everything else (content
    /// blocks can be large) without materializing it.
    private struct Line: Decodable {
        struct Message: Decodable {
            var id: String?
            var model: String?
            var usage: Usage?
        }
        struct Usage: Decodable {
            var input: Int?
            var output: Int?
            var cacheRead: Int?
            var cacheCreation: Int?

            enum CodingKeys: String, CodingKey {
                case input = "input_tokens"
                case output = "output_tokens"
                case cacheRead = "cache_read_input_tokens"
                case cacheCreation = "cache_creation_input_tokens"
            }
        }
        var type: String?
        var message: Message?
        var timestamp: String?
    }

    private static let decoder = JSONDecoder()
    private static let assistantMarker = Array("\"assistant\"".utf8)
    private static let usageMarker = Array("\"usage\"".utf8)

    private static func contains(_ haystack: UnsafeRawBufferPointer, _ needle: [UInt8]) -> Bool {
        needle.withUnsafeBytes { pattern in
            guard let base = haystack.baseAddress, let pat = pattern.baseAddress else { return false }
            return memmem(base, haystack.count, pat, pattern.count) != nil
        }
    }

    private static func parseTimestamp(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date
        }
        return try? Date(text, strategy: Date.ISO8601FormatStyle())
    }
}
