import Foundation

/// Whose local logs the Usage tab reads. Only Claude Code and the Codex CLI
/// keep usage on this Mac (the hosted APIs and Ollama keep none), so the
/// tab follows the chosen AI when it is Codex and stays on Claude Code,
/// its original source, otherwise.
public enum AIUsageSource: String, Equatable, Sendable {
    case claudeCode
    case codex

    public static func source(for provider: AIProviderID?) -> AIUsageSource {
        provider == .codexCLI ? .codex : .claudeCode
    }

    /// The tool's name in the panel, e.g. "Codex not found".
    public var toolName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }

    /// The plan's name in the ticker tooltip, e.g. "Codex usage 5h 86%".
    public var usageName: String {
        switch self {
        case .claudeCode: "Claude usage"
        case .codex: "Codex usage"
        }
    }

    /// Whether limits come from a live probe that spends a sliver of the
    /// plan (Claude Code) rather than from logs the tool already wrote.
    public var probesLimits: Bool { self == .claudeCode }
}
