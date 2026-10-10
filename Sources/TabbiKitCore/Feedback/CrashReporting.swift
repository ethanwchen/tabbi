import Foundation

/// Whether Tabbi may send a crash report, as the person chose it in the
/// next-launch prompt. Opt-in: until they choose, every report is asked
/// about, and nothing is sent without a yes.
public enum CrashReportConsent: String, Sendable, CaseIterable {
    /// Show the prompt after each crash (the default).
    case ask
    /// The person ticked "Don't ask again" and pressed Send.
    case alwaysSend
    /// The person ticked "Don't ask again" and pressed Don't Send.
    case neverSend

    /// The choice as Settings > About lists it, where it can be changed or
    /// taken back at any time.
    public var title: String {
        switch self {
        case .ask: return "Ask after a crash"
        case .alwaysSend: return "Always send"
        case .neverSend: return "Never send"
        }
    }

    /// The person's answer to one prompt.
    public enum Choice: Sendable {
        case send
        case dontSend
    }

    /// The consent to keep after the prompt: unchanged unless the person
    /// ticked "Don't ask again", which makes this answer the standing one.
    public static func after(_ choice: Choice, dontAskAgain: Bool) -> CrashReportConsent {
        guard dontAskAgain else { return .ask }
        return choice == .send ? .alwaysSend : .neverSend
    }

    /// What to do on launch with the report a crash left, if any.
    public func action(for report: CrashReport?) -> CrashReportAction {
        guard let report else { return .nothing }
        switch self {
        case .ask: return .ask(report)
        case .alwaysSend: return .send(report)
        case .neverSend: return .nothing
        }
    }
}

/// The launch-time outcome of `CrashReportConsent.action(for:)`.
public enum CrashReportAction: Equatable, Sendable {
    /// No report, or the person said never: the report is dropped unseen.
    case nothing
    /// Show the prompt with this report's disclosure.
    case ask(CrashReport)
    /// The person said always: send without asking.
    case send(CrashReport)
}

/// Loads and saves the crash report consent in `UserDefaults`, under a key
/// of its own beside the app's settings. A missing or unknown value is `.ask`,
/// so nothing is ever sent unless the person said so.
public struct CrashReportConsentStore {
    public static let key = "settings.crashReports"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> CrashReportConsent {
        defaults.string(forKey: Self.key).flatMap(CrashReportConsent.init(rawValue:)) ?? .ask
    }

    public func save(_ consent: CrashReportConsent) {
        defaults.set(consent.rawValue, forKey: Self.key)
    }
}

/// Sends one crash report to `POST /v1/crashes` on the Tabbi server.
///
/// It takes no token and sends `CrashReport.jsonData()`, exactly the body the
/// prompt's disclosure shows. A dropped connection or a busy server is tried
/// again a few times, since Tabbi often launches at login before the network
/// is up; a refused report or the server's own limits are not, so a crash
/// loop can't flood it.
public struct CrashReportUploader: Sendable {
    public enum Outcome: Equatable, Sendable {
        case sent
        /// The server refused the report or its daily limits are reached.
        case rejected(status: Int)
        /// Every attempt failed to reach the server.
        case unreachable
    }

    public static let path = "/v1/crashes"

    public var transport: any PartyTransport
    public var timeout: TimeInterval
    /// The waits before the second and later attempts.
    public var retryDelays: [Duration]
    /// Injected so tests don't wait.
    public var sleep: @Sendable (Duration) async throws -> Void

    public init(
        transport: any PartyTransport,
        timeout: TimeInterval = 15,
        retryDelays: [Duration] = [.seconds(30), .seconds(120)],
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.transport = transport
        self.timeout = timeout
        self.retryDelays = retryDelays
        self.sleep = sleep
    }

    /// The real uploader, to the deployed Tabbi server. Always the
    /// maintainer's server, even when Party is pointed at another one.
    public init() {
        self.init(transport: URLSessionPartyTransport(baseURL: PartyServer.productionURL))
    }

    public func send(_ report: CrashReport) async throws -> Outcome {
        let request = PartyHTTPRequest(method: "POST", path: Self.path, body: try report.jsonData())
        for attempt in 0...retryDelays.count {
            if attempt > 0 { try await sleep(retryDelays[attempt - 1]) }
            do {
                let response = try await transport.send(request, timeout: timeout)
                switch response.statusCode {
                case 200..<300: return .sent
                // 503 is the server's daily cap (inbox_full): trying again won't help.
                case 500..<503, 504...: continue
                default: return .rejected(status: response.statusCode)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        return .unreachable
    }
}
