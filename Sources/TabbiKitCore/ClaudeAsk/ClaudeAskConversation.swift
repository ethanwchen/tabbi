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
    /// Screenshots sent with a question; always empty on answers.
    public let attachments: [ClaudeAskAttachment]

    public init(id: Int, role: Role, text: String, status: Status = .complete,
                attachments: [ClaudeAskAttachment] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.status = status
        self.attachments = attachments
    }
}

/// A question as it is sent: its text and any screenshots with it.
public struct ClaudeAskQuestion: Equatable, Sendable {
    public var text: String
    public var attachments: [ClaudeAskAttachment]

    public init(text: String, attachments: [ClaudeAskAttachment] = []) {
        self.text = text
        self.attachments = attachments
    }
}

/// Why the last question couldn't be answered.
public enum ClaudeAskFailure: Equatable, Sendable {
    /// No AI provider is picked yet, so nothing was sent.
    case noProvider
    /// The provider's command line tool was not found.
    case notInstalled(AIProviderID)
    /// The provider needs an API key and none is saved.
    case needsKey(AIProviderID)
    /// The provider ran but reported an error or exited abnormally.
    /// `detail` is a short, single-line summary safe to show in the UI.
    case process(detail: String)

    /// True when Settings, not Retry, is the way forward.
    public var needsSetup: Bool {
        if case .process = self { return false }
        return true
    }
}

