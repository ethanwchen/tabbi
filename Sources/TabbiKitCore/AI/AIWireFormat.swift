import Foundation

/// The HTTP request and streaming response formats of the hosted APIs and
/// Ollama, kept pure so every byte Tabbi sends and every event it reads is
/// unit tested without a network.
///
/// Anthropic, OpenAI and Gemini stream server-sent events whose `data:`
/// lines each hold one JSON object; Ollama streams one JSON object per line.
public enum AIWireFormat {
    public static let anthropicVersion = "2023-06-01"
    /// Where Ollama listens unless the user changed it.
    public static let ollamaBaseURL = URL(string: "http://localhost:11434")!

    // MARK: - Requests

    /// The streaming request for `request` to an HTTP provider. `apiKey` is
    /// required for the hosted APIs; `baseURL` overrides Ollama's address.
    public static func urlRequest(
        for provider: AIProviderID,
        _ request: AIRequest,
        apiKey: String?,
        baseURL: URL? = nil
    ) throws -> URLRequest {
        let model = request.resolvedModel(for: provider)
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if provider.requiresAPIKey, key.isEmpty { throw AIProviderError.missingAPIKey }

        let url: URL
        var headers = ["content-type": "application/json"]
        let body: [String: Any]
        switch provider {
        case .anthropic:
            url = URL(string: "https://api.anthropic.com/v1/messages")!
            headers["x-api-key"] = key
            headers["anthropic-version"] = anthropicVersion
            body = anthropicBody(request, model: model)
        case .openAI:
            url = URL(string: "https://api.openai.com/v1/chat/completions")!
            headers["authorization"] = "Bearer \(key)"
            body = openAIBody(request, model: model)
        case .gemini:
            let name = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
            url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(name):streamGenerateContent?alt=sse")!
            headers["x-goog-api-key"] = key
            body = geminiBody(request)
        case .ollama:
            url = (baseURL ?? ollamaBaseURL).appendingPathComponent("api/chat")
            body = ollamaBody(request, model: model)
        case .claudeCLI, .codexCLI, .geminiCLI:
            preconditionFailure("\(provider) is a command line tool, not an HTTP provider")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 120
        for (name, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
        return urlRequest
    }

    private static let imageMediaType = "image/png"

    private static func anthropicBody(_ request: AIRequest, model: String) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": request.maxTokens,
            "stream": true,
            "messages": request.messages.map { message -> [String: Any] in
                let images: [[String: Any]] = message.images.map {
                    ["type": "image", "source": ["type": "base64", "media_type": imageMediaType, "data": $0.base64EncodedString()]]
                }
                return ["role": message.role.rawValue, "content": images + [["type": "text", "text": message.text]]]
            },
        ]
        if let system = request.system { body["system"] = system }
        return body
    }

    private static func openAIBody(_ request: AIRequest, model: String) -> [String: Any] {
        let system: [[String: Any]] = request.system.map { [["role": "system", "content": $0]] } ?? []
        let messages = request.messages.map { message -> [String: Any] in
            guard !message.images.isEmpty else { return ["role": message.role.rawValue, "content": message.text] }
            let images: [[String: Any]] = message.images.map {
                ["type": "image_url", "image_url": ["url": "data:\(imageMediaType);base64,\($0.base64EncodedString())"]]
            }
            return ["role": message.role.rawValue, "content": [["type": "text", "text": message.text]] + images]
        }
        return [
            "model": model,
            "stream": true,
            "max_completion_tokens": request.maxTokens + reasoningHeadroom(for: .openAI, model: model),
            "messages": system + messages,
        ]
    }

    private static func geminiBody(_ request: AIRequest) -> [String: Any] {
        let model = request.resolvedModel(for: .gemini)
        let maxOutputTokens = request.maxTokens + reasoningHeadroom(for: .gemini, model: model)
        var body: [String: Any] = [
            "contents": request.messages.map { message -> [String: Any] in
                let images: [[String: Any]] = message.images.map {
                    ["inline_data": ["mime_type": imageMediaType, "data": $0.base64EncodedString()]]
                }
                // Gemini calls the assistant "model".
                let role = message.role == .user ? "user" : "model"
                return ["role": role, "parts": images + [["text": message.text]]]
            },
            "generationConfig": ["maxOutputTokens": maxOutputTokens],
        ]
        if let system = request.system { body["system_instruction"] = ["parts": [["text": system]]] }
        return body
    }

    /// Extra output tokens for a model that reasons before it answers.
    /// OpenAI's reasoning models and Gemini's thinking models count their
    /// reasoning toward the output limit, so without room for it a long
    /// answer (Plan my day's JSON) could be cut off or never start. Only
    /// the tokens used are billed. Older models get none, since some
    /// refuse a limit above what they can write.
    static func reasoningHeadroom(for provider: AIProviderID, model: String) -> Int {
        let model = model.lowercased()
        switch provider {
        case .openAI:
            let reasons = ["o1", "o3", "o4", "gpt-5"].contains { model.hasPrefix($0) }
            return reasons ? 8192 : 0
        case .gemini:
            let thinks = model.hasPrefix("gemini-") && !model.hasPrefix("gemini-1.") && !model.hasPrefix("gemini-2.0")
            return thinks ? 8192 : 0
        default:
            return 0
        }
    }

