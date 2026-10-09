import Foundation

/// Something that answers an `AIRequest` with a stream of events. The app
/// picks one from the user's provider choice; tests pass a mock.
///
/// Cancelling the task that consumes the stream stops the request (or the
/// process, for a command line tool).
public protocol AIProvider: Sendable {
    var id: AIProviderID { get }
    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIStreamEvent, Error>
}

public extension AIProvider {
    /// The whole answer to `request`, for features that use the result
    /// rather than show it as it arrives (Plan my day, Day review, Refine).
    /// Throws the provider's error, or `AIProviderError.unreachable` after
    /// `timeout`.
    func answer(_ request: AIRequest, timeout: Duration = .seconds(60)) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                var deltas = ""
                var final: String?
                for try await event in stream(request) {
                    switch event {
                    case .textDelta(let text): deltas += text
                    case .finished(let text): final = text ?? final
                    case .sessionStarted: break
                    }
                }
                return final ?? deltas
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw AIProviderError.unreachable(detail: "timed out")
            }
            defer { group.cancelAll() }
            return try await group.next() ?? ""
        }
    }
}

/// A streamed HTTP response: its status and its body, line by line.
public struct AIHTTPResponse: Sendable {
    public var status: Int
    public var lines: AsyncThrowingStream<String, Error>

    public init(status: Int, lines: AsyncThrowingStream<String, Error>) {
        self.status = status
        self.lines = lines
    }
}

/// The hosted APIs and Ollama: one `AIWireFormat` request, its streamed
/// lines decoded into events. The transport is injected so tests replay
/// recorded responses; the app uses `urlSession(_:)`.
public struct AIHTTPProvider: AIProvider {
    public typealias Transport = @Sendable (URLRequest) async throws -> AIHTTPResponse

    public let id: AIProviderID
    private let apiKey: String?
    private let baseURL: URL?
    private let transport: Transport

    public init(id: AIProviderID, apiKey: String?, baseURL: URL? = nil, transport: @escaping Transport = AIHTTPProvider.urlSession()) {
        precondition(!id.isCommandLineTool, "\(id) is a command line tool")
        self.id = id
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.transport = transport
    }

    public func stream(_ request: AIRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        let (id, apiKey, baseURL, transport) = (id, apiKey, baseURL, transport)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try AIWireFormat.urlRequest(for: id, request, apiKey: apiKey, baseURL: baseURL)
                    let response = try await transport(urlRequest)
                    guard (200..<300).contains(response.status) else {
                        var body = ""
                        for try await line in response.lines { body += line + "\n" }
                        throw AIWireFormat.error(status: response.status, body: Data(body.utf8))
                    }
                    for try await line in response.lines {
                        for event in try AIWireFormat.events(fromLine: line, provider: id) {
                            // One `finished` closes the stream below, whatever
                            // end marker the provider sends.
                            if case .finished = event { continue }
                            continuation.yield(event)
                        }
                    }
                    continuation.yield(.finished(text: nil))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.providerError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Turns a connection failure into the error the panel explains.
    static func providerError(_ error: Error) -> Error {
        guard let urlError = error as? URLError else { return error }
        switch urlError.code {
        case .cancelled: return CancellationError()
        default: return AIProviderError.unreachable(detail: urlError.localizedDescription)
        }
    }

    /// Sends requests through `session` and streams the body by line.
    public static func urlSession(_ session: URLSession = .shared) -> Transport {
        { request in
            let (bytes, response) = try await session.bytes(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let lines = AsyncThrowingStream<String, Error> { continuation in
                let task = Task {
                    do {
                        for try await line in bytes.lines { continuation.yield(line) }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
            return AIHTTPResponse(status: status, lines: lines)
        }
    }
}
