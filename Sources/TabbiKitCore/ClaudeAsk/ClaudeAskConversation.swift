import Foundation

/// One bubble in the Ask Claude panel.
public struct ClaudeAskMessage: Identifiable, Equatable, Sendable {
    public enum Role: String, Codable, Equatable, Sendable {
        case user
        case assistant
    }

    /// Lifecycle of an assistant answer. User messages are always `.complete`.
    public enum Status: String, Codable, Equatable, Sendable {
        case streaming
        case complete
        /// The user pressed stop; `text` holds whatever arrived before that.
        case stopped
        case failed
    }

    /// Unique within a conversation, including across `reset()`, so SwiftUI
    /// never reuses a row identity for a different message.
    public let id: Int
    public let role: Role
    public internal(set) var text: String
    public internal(set) var status: Status

    public init(id: Int, role: Role, text: String, status: Status = .complete) {
        self.id = id
        self.role = role
        self.text = text
        self.status = status
    }
}

/// Why the last question couldn't be answered.
public enum ClaudeAskFailure: Equatable, Sendable {
    /// No `claude` executable was found (see `ClaudeCLI.overrideVariable`).
    case claudeNotFound
    /// The CLI ran but reported an error or exited abnormally.
    /// `detail` is a short, single-line summary safe to show in the UI.
    case process(detail: String)
}

