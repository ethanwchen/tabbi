import XCTest
import TabbiKitCore

/// Answers URLSession requests in-process with a body sent in chunks, so a
/// test controls where lines break and whether the connection drops. Each
/// test registers its reply for one host, so no state is shared and nothing
/// touches the network. The hosted APIs always use their real hosts (only
/// Ollama takes a base URL), so each of those hosts belongs to one test.
private final class AIStubProtocol: URLProtocol {
    enum Reply {
        /// A status, the body in chunks, then either a clean finish or `failure`.
        case stream(status: Int, chunks: [String], failure: URLError? = nil)
        case failure(URLError)
        /// Never answers, so only cancellation ends the request.
        case hang
    }

    struct Seen {
        var request: URLRequest
        var body: Data?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [String: Reply] = [:]
    nonisolated(unsafe) private static var seen: [String: [Seen]] = [:]
    nonisolated(unsafe) private static var stops: [String: Int] = [:]

    static func reply(_ reply: Reply, for host: String) {
        lock.withLock {
            replies[host] = reply
            seen[host] = []
            stops[host] = 0
        }
    }

    static func requests(to host: String) -> [Seen] {
        lock.withLock { seen[host] ?? [] }
    }

    static func stopCount(for host: String) -> Int {
        lock.withLock { stops[host] ?? 0 }
    }

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIStubProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read)
        let reply: Reply? = Self.lock.withLock {
            Self.seen[host, default: []].append(Seen(request: request, body: body))
            return Self.replies[host]
        }
        switch reply {
        case let .stream(status, chunks, failure):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "text/event-stream"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for chunk in chunks { client?.urlProtocol(self, didLoad: Data(chunk.utf8)) }
            if let failure {
                client?.urlProtocol(self, didFailWithError: failure)
            } else {
                client?.urlProtocolDidFinishLoading(self)
            }
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        case .hang:
            break
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
        }
    }

    override func stopLoading() {
        let host = request.url?.host ?? ""
        Self.lock.withLock { Self.stops[host, default: 0] += 1 }
    }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// Drives `AIHTTPProvider` over the real `AIHTTPProvider.urlSession(_:)`
/// transport: the request URLSession sends, a body split across chunks,
/// HTTP errors, errors inside a 200 stream, dropped connections and
/// cancellation. The providers' parsing is covered with a fake transport
/// in `AIProviderTests`; this checks the bytes-to-lines layer under it.
final class AIHTTPURLSessionTransportTests: XCTestCase {
    private func ollama(host: String) -> AIHTTPProvider {
        AIHTTPProvider(id: .ollama, apiKey: nil, baseURL: URL(string: "http://\(host):11434")!,
                       transport: AIHTTPProvider.urlSession(AIStubProtocol.session))
    }

    /// Every event, or the error that ended the stream after them.
    private static func collect(_ stream: AsyncThrowingStream<AIStreamEvent, Error>) async -> ([AIStreamEvent], Error?) {
        var events: [AIStreamEvent] = []
        do {
            for try await event in stream { events.append(event) }
            return (events, nil)
        } catch {
            return (events, error)
        }
    }

    func testOllamaLinesSplitAcrossChunksArriveWhole() async throws {
        let host = "ollama-chunks.test"
        AIStubProtocol.reply(.stream(status: 200, chunks: [
            #"{"message":{"content":"Pl"#,
            #"an "},"done":false}"# + "\n" + #"{"message":{"con"#,
            #"tent":"ready"},"done":false}"# + "\n",
            #"{"message":{"content":""},"done":true}"# + "\n",
        ]), for: host)

        let (events, error) = await Self.collect(ollama(host: host).stream(.prompt("plan my day", model: "qwen3")))

        XCTAssertNil(error)
        XCTAssertEqual(events, [.textDelta("Plan "), .textDelta("ready"), .finished(text: nil)])
        let seen = try XCTUnwrap(AIStubProtocol.requests(to: host).first)
        XCTAssertEqual(seen.request.url?.absoluteString, "http://\(host):11434/api/chat")
        XCTAssertEqual(seen.request.httpMethod, "POST")
        XCTAssertNil(seen.request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(seen.body)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "qwen3")
    }

