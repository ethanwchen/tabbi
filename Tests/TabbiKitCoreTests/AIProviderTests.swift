import XCTest
@testable import TabbiKitCore

final class AIProviderIDTests: XCTestCase {
    func testSandboxOffersOnlyAPIsAndOllama() {
        XCTAssertEqual(AIProviderID.available(sandboxed: true), [.anthropic, .openAI, .gemini, .ollama])
        XCTAssertEqual(AIProviderID.available(sandboxed: false), AIProviderID.allCases)
    }

    func testEveryHTTPProviderListsItsHost() {
        for provider in AIProviderID.allCases {
            XCTAssertEqual(provider.networkAccess == nil, provider.isCommandLineTool, "\(provider)")
        }
        XCTAssertEqual(
            Set(AIProviderID.allNetworkAccess.map(\.host)),
            ["api.anthropic.com", "api.openai.com", "generativelanguage.googleapis.com", "localhost"]
        )
        XCTAssertTrue(AIProviderID.ollama.networkAccess!.isLocal)
    }

    func testEveryProviderThatLeavesTheMacNamesWhoGetsTheData() {
        for provider in AIProviderID.allCases {
            let disclosure = provider.dataDisclosure
            XCTAssertEqual(disclosure == nil, provider == .ollama, "\(provider)")
            if let recipient = provider.dataRecipient {
                XCTAssertTrue(disclosure!.contains(recipient), "\(provider)")
            }
        }
        XCTAssertEqual(AIProviderID.claudeCLI.dataRecipient, AIProviderID.anthropic.dataRecipient)
        XCTAssertEqual(AIProviderID.geminiCLI.dataRecipient, "Google")
    }

    func testOnlyHostedAPIsNeedAKeyAndHaveDefaultModels() {
        XCTAssertEqual(AIProviderID.allCases.filter(\.requiresAPIKey), [.anthropic, .openAI, .gemini])
        for provider in AIProviderID.allCases where !provider.isCommandLineTool {
            XCTAssertFalse(provider.defaultModel.isEmpty, "\(provider)")
        }
    }

    func testResolvedModelFallsBackToTheDefault() {
        XCTAssertEqual(AIRequest.prompt("hi").resolvedModel(for: .gemini), "gemini-flash-latest")
        XCTAssertEqual(AIRequest.prompt("hi", model: "  ").resolvedModel(for: .ollama), "llama3.2")
        XCTAssertEqual(AIRequest.prompt("hi", model: "qwen3").resolvedModel(for: .ollama), "qwen3")
    }

    func testErrorMessagesNameTheProvider() {
        XCTAssertEqual(AIProviderError.missingAPIKey.message(for: .gemini), "Add your Gemini API key in Settings.")
        XCTAssertEqual(AIProviderError.unreachable(detail: nil).message(for: .ollama), "Ollama is not running. Open Ollama and try again.")
    }
}

final class AIWireFormatTests: XCTestCase {
    private let png = Data([0x89, 0x50])
    private var chat: AIRequest {
        AIRequest(
            system: "Be brief.",
            messages: [.user("What is this?", images: [png]), .assistant("A chart."), .user("Thanks")],
            model: "m",
            maxTokens: 100
        )
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    func testHostedAPIsRefuseToBuildWithoutAKey() {
        for provider in [AIProviderID.anthropic, .openAI, .gemini] {
            XCTAssertThrowsError(try AIWireFormat.urlRequest(for: provider, chat, apiKey: " ")) {
                XCTAssertEqual($0 as? AIProviderError, .missingAPIKey)
            }
        }
        XCTAssertNoThrow(try AIWireFormat.urlRequest(for: .ollama, chat, apiKey: nil))
    }

    func testAnthropicRequest() throws {
        let request = try AIWireFormat.urlRequest(for: .anthropic, chat, apiKey: "sk-ant")
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        let json = try body(request)
        XCTAssertEqual(json["model"] as? String, "m")
        XCTAssertEqual(json["system"] as? String, "Be brief.")
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertEqual(json["max_tokens"] as? Int, 100)
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["user", "assistant", "user"])
        let first = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(first.map { $0["type"] as? String }, ["image", "text"])
        XCTAssertEqual((first[0]["source"] as? [String: Any])?["data"] as? String, png.base64EncodedString())
    }

    func testOpenAIRequest() throws {
        let request = try AIWireFormat.urlRequest(for: .openAI, chat, apiKey: "sk-o")
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer sk-o")
        let messages = try XCTUnwrap(try body(request)["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user", "assistant", "user"])
        let parts = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual((parts[1]["image_url"] as? [String: Any])?["url"] as? String, "data:image/png;base64,\(png.base64EncodedString())")
        XCTAssertEqual(messages[3]["content"] as? String, "Thanks")
    }

