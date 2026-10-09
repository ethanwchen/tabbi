import Foundation

/// One turn of a conversation sent to a provider.
public struct AIMessage: Hashable, Sendable {
    public enum Role: String, Hashable, Sendable {
        case user
        case assistant
    }

    public var role: Role
    public var text: String
    /// PNG images (screenshots) sent with a user turn.
    public var images: [Data]

    public init(role: Role, text: String, images: [Data] = []) {
        self.role = role
        self.text = text
        self.images = images
    }

    public static func user(_ text: String, images: [Data] = []) -> AIMessage {
        AIMessage(role: .user, text: text, images: images)
    }

    public static func assistant(_ text: String) -> AIMessage {
        AIMessage(role: .assistant, text: text)
    }
}

/// A provider-neutral request: instructions, the conversation so far and
/// the model to use. Hosted APIs are stateless, so `messages` carries the
/// whole chat; a CLI that keeps its own session gets `resumeSessionID` and
/// only needs the last message.
public struct AIRequest: Hashable, Sendable {
    public var system: String?
    public var messages: [AIMessage]
    /// Empty means the provider's `defaultModel`.
    public var model: String
    public var maxTokens: Int
    /// A CLI session to continue (from `AIStreamEvent.sessionStarted`).
    public var resumeSessionID: String?
    /// A JSON Schema the answer must follow, where the provider can enforce
    /// one (Claude Code's `--json-schema`). Others only get the prompt's
    /// own instructions, so the caller still parses the answer leniently.
    public var responseSchema: String?

    public init(
        system: String? = nil,
        messages: [AIMessage],
        model: String = "",
        maxTokens: Int = 4096,
        resumeSessionID: String? = nil,
        responseSchema: String? = nil
    ) {
        self.system = system
        self.messages = messages
        self.model = model
        self.maxTokens = maxTokens
        self.resumeSessionID = resumeSessionID
        self.responseSchema = responseSchema
    }

    /// A one-shot prompt, as Plan my day and Day review send.
    public static func prompt(_ text: String, model: String = "", responseSchema: String? = nil) -> AIRequest {
        AIRequest(messages: [.user(text)], model: model, responseSchema: responseSchema)
    }

    /// The model to send to `provider`.
    public func resolvedModel(for provider: AIProviderID) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? provider.defaultModel : trimmed
    }
}

/// What a provider streams back, the same for every provider.
public enum AIStreamEvent: Hashable, Sendable {
    /// A CLI started or resumed a session the next request can continue.
    case sessionStarted(String)
    /// The next piece of the answer.
    case textDelta(String)
    /// The run ended. `text` is the whole answer when the provider reports
    /// it (a CLI's final result); otherwise the deltas are the answer.
    case finished(text: String?)
}

/// Why a provider could not answer, worded for the panel's error state.
public enum AIProviderError: Error, Hashable, Sendable {
    /// The command line tool is not installed (or not where Tabbi looks).
    case notInstalled
    /// The provider needs an API key and none is saved.
    case missingAPIKey
    /// The key was refused (HTTP 401 or 403).
    case invalidAPIKey
    /// Too many requests or the quota ran out (HTTP 429).
    case rateLimited(detail: String?)
    /// Nothing answered at the address (Ollama not running, no network).
    case unreachable(detail: String?)
    /// The provider answered with an error of its own.
    case service(detail: String)

    /// A sentence for the error state, naming `provider`.
    public func message(for provider: AIProviderID) -> String {
        switch self {
        case .notInstalled:
            "\(provider.displayName) is not installed."
        case .missingAPIKey:
            "Add your \(provider.displayName) key in Settings."
        case .invalidAPIKey:
            "\(provider.displayName) did not accept the key. Check it in Settings."
        case .rateLimited(let detail):
            detail.map { "\(provider.displayName) is busy: \($0)" }
                ?? "\(provider.displayName) is out of quota for now. Try again in a minute."
        case .unreachable:
            provider == .ollama
                ? "Ollama is not running. Open Ollama and try again."
                : "Could not reach \(provider.displayName). Check your connection."
        case .service(let detail):
            detail
        }
    }
}
