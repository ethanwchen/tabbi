import Foundation

/// A raw HTTP reply from AnkiConnect. AnkiConnect answers 200 even for
/// application errors, so the status code only matters for origin rejection.
public struct AnkiConnectHTTPResponse: Hashable, Sendable {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

/// Network-level failures, already classified so the client can map them
/// to user-facing states without knowing about `URLError`.
public enum AnkiConnectTransportError: Error, Hashable, Sendable {
    /// Nothing is listening on the port: Anki is closed, still starting,
    /// or the add-on is missing.
    case connectionRefused
    /// Something is listening but did not answer in time (App Nap or a modal
    /// dialog blocking Anki's main thread).
    case timedOut
    case failed(String)
}

/// Sends one JSON body to AnkiConnect. Injected so tests can replay fixtures.
public protocol AnkiConnectTransport: Sendable {
    func post(_ body: Data, timeout: TimeInterval) async throws -> AnkiConnectHTTPResponse
}

/// The real transport: a plain `POST http://127.0.0.1:8765`.
///
/// It deliberately sends no `Origin` header. AnkiConnect allows any request
/// without one, so a native app needs no CORS configuration.
public struct URLSessionAnkiConnectTransport: AnkiConnectTransport {
    public static let defaultEndpoint = URL(string: "http://127.0.0.1:8765")!

    public let endpoint: URL
    private let session: URLSession

    public init(endpoint: URL = URLSessionAnkiConnectTransport.defaultEndpoint, session: URLSession? = nil) {
        self.endpoint = endpoint
        self.session = session ?? URLSession(configuration: .ephemeral)
    }

    public func post(_ body: Data, timeout: TimeInterval) async throws -> AnkiConnectHTTPResponse {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            return AnkiConnectHTTPResponse(statusCode: status, body: data)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw Self.classify(error)
        }
    }

    /// Maps a `URLError` to the states AnkiConnect callers care about.
    public static func classify(_ error: URLError) -> AnkiConnectTransportError {
        switch error.code {
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
            return .connectionRefused
        case .timedOut:
            return .timedOut
        default:
            return .failed(error.localizedDescription)
        }
    }
}
