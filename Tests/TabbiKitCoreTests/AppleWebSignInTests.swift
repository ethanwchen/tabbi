import XCTest
import TabbiKitCore

/// The app's half of web Sign in with Apple: Apple's authorize link, the
/// `tabbi://auth/apple` callback and the code exchange, against a server
/// that answers like `backend/src/webauth.ts`.
final class AppleWebSignInTests: XCTestCase {
    private let code = String(repeating: "ab12", count: 16)

    // MARK: Authorize link

    func testAStateIs32RandomBytesInBase64URL() {
        let first = AppleWebSignIn()
        let second = AppleWebSignIn()
        XCTAssertEqual(first.state.count, 43)
        XCTAssertNotEqual(first.state, second.state)
        XCTAssertTrue(first.state.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }

    func testTheNonceIsTheStatesHashLikeTheServerDerivesIt() {
        // base64url(SHA-256("abc")), the value the backend's webNonce gives.
        XCTAssertEqual(AppleWebSignIn(state: "abc").nonce, "ungWv48Bz-pBQUDeXa4iI7ADYaOWF3qctBD_YfIAFa0")
        XCTAssertFalse(AppleWebSignIn().nonce.contains("="))
    }

    func testTheAuthorizeLinkAsksApplePerTheWebFlow() throws {
        let attempt = AppleWebSignIn()
        let url = attempt.authorizeURL()
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "appleid.apple.com")
        XCTAssertEqual(components.path, "/auth/authorize")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query, [
            "response_type": "code id_token",
            "response_mode": "form_post",
            "client_id": "dev.tabbi.Tabbi.signin",
            "redirect_uri": "https://tabbi-friends.drosophil-anki-friends-backend.workers.dev/v1/auth/apple/web/callback",
            "scope": "name",
            "state": attempt.state,
            "nonce": attempt.nonce,
        ])
        XCTAssertTrue(url.absoluteString.contains("response_type=code%20id_token"), "a space, not a plus")
    }

    func testTheRedirectFollowsTheServer() {
        XCTAssertEqual(AppleWebSignIn.redirectURI(server: URL(string: "http://localhost:8787")!).absoluteString,
                       "http://localhost:8787/v1/auth/apple/web/callback")
    }

    // MARK: Callback link

    private func callback(_ text: String) -> AppleWebSignIn.Callback? {
        URL(string: text).flatMap(AppleWebSignIn.Callback.init(url:))
    }

    func testReadsTheOneTimeCode() {
        XCTAssertEqual(callback("tabbi://auth/apple?code=\(code)"), .code(code))
        XCTAssertEqual(callback("TABBI://Auth/apple/?code=\(code)"), .code(code))
    }

    func testReadsTheServersErrors() {
        XCTAssertEqual(callback("tabbi://auth/apple?error=cancelled"), .failure(.cancelled))
        XCTAssertEqual(callback("tabbi://auth/apple?error=not_configured"), .failure(.notConfigured))
        for reason in ["invalid_state", "invalid_identity_token", "apple_error"] {
            XCTAssertEqual(callback("tabbi://auth/apple?error=\(reason)"), .failure(.rejected), reason)
        }
        for reason in ["apple_unavailable", "rate_limited", "internal", "body_too_large", "something_new"] {
            XCTAssertEqual(callback("tabbi://auth/apple?error=\(reason)"), .failure(.unavailable), reason)
        }
        XCTAssertNil(AppleWebSignIn.Failure.cancelled.message, "cancelling says nothing")
        XCTAssertNotNil(AppleWebSignIn.Failure.unavailable.message)
    }

    func testIgnoresAnythingElse() {
        XCTAssertNil(callback("tabbi://auth/apple"))
        XCTAssertNil(callback("tabbi://auth/apple?code=short"))
        XCTAssertNil(callback("tabbi://auth/apple?code=\(code.uppercased())"))
        XCTAssertNil(callback("tabbi://auth/apple?code=\(code)&code=\(code)"))
        XCTAssertNil(callback("tabbi://auth/google?code=\(code)"))
        XCTAssertNil(callback("tabbi://auth/apple/more?code=\(code)"))
        XCTAssertNil(callback("tabbi://open?code=\(code)"))
        XCTAssertNil(callback("https://tabbinotch.com/auth/apple?code=\(code)"))
    }

    // MARK: Code exchange

    func testExchangesTheCodeWithItsStateAndTheAnonymousToken() async throws {
        let server = WebTokenServer()
        let state = AppleWebSignIn().state
        server.issue(code: code, state: state)
        let client = SyncClient(transport: server, token: "anonymous-token")

        let reply = try await client.exchangeWebSignIn(code: code, state: state)

        XCTAssertEqual(reply.credentials, PartyCredentials(token: "t-new", code: "K7QW2MZD"))
        XCTAssertEqual(reply.profile.name, "Ana")
        XCTAssertFalse(reply.newAccount)
        let request = try XCTUnwrap(server.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/v1/auth/apple/web/token")
        XCTAssertEqual(request.token, "anonymous-token", "links the Mac's anonymous Party user")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.body)) as? [String: String])
        XCTAssertEqual(body, ["code": code, "state": state])
    }

    func testACodeWorksOnceAndOnlyWithItsState() async throws {
        let server = WebTokenServer()
        let state = AppleWebSignIn().state
        server.issue(code: code, state: state)
        let client = SyncClient(transport: server)

        await assertExpired { try await client.exchangeWebSignIn(code: self.code, state: AppleWebSignIn().state) }
        // The wrong state spent the code, as on the server.
        await assertExpired { try await client.exchangeWebSignIn(code: self.code, state: state) }

        server.issue(code: code, state: state)
        _ = try await client.exchangeWebSignIn(code: code, state: state)
        await assertExpired { try await client.exchangeWebSignIn(code: self.code, state: state) }
    }

    func testOtherFailuresAreNotAnExpiredCode() async {
        let server = WebTokenServer()
        server.failure = (503, #"{"ok":false,"error":"apple_unavailable"}"#)
        do {
            _ = try await SyncClient(transport: server).exchangeWebSignIn(code: code, state: AppleWebSignIn().state)
            XCTFail("expected a failure")
        } catch let error as PartyError {
            XCTAssertFalse(error.isExpiredWebSignIn)
            XCTAssertEqual(error, .serverUnavailable)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    private func assertExpired(_ body: () async throws -> AppleSignInReply,
                               file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await body()
            XCTFail("expected invalid_code", file: file, line: line)
        } catch let error as PartyError {
            XCTAssertTrue(error.isExpiredWebSignIn, "\(error)", file: file, line: line)
        } catch {
            XCTFail("unexpected \(error)", file: file, line: line)
        }
    }
}

/// Answers `POST /v1/auth/apple/web/token` like the backend: each issued
/// code works once, and a wrong state spends it.
private final class WebTokenServer: PartyTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [String: String] = [:]
    private(set) var requests: [PartyHTTPRequest] = []
    var failure: (Int, String)?

    func issue(code: String, state: String) {
        lock.withLock { pending[code] = state }
    }

    func send(_ request: PartyHTTPRequest, timeout: TimeInterval) async throws -> PartyHTTPResponse {
        lock.withLock { requests.append(request) }
        if let (status, body) = failure { return Self.reply(body, status: status) }
        guard request.method == "POST", request.path == "/v1/auth/apple/web/token",
              let data = request.body,
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let code = body["code"], let state = body["state"] else {
            return Self.reply(#"{"ok":false,"error":"invalid_field"}"#, status: 400)
        }
        let expected = lock.withLock { pending.removeValue(forKey: code) }
        guard expected == state else { return Self.reply(#"{"ok":false,"error":"invalid_code"}"#, status: 401) }
        return Self.reply(#"{"ok":true,"token":"t-new","code":"K7QW2MZD","newAccount":false,"profile":{"code":"K7QW2MZD","name":"Ana","petName":"Mochi","species":"cat","breed":"tabby","colors":[],"costume":"none","accessories":[],"points":10,"level":1}}"#)
    }

    private static func reply(_ body: String, status: Int = 200) -> PartyHTTPResponse {
        PartyHTTPResponse(statusCode: status, body: Data(body.utf8))
    }
}
