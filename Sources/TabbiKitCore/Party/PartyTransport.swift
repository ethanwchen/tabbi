import Foundation

/// One request to the friends server, already encoded.
public struct PartyHTTPRequest: Hashable, Sendable {
    public var method: String
    /// The route, e.g. `/v1/friends`.
    public var path: String
    public var body: Data?
    /// The bearer token, when the route needs one.
    public var token: String?
    /// Extra headers, such as the `If-Match` revision a sync push needs.
    public var headers: [String: String]

    public init(method: String, path: String, body: Data? = nil, token: String? = nil,
                headers: [String: String] = [:]) {
        self.method = method
        self.path = path
        self.body = body
        self.token = token
        self.headers = headers
    }
}

/// A raw reply from the friends server.
public struct PartyHTTPResponse: Hashable, Sendable {
    public var statusCode: Int
    public var body: Data
    /// The `Retry-After` header in seconds, sent with `429`.
    public var retryAfter: TimeInterval?

    public init(statusCode: Int, body: Data, retryAfter: TimeInterval? = nil) {
        self.statusCode = statusCode
        self.body = body
        self.retryAfter = retryAfter
    }
}

/// Sends one request. Injected so tests replay recorded fixtures.
/// Network failures are thrown as `PartyError` (`.unreachable`, `.timedOut`, `.transport`).
public protocol PartyTransport: Sendable {
    func send(_ request: PartyHTTPRequest, timeout: TimeInterval) async throws -> PartyHTTPResponse
}

/// The real transport: HTTPS to the configured server with an ephemeral
/// session, so no cookies or caches outlive the request.
public struct URLSessionPartyTransport: PartyTransport {
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.session = session ?? URLSession(configuration: .ephemeral)
    }

    public func send(_ request: PartyHTTPRequest, timeout: TimeInterval) async throws -> PartyHTTPResponse {
        let url = Self.url(base: baseURL, path: request.path)
        var urlRequest = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        urlRequest.httpMethod = request.method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = request.body {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = body
        }
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        if let token = request.token {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await session.data(for: urlRequest)
            let http = response as? HTTPURLResponse
            let retryAfter = (http?.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            return PartyHTTPResponse(statusCode: http?.statusCode ?? 200, body: data, retryAfter: retryAfter)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw Self.classify(error)
        }
    }

    /// Joins a route onto the base URL, tolerating a trailing slash or a
    /// path prefix in the user's server setting.
    public static func url(base: URL, path: String) -> URL {
        var text = base.absoluteString
        while text.hasSuffix("/") { text.removeLast() }
        return URL(string: text + path) ?? base
    }

    /// Maps a `URLError` to the states the Party tab explains.
    public static func classify(_ error: URLError) -> PartyError {
        switch error.code {
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet,
             .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
            return .unreachable
        case .timedOut:
            return .timedOut
        default:
            return .transport(error.localizedDescription)
        }
    }
}