    private static func ollamaBody(_ request: AIRequest, model: String) -> [String: Any] {
        let system: [[String: Any]] = request.system.map { [["role": "system", "content": $0]] } ?? []
        let messages = request.messages.map { message -> [String: Any] in
            var entry: [String: Any] = ["role": message.role.rawValue, "content": message.text]
            if !message.images.isEmpty { entry["images"] = message.images.map { $0.base64EncodedString() } }
            return entry
        }
        return ["model": model, "stream": true, "messages": system + messages]
    }

    // MARK: - Responses

    /// The events in one line of `provider`'s streaming response. Blank
    /// lines, `event:` names, keep-alives and unknown shapes yield nothing;
    /// an error the provider reports mid-stream throws `AIProviderError`,
    /// and so does an answer the token limit cut off (`cutOff`), so a
    /// feature never takes half an answer for a whole one.
    public static func events(fromLine line: String, provider: AIProviderID) throws -> [AIStreamEvent] {
        let payload: String
        if provider == .ollama {
            payload = line
        } else {
            guard line.hasPrefix("data:") else { return [] }
            payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { return [.finished(text: nil)] }
        }
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        if let error = streamError(in: object) { throw error }

        switch provider {
        case .anthropic:
            switch object["type"] as? String {
            case "message_delta":
                let stop = (object["delta"] as? [String: Any])?["stop_reason"] as? String
                if stop == "max_tokens" { throw AIProviderError.cutOff }
                return []
            case "content_block_delta":
                let delta = object["delta"] as? [String: Any]
                guard delta?["type"] as? String == "text_delta", let text = delta?["text"] as? String else { return [] }
                return [.textDelta(text)]
            case "message_stop":
                return [.finished(text: nil)]
            default:
                return []
            }
        case .openAI:
            let choices = object["choices"] as? [[String: Any]] ?? []
            if choices.contains(where: { $0["finish_reason"] as? String == "length" }) { throw AIProviderError.cutOff }
            let text = choices.compactMap { ($0["delta"] as? [String: Any])?["content"] as? String }.joined()
            return text.isEmpty ? [] : [.textDelta(text)]
        case .gemini:
            let candidates = object["candidates"] as? [[String: Any]] ?? []
            if candidates.contains(where: { $0["finishReason"] as? String == "MAX_TOKENS" }) { throw AIProviderError.cutOff }
            let parts = candidates.compactMap { ($0["content"] as? [String: Any])?["parts"] as? [[String: Any]] }
            // Thinking models stream their thoughts as parts marked `thought`.
            let text = parts.joined().filter { $0["thought"] as? Bool != true }.compactMap { $0["text"] as? String }.joined()
            return text.isEmpty ? [] : [.textDelta(text)]
        case .ollama:
            let text = (object["message"] as? [String: Any])?["content"] as? String ?? ""
            var events: [AIStreamEvent] = text.isEmpty ? [] : [.textDelta(text)]
            if object["done"] as? Bool == true {
                if object["done_reason"] as? String == "length" { throw AIProviderError.cutOff }
                events.append(.finished(text: nil))
            }
            return events
        case .claudeCLI, .codexCLI, .geminiCLI:
            return []
        }
    }

    /// The error for a response that did not start streaming: its HTTP
    /// status and body (which every provider fills with a JSON message).
    public static func error(status: Int, body: Data) -> AIProviderError {
        let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        let detail = object.flatMap(errorMessage(in:))
        switch status {
        case 401, 403: return .invalidAPIKey
        case 429, 529: return .rateLimited(detail: detail)
        case 404 where detail != nil: return .service(detail: detail!)
        default: return .service(detail: detail ?? "The request failed (HTTP \(status)).")
        }
    }

    private static func streamError(in object: [String: Any]) -> AIProviderError? {
        guard object["error"] != nil, let message = errorMessage(in: object) else { return nil }
        let type = (object["error"] as? [String: Any])?["type"] as? String
        let code = (object["error"] as? [String: Any])?["code"] as? Int
        if type == "overloaded_error" || type == "rate_limit_error" || code == 429 {
            return .rateLimited(detail: message)
        }
        return .service(detail: message)
    }

    /// `{"error":{"message":...}}` (Anthropic, OpenAI, Gemini) or
    /// `{"error":"..."}` (Ollama).
    private static func errorMessage(in object: [String: Any]) -> String? {
        if let message = object["error"] as? String { return message }
        return (object["error"] as? [String: Any])?["message"] as? String
    }
}
