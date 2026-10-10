import XCTest
import TabbiKitCore

/// Answers URLSession requests in-process. Each test registers a reply for
/// its own made-up host, so tests never share state or touch the network.
private final class PartyStubProtocol: URLProtocol {
    enum Reply {
        case http(status: Int, body: Data, headers: [String: String])
        case failure(URLError)
        /// Never answers, so only cancellation ends the request.
        case hang
    }

    /// What the stub saw, with the body read back from its stream.
    struct Seen {
        var request: URLRequest
        var body: Data?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [String: Reply] = [:]
    nonisolated(unsafe) private static var seen: [String: [Seen]] = [:]

    static func reply(_ reply: Reply, for host: String) {
        lock.withLock {
            replies[host] = reply
            seen[host] = []
        }
    }

    static func requests(to host: String) -> [Seen] {
        lock.withLock { seen[host] ?? [] }
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
        case let .http(status, data, headers):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        case .hang:
            break
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
        }
    }

    override func stopLoading() {}

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

/// Drives the real `URLSessionPartyTransport` through a `URLProtocol` stub:
/// how a `PartyHTTPRequest` becomes a URLRequest, how replies and the
/// `Retry-After` header come back, and how network failures and
/// cancellation surface to `PartyClient`.
final class URLSessionPartyTransportTests: XCTestCase {
    private func transport(base: String) -> URLSessionPartyTransport {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PartyStubProtocol.self]
        return URLSessionPartyTransport(baseURL: URL(string: base)!, session: URLSession(configuration: config))
    }

    func testPostSendsMethodRouteHeadersTokenAndBody() async throws {
        let host = "post.party.test"
        PartyStubProtocol.reply(.http(status: 200, body: Data(#"{"ok":true}"#.utf8), headers: [:]), for: host)
        let body = Data(#"{"code":"ABCD2345"}"#.utf8)
        let request = PartyHTTPRequest(method: "POST", path: "/v1/friends", body: body, token: "secret-token",
                                       headers: ["If-Match": "7"])

        // A trailing slash and a path prefix in the user's server setting both survive.
        let response = try await transport(base: "https://\(host)/tabbi/").send(request, timeout: 12)

        XCTAssertEqual(response, PartyHTTPResponse(statusCode: 200, body: Data(#"{"ok":true}"#.utf8)))
        let seen = try XCTUnwrap(PartyStubProtocol.requests(to: host).first)
        XCTAssertEqual(PartyStubProtocol.requests(to: host).count, 1)
        XCTAssertEqual(seen.request.httpMethod, "POST")
        XCTAssertEqual(seen.request.url?.absoluteString, "https://\(host)/tabbi/v1/friends")
        XCTAssertEqual(seen.request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(seen.request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(seen.request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
        XCTAssertEqual(seen.request.value(forHTTPHeaderField: "If-Match"), "7")
        XCTAssertEqual(seen.request.timeoutInterval, 12)
        XCTAssertEqual(seen.body, body)
    }

    func testGetWithoutBodyOrTokenSendsNeitherContentTypeNorAuthorization() async throws {
        let host = "get.party.test"
        PartyStubProtocol.reply(.http(status: 200, body: Data("{}".utf8), headers: [:]), for: host)

        _ = try await transport(base: "https://\(host)").send(PartyHTTPRequest(method: "GET", path: "/v1/party"),
                                                               timeout: 5)

        let seen = try XCTUnwrap(PartyStubProtocol.requests(to: host).first)
        XCTAssertEqual(seen.request.httpMethod, "GET")
        XCTAssertEqual(seen.request.url?.absoluteString, "https://\(host)/v1/party")
        XCTAssertNil(seen.request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertNil(seen.request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(seen.body?.isEmpty ?? true)
    }

    func testErrorStatusIsReturnedWithBodyAndRetryAfter() async throws {
        let host = "limited.party.test"
        let body = Data(#"{"error":"rate_limited","message":"slow down"}"#.utf8)
        PartyStubProtocol.reply(.http(status: 429, body: body, headers: ["Retry-After": "30"]), for: host)

        let response = try await transport(base: "https://\(host)").send(PartyHTTPRequest(method: "GET", path: "/v1/me"),
                                                                           timeout: 5)

        // Non-2xx is not a transport failure: PartyClient reads the error code.
        XCTAssertEqual(response, PartyHTTPResponse(statusCode: 429, body: body, retryAfter: 30))
    }

    func testUnparsableRetryAfterIsDropped() async throws {
        let host = "date-retry.party.test"
        PartyStubProtocol.reply(.http(status: 503, body: Data(),
                                      headers: ["Retry-After": "Wed, 21 Oct 2026 07:28:00 GMT"]), for: host)

        let response = try await transport(base: "https://\(host)").send(PartyHTTPRequest(method: "GET", path: "/"),
                                                                           timeout: 5)

        XCTAssertEqual(response.statusCode, 503)
        XCTAssertNil(response.retryAfter)
        XCTAssertTrue(response.body.isEmpty)
    }

    func testNetworkFailuresMapToPartyErrors() async {
        let cases: [(URLError.Code, String)] = [
            (.notConnectedToInternet, "offline.party.test"),
            (.timedOut, "slow.party.test"),
            (.badServerResponse, "garbled.party.test"),
        ]
        for (code, host) in cases {
            PartyStubProtocol.reply(.failure(URLError(code)), for: host)
            do {
                _ = try await transport(base: "https://\(host)").send(PartyHTTPRequest(method: "GET", path: "/"),
                                                                       timeout: 5)
                XCTFail("Expected \(code) to throw")
            } catch let error as PartyError {
                switch (code, error) {
                case (.notConnectedToInternet, .unreachable), (.timedOut, .timedOut), (.badServerResponse, .transport):
                    break
                default:
                    XCTFail("\(code) mapped to \(error)")
                }
            } catch {
                XCTFail("\(code) threw a non-Party error: \(error)")
            }
        }
    }

    func testClientSeesUnreachableWhenTheServerCannotBeFound() async {
        // An unknown host falls through to the stub's cannotFindHost, which
        // the Party tab explains as "can't reach the server".
        let client = PartyClient(transport: transport(base: "https://unregistered.party.test"))
        do {
            _ = try await client.health()
            XCTFail("Expected unreachable")
        } catch {
            XCTAssertEqual(error as? PartyError, .unreachable)
        }
    }

    func testCancellingAHangingRequestThrowsCancellation() async {
        let host = "hang.party.test"
        PartyStubProtocol.reply(.hang, for: host)
        let transport = transport(base: "https://\(host)")
        let request = Task { try await transport.send(PartyHTTPRequest(method: "GET", path: "/v1/party"), timeout: 30) }
        // Wait until the stub holds the request, then cancel the caller.
        for _ in 0..<200 where PartyStubProtocol.requests(to: host).isEmpty {
            try? await Task.sleep(for: .milliseconds(5))
        }
        request.cancel()
        do {
            _ = try await request.value
            XCTFail("Expected cancellation")
        } catch {
            // Cancelling is the caller stopping, not a network problem.
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
    }
}