/// An in-memory Ask chat and the pure reducer that folds a provider's
/// stream events into it.
///
/// Kept free of process and UI concerns so the streaming semantics (partial
/// text, final result, errors, session capture for resuming) are unit tested.
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
    /// The command line tool `sessionID` belongs to; another provider can't
    /// resume it and gets the chat as messages instead.
    public private(set) var sessionProvider: AIProviderID?
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
        sessionProvider = chat.sessionID == nil ? nil : chat.sessionProvider
        for message in chat.messages {
            append(message.role, message.text, message.status, attachments: message.attachments)
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
                pendingQuestion = ClaudeAskChat.Message(role: .user, text: message.text,
                                                        attachments: message.attachments)
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
                             sessionID: sessionID, sessionProvider: sessionProvider, messages: kept)
    }

    public var isStreaming: Bool { phase == .streaming }
    public var isEmpty: Bool { messages.isEmpty }

    /// Why the latest exchange failed, while it is still the latest.
    public var failure: ClaudeAskFailure? {
        if case .failed(let failure) = phase { return failure }
        return nil
    }

    /// Starts a new exchange. Returns the trimmed prompt to send, or `nil` if
    /// the prompt is blank or an answer is still streaming. A screenshot
    /// always comes with a question, so `attachments` alone sends nothing.
    @discardableResult
    public mutating func begin(prompt: String, attachments: [ClaudeAskAttachment] = []) -> String? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return nil }
        append(.user, trimmed, .complete, attachments: attachments)
        append(.assistant, "", .streaming)
        committedText = ""
        partialText = ""
        phase = .streaming
        return trimmed
    }

    /// Applies one event from `claude -p --output-format stream-json` (the
    /// demo chat and the recorded stream fixtures use these).
    /// Events that arrive outside a streaming exchange are ignored.
    public mutating func apply(_ event: ClaudeStreamEvent) {
        guard isStreaming else { return }
        switch event {
        case .sessionStarted(let id):
            if let id { (sessionID, sessionProvider) = (id, .claudeCLI) }
        case .textDelta(let text):
            partialText += text
            updateAnswer(displayedText)
        case .assistantText(let text):
            // A complete message supersedes the deltas that built it.
            committedText = Self.join(committedText, text)
            partialText = ""
            updateAnswer(committedText)
        case .result(let result):
            if let id = result.sessionID { (sessionID, sessionProvider) = (id, .claudeCLI) }
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

    /// Applies one event from `provider`'s stream. Events that arrive outside
    /// a streaming exchange are ignored.
    public mutating func apply(_ event: AIStreamEvent, from provider: AIProviderID) {
        guard isStreaming else { return }
        switch event {
        case .sessionStarted(let id):
            sessionID = id
            sessionProvider = provider
        case .textDelta(let text):
            partialText += text
            updateAnswer(displayedText)
        case .finished(let text):
            if let text, !text.isEmpty {
                committedText = text
                partialText = ""
            }
            finish(answeredBy: provider)
        }
    }

    /// The stream ended. Without a `result` event, whatever arrived is kept as
    /// the answer; an empty answer counts as a failure.
    public mutating func finish(answeredBy provider: AIProviderID = .claudeCLI) {
        guard isStreaming else { return }
        let text = displayedText
        if text.isEmpty {
            fail(.process(detail: "\(provider.assistantName) ended without answering."))
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

    /// Removes the failed exchange and returns its question (with its
    /// screenshots) so it can be sent again with `begin(prompt:attachments:)`.
    /// `nil` when there's nothing to retry.
    public mutating func takeRetryQuestion() -> ClaudeAskQuestion? {
        guard case .failed = phase else { return nil }
        phase = .idle
        guard let userIndex = messages.lastIndex(where: { $0.role == .user }) else { return nil }
        let question = ClaudeAskQuestion(text: messages[userIndex].text, attachments: messages[userIndex].attachments)
        messages.removeSubrange(userIndex...)
        return question
    }

    /// When the last question failed because the CLI no longer has this
    /// chat's session (it deletes old ones), drops the session and returns
    /// the question so it can be sent again as a fresh session. `nil` for
    /// any other failure, so it never retries more than once.
    public mutating func takeQuestionForLostSession() -> ClaudeAskQuestion? {
        guard sessionID != nil, case .failed(.process(let detail)) = phase,
              detail.localizedCaseInsensitiveContains("No conversation found") else { return nil }
        sessionID = nil
        sessionProvider = nil
        return takeRetryQuestion()
    }

    /// The request for the question just begun, sent with `images` to
    /// `provider`. A command line tool that holds this chat's session
    /// resumes it and gets just `prompt`. Anyone else (a hosted API, which
    /// keeps no state, another tool, or a tool that lost the session) gets
    /// the earlier exchanges as messages, newest kept first: the oldest are
    /// left out past `transcriptLimit` characters. Earlier screenshots stay
    /// on this Mac; only the new question's go.
    public func request(prompt: String, images: [Data] = [], provider: AIProviderID, system: String? = nil,
                        transcriptLimit: Int = 24_000) -> AIRequest {
        let question = AIMessage.user(prompt, images: images)
        if provider.isCommandLineTool, let sessionID, sessionProvider == provider {
            return AIRequest(system: system, messages: [question], resumeSessionID: sessionID)
        }
        let earlier = savedChat()?.messages ?? []
        // A saved chat is question and answer pairs; whole pairs are kept.
        var history: [AIMessage] = []
        var length = 0
        for start in stride(from: earlier.count - (earlier.count.isMultiple(of: 2) ? 2 : 1), through: 0, by: -2) {
            let exchange = earlier[start..<min(start + 2, earlier.count)].map {
                AIMessage(role: $0.role == .user ? .user : .assistant, text: $0.text)
            }
            let size = exchange.reduce(0) { $0 + $1.text.count }
            guard length + size <= transcriptLimit || history.isEmpty else { break }
            history.insert(contentsOf: exchange, at: 0)
            length += size
        }
        return AIRequest(system: system, messages: history + [question])
    }

    /// Starts a new chat with a new `chatID`. Message ids keep increasing.
    public mutating func reset(at now: Date = Date()) {
        chatID = UUID()
        startedAt = now
        messages = []
        phase = .idle
        sessionID = nil
        sessionProvider = nil
        committedText = ""
        partialText = ""
    }

    // MARK: - Helpers

    private var displayedText: String { Self.join(committedText, partialText) }

    private var lastAssistantIndex: Int? {
        messages.lastIndex(where: { $0.role == .assistant })
    }

    private mutating func append(_ role: ClaudeAskMessage.Role, _ text: String, _ status: ClaudeAskMessage.Status,
                                 attachments: [ClaudeAskAttachment] = []) {
        messages.append(ClaudeAskMessage(id: nextID, role: role, text: text, status: status, attachments: attachments))
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