/// An in-memory Ask Claude chat and the pure reducer that folds
/// `ClaudeStreamEvent`s into it.
///
/// Kept free of process and UI concerns so the streaming semantics (partial
/// text, final result, errors, session capture for `--resume`) are unit tested.
public struct ClaudeAskConversation: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case streaming
        case failed(ClaudeAskFailure)
    }

    public private(set) var messages: [ClaudeAskMessage] = []
    public private(set) var phase: Phase = .idle
    /// Session to pass to `--resume` so follow-ups keep context.
    public private(set) var sessionID: String?
    /// Names this chat in the history; `reset()` starts a new one.
    public private(set) var chatID: UUID
    /// When this chat began, kept when it is saved and restored.
    public private(set) var startedAt: Date

    /// Text of assistant messages the CLI has already finalized in this run.
    private var committedText = ""
    /// Streaming deltas of the assistant message currently being written.
    private var partialText = ""
    private var nextID = 0

    public init(chatID: UUID = UUID(), startedAt: Date = Date()) {
        self.chatID = chatID
        self.startedAt = startedAt
    }

    /// Reopens a saved chat so the next question continues it (with
    /// `--resume` when the chat has a session).
    public init(restoring chat: ClaudeAskChat) {
        self.init(chatID: chat.id, startedAt: chat.createdAt)
        sessionID = chat.sessionID
        for message in chat.messages {
            append(message.role, message.text, message.status)
        }
    }

    /// The chat as it should be saved, or `nil` while there is nothing worth
    /// keeping. A failed exchange is left out (its question can be retried,
    /// not reread) and an answer still streaming is saved as stopped, so a
    /// restored chat never shows a spinner that nothing drives.
    public func savedChat(updatedAt: Date = Date()) -> ClaudeAskChat? {
        var kept: [ClaudeAskChat.Message] = []
        var pendingQuestion: ClaudeAskChat.Message?
        for message in messages {
            switch message.role {
            case .user:
                pendingQuestion = ClaudeAskChat.Message(role: .user, text: message.text)
            case .assistant:
                guard let question = pendingQuestion, message.status != .failed else { continue }
                let status: ClaudeAskMessage.Status = message.status == .streaming ? .stopped : message.status
                guard status != .stopped || !message.text.isEmpty else { continue }
                kept += [question, ClaudeAskChat.Message(role: .assistant, text: message.text, status: status)]
                pendingQuestion = nil
            }
        }
        guard !kept.isEmpty else { return nil }
        return ClaudeAskChat(id: chatID, createdAt: startedAt, updatedAt: updatedAt,
                             sessionID: sessionID, messages: kept)
    }

    public var isStreaming: Bool { phase == .streaming }
    public var isEmpty: Bool { messages.isEmpty }

    /// Why the latest exchange failed, while it is still the latest.
    public var failure: ClaudeAskFailure? {
        if case .failed(let failure) = phase { return failure }
        return nil
    }

    /// Starts a new exchange. Returns the trimmed prompt to send, or `nil` if
    /// the prompt is blank or an answer is still streaming.
    @discardableResult
    public mutating func begin(prompt: String) -> String? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return nil }
        append(.user, trimmed, .complete)
        append(.assistant, "", .streaming)
        committedText = ""
        partialText = ""
        phase = .streaming
        return trimmed
    }

    /// Applies one event from `claude -p --output-format stream-json`.
    /// Events that arrive outside a streaming exchange are ignored.
    public mutating func apply(_ event: ClaudeStreamEvent) {
        guard isStreaming else { return }
        switch event {
        case .sessionStarted(let id):
            if let id { sessionID = id }
        case .textDelta(let text):
            partialText += text
            updateAnswer(displayedText)
        case .assistantText(let text):
            // A complete message supersedes the deltas that built it.
            committedText = Self.join(committedText, text)
            partialText = ""
            updateAnswer(committedText)
        case .result(let result):
            if let id = result.sessionID { sessionID = id }
            if result.isError {
                fail(.process(detail: Self.summarize(result.text) ?? "Claude couldn't finish this answer."))
            } else {
                let final = result.text.flatMap { $0.isEmpty ? nil : $0 } ?? displayedText
                updateAnswer(final, status: .complete)
                phase = .idle
            }
        case .rateLimit, .other:
            break
        }
    }

    /// The stream ended. Without a `result` event, whatever arrived is kept as
    /// the answer; an empty answer counts as a failure.
    public mutating func finish() {
        guard isStreaming else { return }
        let text = displayedText
        if text.isEmpty {
            fail(.process(detail: "Claude ended without answering."))
        } else {
            updateAnswer(text, status: .complete)
            phase = .idle
        }
    }

    /// Records a failure for the current exchange (or before one starts, e.g.
    /// when `claude` can't be found).
    public mutating func fail(_ failure: ClaudeAskFailure) {
        if let index = lastAssistantIndex, messages[index].status == .streaming {
            messages[index].status = .failed
        }
        phase = .failed(failure)
    }

    /// The user pressed stop: keep the partial answer, mark it stopped.
    public mutating func cancel() {
        guard isStreaming else { return }
        updateAnswer(displayedText, status: .stopped)
        phase = .idle
    }

    /// Removes the failed exchange and returns its prompt so it can be sent
    /// again with `begin(prompt:)`. `nil` when there's nothing to retry.
    public mutating func takeRetryPrompt() -> String? {
        guard case .failed = phase else { return nil }
        phase = .idle
        guard let userIndex = messages.lastIndex(where: { $0.role == .user }) else { return nil }
        let prompt = messages[userIndex].text
        messages.removeSubrange(userIndex...)
        return prompt
    }

    /// Starts a new chat with a new `chatID`. Message ids keep increasing.
    public mutating func reset(at now: Date = Date()) {
        chatID = UUID()
        startedAt = now
        messages = []
        phase = .idle
        sessionID = nil
        committedText = ""
        partialText = ""
    }

    // MARK: - Helpers

    private var displayedText: String { Self.join(committedText, partialText) }

    private var lastAssistantIndex: Int? {
        messages.lastIndex(where: { $0.role == .assistant })
    }

    private mutating func append(_ role: ClaudeAskMessage.Role, _ text: String, _ status: ClaudeAskMessage.Status) {
        messages.append(ClaudeAskMessage(id: nextID, role: role, text: text, status: status))
        nextID += 1
    }

    private mutating func updateAnswer(_ text: String, status: ClaudeAskMessage.Status? = nil) {
        guard let index = lastAssistantIndex else { return }
        messages[index].text = text
        if let status { messages[index].status = status }
    }

    private static func join(_ first: String, _ second: String) -> String {
        if first.isEmpty { return second }
        if second.isEmpty { return first }
        return first + "\n\n" + second
    }

    /// Reduces raw CLI error output to one readable line: the first non-empty
    /// line, capped in length. Returns `nil` for empty input.
    public static func summarize(_ raw: String?, limit: Int = 140) -> String? {
        guard let line = raw?
            .split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty })
        else { return nil }
        guard line.count > limit else { return line }
        return String(line.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