    func testGeminiRequest() throws {
        let request = try AIWireFormat.urlRequest(for: .gemini, .prompt("Hi"), apiKey: "AIza")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:streamGenerateContent?alt=sse"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "AIza")
        XCTAssertNil(request.url?.query?.range(of: "key="), "the key never goes in the URL")
        let chatBody = try body(try AIWireFormat.urlRequest(for: .gemini, chat, apiKey: "AIza"))
        let contents = try XCTUnwrap(chatBody["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.map { $0["role"] as? String }, ["user", "model", "user"])
        XCTAssertNotNil(chatBody["system_instruction"])
    }

    func testOllamaRequestUsesLocalhostOrTheGivenAddress() throws {
        let request = try AIWireFormat.urlRequest(for: .ollama, chat, apiKey: nil)
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/api/chat")
        XCTAssertNil(request.value(forHTTPHeaderField: "authorization"))
        let messages = try XCTUnwrap(try body(request)["messages"] as? [[String: Any]])
        XCTAssertEqual(messages[1]["images"] as? [String], [png.base64EncodedString()])
        let custom = try AIWireFormat.urlRequest(for: .ollama, chat, apiKey: nil, baseURL: URL(string: "http://127.0.0.1:9999")!)
        XCTAssertEqual(custom.url?.absoluteString, "http://127.0.0.1:9999/api/chat")
    }

    func testAnthropicStream() throws {
        let lines = [
            "event: message_start",
            #"data: {"type":"message_start","message":{"id":"m"}}"#,
            "",
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"lo"}}"#,
            #"data: {"type":"ping"}"#,
            #"data: {"type":"message_stop"}"#,
        ]
        XCTAssertEqual(try lines.flatMap { try AIWireFormat.events(fromLine: $0, provider: .anthropic) },
                       [.textDelta("Hel"), .textDelta("lo"), .finished(text: nil)])
        XCTAssertThrowsError(try AIWireFormat.events(
            fromLine: #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#,
            provider: .anthropic
        )) { XCTAssertEqual($0 as? AIProviderError, .rateLimited(detail: "Overloaded")) }
    }

    func testOpenAIStream() throws {
        let lines = [
            #"data: {"choices":[{"delta":{"role":"assistant","content":""}}]}"#,
            #"data: {"choices":[{"delta":{"content":"Hi"}}]}"#,
            #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#,
            "data: [DONE]",
        ]
        XCTAssertEqual(try lines.flatMap { try AIWireFormat.events(fromLine: $0, provider: .openAI) },
                       [.textDelta("Hi"), .finished(text: nil)])
    }

    func testGeminiStreamSkipsThoughts() throws {
        let line = #"data: {"candidates":[{"content":{"role":"model","parts":[{"text":"hmm","thought":true},{"text":"Answer"}]}}]}"#
        XCTAssertEqual(try AIWireFormat.events(fromLine: line, provider: .gemini), [.textDelta("Answer")])
    }