    func testOpenAISendsTheBearerKeyAndStreamsServerSentEvents() async throws {
        let host = "api.openai.com"
        AIStubProtocol.reply(.stream(status: 200, chunks: [
            ": keep-alive\n\n",
            #"data: {"choices":[{"delta":{"content":"Hel"}}]}"# + "\n\n",
            #"data: {"choices":[{"delta":{"content":"lo"}}]}"# + "\n\ndata: [DONE]\n\n",
        ]), for: host)
        let provider = AIHTTPProvider(id: .openAI, apiKey: " sk-test ",
                                      transport: AIHTTPProvider.urlSession(AIStubProtocol.session))

        let (events, error) = await Self.collect(provider.stream(.prompt("hi")))

        XCTAssertNil(error)
        XCTAssertEqual(events, [.textDelta("Hel"), .textDelta("lo"), .finished(text: nil)])
        let seen = try XCTUnwrap(AIStubProtocol.requests(to: host).first)
        XCTAssertEqual(seen.request.url?.path, "/v1/chat/completions")
        XCTAssertEqual(seen.request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(seen.request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testAnthropicOverloadedStatusIsRateLimitedWithTheServiceMessage() async throws {
        let host = "api.anthropic.com"
        AIStubProtocol.reply(.stream(status: 529, chunks: [
            #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#,
        ]), for: host)
        let provider = AIHTTPProvider(id: .anthropic, apiKey: "sk-ant",
                                      transport: AIHTTPProvider.urlSession(AIStubProtocol.session))

        let (events, error) = await Self.collect(provider.stream(.prompt("hi")))

        XCTAssertEqual(events, [])
        XCTAssertEqual(error as? AIProviderError, .rateLimited(detail: "Overloaded"))
        let seen = try XCTUnwrap(AIStubProtocol.requests(to: host).first)
        XCTAssertEqual(seen.request.value(forHTTPHeaderField: "x-api-key"), "sk-ant")
        XCTAssertNotNil(seen.request.value(forHTTPHeaderField: "anthropic-version"))
    }

    func testNotFoundWithAMessageIsAServiceError() async {
        let host = "ollama-404.test"
        AIStubProtocol.reply(.stream(status: 404, chunks: [#"{"error":"model 'qwen9' not found"}"#]), for: host)

        let (events, error) = await Self.collect(ollama(host: host).stream(.prompt("hi", model: "qwen9")))

        XCTAssertEqual(events, [])
        XCTAssertEqual(error as? AIProviderError, .service(detail: "model 'qwen9' not found"))
    }

    func testServerErrorWithAnEmptyBodyNamesTheStatus() async {
        let host = "ollama-500.test"
        AIStubProtocol.reply(.stream(status: 500, chunks: []), for: host)

        let (_, error) = await Self.collect(ollama(host: host).stream(.prompt("hi")))

        XCTAssertEqual(error as? AIProviderError, .service(detail: "The request failed (HTTP 500)."))
    }

    func testAnErrorInsideAnOKStreamEndsItAfterTheTextSoFar() async {
        let host = "ollama-stream-error.test"
        AIStubProtocol.reply(.stream(status: 200, chunks: [
            #"{"message":{"content":"Par"},"done":false}"# + "\n",
            #"{"error":"model runner crashed"}"# + "\n",
            #"{"message":{"content":"never"},"done":true}"# + "\n",
        ]), for: host)

        let (events, error) = await Self.collect(ollama(host: host).stream(.prompt("hi")))

        XCTAssertEqual(events, [.textDelta("Par")])
        XCTAssertEqual(error as? AIProviderError, .service(detail: "model runner crashed"))
    }

    func testRefusedConnectionIsUnreachable() async {
        let host = "ollama-refused.test"
        AIStubProtocol.reply(.failure(URLError(.cannotConnectToHost)), for: host)

        let (events, error) = await Self.collect(ollama(host: host).stream(.prompt("hi")))

        XCTAssertEqual(events, [])
        guard case .unreachable = error as? AIProviderError else { return XCTFail("got \(String(describing: error))") }
        XCTAssertEqual((error as? AIProviderError)?.message(for: .ollama), "Ollama is not running. Open Ollama and try again.")
    }

    func testDroppedConnectionMidStreamFailsInsteadOfFinishing() async {
        let host = "ollama-dropped.test"
        AIStubProtocol.reply(.stream(status: 200, chunks: [
            #"{"message":{"content":"Par"},"done":false}"# + "\n",
            #"{"message":{"content":"tial"#,
        ], failure: URLError(.networkConnectionLost)), for: host)

        let (events, error) = await Self.collect(ollama(host: host).stream(.prompt("hi")))

        // The half line is never parsed, and no `finished` makes the cut
        // answer look whole.
        XCTAssertFalse(events.contains(.finished(text: nil)), "got \(events)")
        XCTAssertFalse(events.contains(.textDelta("tial")))
        guard case .unreachable = error as? AIProviderError else { return XCTFail("got \(String(describing: error))") }
    }

    func testCancellingTheConsumerStopsTheRequest() async throws {
        let host = "ollama-hang.test"
        AIStubProtocol.reply(.hang, for: host)
        // A detached task that makes its own stream and returns only the
        // events: the region isolation checker of the Swift in Xcode 26.6
        // (CI) gives up on a task that captures a stream or returns the tuple.
        let provider = ollama(host: host)
        let consumer = Task.detached { [provider] () -> [AIStreamEvent] in
            await Self.collect(provider.stream(.prompt("hi"))).0
        }

        let deadline = Date().addingTimeInterval(5)
        while AIStubProtocol.requests(to: host).isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(AIStubProtocol.requests(to: host).count, 1)
        consumer.cancel()

        let events = await consumer.value
        XCTAssertEqual(events, [])
        while AIStubProtocol.stopCount(for: host) == 0, Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(AIStubProtocol.stopCount(for: host), 1, "the URLSession task was not cancelled")
    }
}
