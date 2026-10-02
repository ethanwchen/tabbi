import Foundation

/// One window of the Claude subscription usage limit (5-hour or weekly).
public struct ClaudeUsageWindow: Equatable, Sendable {
    /// 0.0 ... 1.0 (can exceed 1.0 when over the limit).
    public var utilization: Double
    public var resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

/// Live usage reported by the `claude` CLI in its `rate_limit_event`.
public struct ClaudeRateLimitSnapshot: Equatable, Sendable {
    public var status: String?
    public var fiveHour: ClaudeUsageWindow?
    public var sevenDay: ClaudeUsageWindow?

    public init(status: String?, fiveHour: ClaudeUsageWindow?, sevenDay: ClaudeUsageWindow?) {
        self.status = status
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }
}

public struct ClaudeResult: Equatable, Sendable {
    public var text: String?
    public var sessionID: String?
    public var isError: Bool

    public init(text: String?, sessionID: String?, isError: Bool) {
        self.text = text
        self.sessionID = sessionID
        self.isError = isError
    }
}

/// A parsed line of `claude -p --output-format stream-json --verbose` output.
public enum ClaudeStreamEvent: Equatable, Sendable {
    /// `system/init`; carries the session id used for `--resume`.
    case sessionStarted(sessionID: String?)
    /// Usage-limit utilization, emitted on every call.
    case rateLimit(ClaudeRateLimitSnapshot)
    /// Incremental text (requires `--include-partial-messages`).
    case textDelta(String)
    /// The concatenated text blocks of one complete assistant message.
    case assistantText(String)
    /// Final event of a run.
    case result(ClaudeResult)
    /// Anything else (tool use, hooks, unparseable lines).
    case other

    /// Parses one JSONL line. Never throws: unknown shapes become `.other`.
    public static func parse(line: String) -> ClaudeStreamEvent {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else { return .other }

        switch type {
        case "system":
            guard object["subtype"] as? String == "init" else { return .other }
            return .sessionStarted(sessionID: object["session_id"] as? String)

        case "rate_limit_event":
            guard let info = object["rate_limit_info"] as? [String: Any] else { return .other }
            let windows = info["unifiedWindows"] as? [String: Any]
            return .rateLimit(ClaudeRateLimitSnapshot(
                status: info["status"] as? String,
                fiveHour: window(windows?["five_hour"]),
                sevenDay: window(windows?["seven_day"])
            ))

        case "stream_event":
            guard let event = object["event"] as? [String: Any],
                  event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String
            else { return .other }
            return .textDelta(text)

        case "assistant":
            guard let message = object["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]]
            else { return .other }
            let text = content
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
                .joined()
            return text.isEmpty ? .other : .assistantText(text)

        case "result":
            return .result(ClaudeResult(
                text: object["result"] as? String,
                sessionID: object["session_id"] as? String,
                isError: (object["is_error"] as? Bool) ?? (object["subtype"] as? String != "success")
            ))

        default:
            return .other
        }
    }

    private static func window(_ value: Any?) -> ClaudeUsageWindow? {
        guard let dict = value as? [String: Any],
              let utilization = (dict["utilization"] as? NSNumber)?.doubleValue
        else { return nil }
        let resetsAt = (dict["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return ClaudeUsageWindow(utilization: utilization, resetsAt: resetsAt)
    }
}