    func testOllamaStream() throws {
        XCTAssertEqual(try AIWireFormat.events(fromLine: #"{"message":{"role":"assistant","content":"Yo"},"done":false}"#, provider: .ollama),
                       [.textDelta("Yo")])
        XCTAssertEqual(try AIWireFormat.events(fromLine: #"{"message":{"role":"assistant","content":""},"done":true}"#, provider: .ollama),
                       [.finished(text: nil)])
        XCTAssertThrowsError(try AIWireFormat.events(fromLine: #"{"error":"model \"x\" not found"}"#, provider: .ollama)) {
            XCTAssertEqual($0 as? AIProviderError, .service(detail: #"model "x" not found"#))
        }
    }

    func testReasoningModelsGetRoomToThinkBeforeTheAnswer() throws {
        func limit(_ provider: AIProviderID, _ model: String) throws -> Int? {
            let json = try body(AIWireFormat.urlRequest(for: provider, AIRequest(messages: [.user("Hi")], model: model, maxTokens: 100), apiKey: "k"))
            return provider == .gemini
                ? (json["generationConfig"] as? [String: Any])?["maxOutputTokens"] as? Int
                : json["max_completion_tokens"] as? Int
        }
        XCTAssertEqual(try limit(.openAI, "gpt-5-mini"), 8292)
        XCTAssertEqual(try limit(.openAI, "o4-mini"), 8292)
        XCTAssertEqual(try limit(.openAI, "gpt-4o"), 100)
        XCTAssertEqual(try limit(.gemini, ""), 8292, "the default flash model thinks")
        XCTAssertEqual(try limit(.gemini, "gemini-2.0-flash"), 100)
        XCTAssertEqual(try limit(.gemini, "gemma-3-27b-it"), 100)
        let anthropic = try body(AIWireFormat.urlRequest(for: .anthropic, chat, apiKey: "k"))
        XCTAssertEqual(anthropic["max_tokens"] as? Int, 100)
    }

    func testAnAnswerCutOffByTheTokenLimitIsAnError() {
        let lines: [(AIProviderID, String)] = [
            (.anthropic, #"data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"}}"#),
            (.openAI, #"data: {"choices":[{"delta":{},"finish_reason":"length"}]}"#),
            (.gemini, #"data: {"candidates":[{"content":{"parts":[{"text":"x"}]},"finishReason":"MAX_TOKENS"}]}"#),
            (.ollama, #"{"message":{"role":"assistant","content":""},"done":true,"done_reason":"length"}"#),
        ]
        for (provider, line) in lines {
            XCTAssertThrowsError(try AIWireFormat.events(fromLine: line, provider: provider), "\(provider)") {
                XCTAssertEqual($0 as? AIProviderError, .cutOff)
            }
        }
        XCTAssertEqual(try AIWireFormat.events(fromLine: #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#, provider: .anthropic), [])
        XCTAssertEqual(AIProviderError.cutOff.message(for: .openAI), "OpenAI API stopped before the answer was complete. Try a shorter question.")
    }

    func testHTTPStatusErrors() {
        let body = Data(#"{"error":{"message":"Quota exceeded"}}"#.utf8)
        XCTAssertEqual(AIWireFormat.error(status: 401, body: body), .invalidAPIKey)
        XCTAssertEqual(AIWireFormat.error(status: 429, body: body), .rateLimited(detail: "Quota exceeded"))
        XCTAssertEqual(AIWireFormat.error(status: 500, body: body), .service(detail: "Quota exceeded"))
        XCTAssertEqual(AIWireFormat.error(status: 502, body: Data()), .service(detail: "The request failed (HTTP 502)."))
    }
}

final class AIHTTPProviderTests: XCTestCase {
    private static func replay(status: Int, _ lines: [String], into box: RequestBox? = nil) -> AIHTTPProvider.Transport {
        { request in
            box?.set(request)
            return AIHTTPResponse(status: status, lines: AsyncThrowingStream { continuation in
                lines.forEach { continuation.yield($0) }
                continuation.finish()
            })
        }
    }

    final class RequestBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: URLRequest?
        func set(_ request: URLRequest) { lock.withLock { stored = request } }
        var request: URLRequest? { lock.withLock { stored } }
    }

    func testStreamsDeltasAndFinishesOnce() async throws {
        let box = RequestBox()
        let provider = AIHTTPProvider(id: .openAI, apiKey: "k", transport: Self.replay(status: 200, [
            #"data: {"choices":[{"delta":{"content":"A"}}]}"#,
            #"data: {"choices":[{"delta":{"content":"B"}}]}"#,
            "data: [DONE]",
        ], into: box))
        var events: [AIStreamEvent] = []
        for try await event in provider.stream(.prompt("q")) { events.append(event) }
        XCTAssertEqual(events, [.textDelta("A"), .textDelta("B"), .finished(text: nil)])
        XCTAssertEqual(box.request?.url?.host, "api.openai.com")
    }

    func testAnswerJoinsTheDeltas() async throws {
        let provider = AIHTTPProvider(id: .ollama, apiKey: nil, transport: Self.replay(status: 200, [
            #"{"message":{"content":"Plan "},"done":false}"#,
            #"{"message":{"content":"ready"},"done":true}"#,
        ]))
        let answer = try await provider.answer(.prompt("plan my day"))
        XCTAssertEqual(answer, "Plan ready")
    }

    func testHTTPErrorBecomesAProviderError() async {
        let provider = AIHTTPProvider(id: .gemini, apiKey: "bad", transport: Self.replay(status: 403, [
            #"{"error":{"code":403,"message":"API key not valid"}}"#,
        ]))
        do {
            _ = try await provider.answer(.prompt("q"))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? AIProviderError, .invalidAPIKey)
        }
    }

    func testMissingKeyFailsWithoutAnyRequest() async {
        let box = RequestBox()
        let provider = AIHTTPProvider(id: .anthropic, apiKey: nil, transport: Self.replay(status: 200, [], into: box))
        do {
            _ = try await provider.answer(.prompt("q"))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? AIProviderError, .missingAPIKey)
        }
        XCTAssertNil(box.request)
    }

    func testConnectionFailureIsUnreachable() async {
        let provider = AIHTTPProvider(id: .ollama, apiKey: nil) { _ in throw URLError(.cannotConnectToHost) }
        do {
            _ = try await provider.answer(.prompt("q"))
            XCTFail("expected an error")
        } catch {
            guard case .unreachable = error as? AIProviderError else { return XCTFail("got \(error)") }
        }
    }

    func testAnswerTimesOut() async {
        let provider = AIHTTPProvider(id: .ollama, apiKey: nil) { _ in
            AIHTTPResponse(status: 200, lines: AsyncThrowingStream { _ in })
        }
        do {
            _ = try await provider.answer(.prompt("q"), timeout: .milliseconds(50))
            XCTFail("expected a timeout")
        } catch {
            guard case .unreachable = error as? AIProviderError else { return XCTFail("got \(error)") }
        }
    }
}
