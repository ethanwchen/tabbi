import XCTest
import TabbiKitCore

/// Records what is posted and answers from a script of replies.
private final class ScriptedCrashServer: PartyTransport, @unchecked Sendable {
    enum Reply {
        case status(Int)
        case offline
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [PartyHTTPRequest] = []

    init(_ replies: [Reply]) {
        self.replies = replies
    }

    func send(_ request: PartyHTTPRequest, timeout: TimeInterval) async throws -> PartyHTTPResponse {
        let reply: Reply = lock.withLock {
            requests.append(request)
            return replies.isEmpty ? .offline : replies.removeFirst()
        }
        switch reply {
        case .status(let code): return PartyHTTPResponse(statusCode: code, body: Data("{}".utf8))
        case .offline: throw PartyError.unreachable
        }
    }
}

private final class SleepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var waits: [Duration] = []
    var all: [Duration] { lock.withLock { waits } }
    func record(_ wait: Duration) { lock.withLock { waits.append(wait) } }
}

final class CrashReportingTests: XCTestCase {
    private let report = CrashReport(
        environment: DiagnosticEnvironment(appVersion: "1.4.0 (52)", systemVersion: "15.1.0", edition: "tabbi"),
        kind: .signal, name: "SIGSEGV",
        threads: [.init(name: "com.apple.main-thread", crashed: true, frames: ["0 Tabbi 0x1 main + 4"])]
    )!

    // MARK: Consent

    func testNothingIsSentWithoutAYes() {
        XCTAssertEqual(CrashReportConsent.ask.action(for: report), .ask(report))
        XCTAssertEqual(CrashReportConsent.neverSend.action(for: report), .nothing)
        XCTAssertEqual(CrashReportConsent.alwaysSend.action(for: report), .send(report))
        for consent in CrashReportConsent.allCases {
            XCTAssertEqual(consent.action(for: nil), .nothing, "no crash, no prompt for \(consent)")
        }
    }

    func testOnlyDontAskAgainMakesTheAnswerStanding() {
        XCTAssertEqual(CrashReportConsent.after(.send, dontAskAgain: false), .ask)
        XCTAssertEqual(CrashReportConsent.after(.dontSend, dontAskAgain: false), .ask)
        XCTAssertEqual(CrashReportConsent.after(.send, dontAskAgain: true), .alwaysSend)
        XCTAssertEqual(CrashReportConsent.after(.dontSend, dontAskAgain: true), .neverSend)
    }

    func testConsentIsStoredAndDefaultsToAsk() throws {
        let suite = "CrashReportingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CrashReportConsentStore(defaults: defaults)

        XCTAssertEqual(store.load(), .ask)
        store.save(.alwaysSend)
        XCTAssertEqual(CrashReportConsentStore(defaults: defaults).load(), .alwaysSend)
        store.save(.neverSend)
        XCTAssertEqual(store.load(), .neverSend)
        defaults.set("sometimes", forKey: CrashReportConsentStore.key)
        XCTAssertEqual(store.load(), .ask, "an unknown value never turns into sending")
    }

    func testSettingsCanTakeBackAlwaysSend() throws {
        let suite = "CrashReportingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CrashReportConsentStore(defaults: defaults)
        store.save(.alwaysSend)

        // Settings > About writes the raw value under the same key.
        defaults.set(CrashReportConsent.ask.rawValue, forKey: CrashReportConsentStore.key)
        let report = try XCTUnwrap(CrashReport(
            environment: DiagnosticEnvironment(appVersion: "1.0", systemVersion: "15.1.0", edition: "tabbi"),
            kind: .signal, name: "SIGSEGV",
            threads: [CrashReport.Thread(name: "main", crashed: true, frames: ["0 Tabbi 0x1 main + 4"])]
        ))
        XCTAssertEqual(store.load().action(for: report), .ask(report), "the next crash is asked about again")
        XCTAssertEqual(Set(CrashReportConsent.allCases.map(\.title)).count, CrashReportConsent.allCases.count)
    }

    // MARK: Upload

    private func uploader(_ server: ScriptedCrashServer, sleeps: SleepLog = SleepLog()) -> CrashReportUploader {
        CrashReportUploader(transport: server, retryDelays: [.seconds(30), .seconds(120)]) { sleeps.record($0) }
    }

    func testPostsExactlyTheDisclosedBody() async throws {
        let server = ScriptedCrashServer([.status(201)])
        let outcome = try await uploader(server).send(report)

        XCTAssertEqual(outcome, .sent)
        XCTAssertEqual(server.requests.count, 1)
        let request = try XCTUnwrap(server.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/v1/crashes")
        XCTAssertNil(request.token, "a crash report is never tied to a Party account")
        XCTAssertEqual(request.body, try report.jsonData())
        let body = try XCTUnwrap(request.body.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertEqual(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: Data(report.disclosure.utf8)) as? NSDictionary)
    }

    func testRetriesWhileTheServerCannotBeReached() async throws {
        let server = ScriptedCrashServer([.offline, .status(502), .status(201)])
        let sleeps = SleepLog()
        let outcome = try await uploader(server, sleeps: sleeps).send(report)

        XCTAssertEqual(outcome, .sent)
        XCTAssertEqual(server.requests.count, 3)
        XCTAssertEqual(sleeps.all, [.seconds(30), .seconds(120)])
    }

    func testGivesUpAfterTheLastAttempt() async throws {
        let server = ScriptedCrashServer([.offline, .offline, .offline, .status(201)])
        let outcome = try await uploader(server).send(report)

        XCTAssertEqual(outcome, .unreachable)
        XCTAssertEqual(server.requests.count, 3)
    }

    func testRefusalsAndLimitsAreNotRetried() async throws {
        for status in [400, 413, 429, 503] {
            let server = ScriptedCrashServer([.status(status), .status(201)])
            let outcome = try await uploader(server).send(report)

            XCTAssertEqual(outcome, .rejected(status: status))
            XCTAssertEqual(server.requests.count, 1, "status \(status) must not be retried")
        }
    }
}
