import Foundation
import TabbiKitCore
import XCTest

/// Pins what the Anki tab gets from AnkiConnect: the requests
/// `AnkiConnectClient.summary` sends, how it reads recorded replies (the
/// deck list, deck counts, the "Deck counts unavailable." failure of
/// AnkiConnect 2026.10 and its fallbacks, `multi` partial failures, older
/// add-ons that name decks by their leaf), the `AnkiSummary` it builds or
/// the error it throws, the connection state and copy that error shows, the
/// `AnkiFormat` strings and the activity record the module logs, to the
/// golden fixture `shared/fixtures/anki/anki.json`.
///
/// The Windows port answers its own client's requests with the recorded
/// replies, in order, and compares the requests and everything after them,
/// so both apps read Anki the same way.
/// Run with `TABBI_RECORD_FIXTURES=1` to rewrite it after an intended change.
final class AnkiGoldenTests: XCTestCase {
    func testAnkiMatchesGoldenFixture() async throws {
        let url = AnkiGoldenFixture.url
        let current = await AnkiGoldenFixture.current()
        if ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1" {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PetGoldenFixtures.encode(current).write(to: url)
            return
        }
        let stored = try JSONDecoder().decode(AnkiGoldenFixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(stored.cases.map(\.name), current.cases.map(\.name), "Anki cases changed")
        for (old, new) in zip(stored.cases, current.cases) {
            XCTAssertEqual(old.environment, new.environment, "Case \(old.name): environment")
            XCTAssertEqual(old.activityLog, new.activityLog, "Case \(old.name): activity log")
            XCTAssertEqual(old.exchanges.count, new.exchanges.count, "Case \(old.name): number of requests")
            for (index, (oldExchange, newExchange)) in zip(old.exchanges, new.exchanges).enumerated() {
                XCTAssertEqual(oldExchange, newExchange, "Case \(old.name), request \(index)")
            }
            XCTAssertEqual(old.reportedErrors, new.reportedErrors, "Case \(old.name): errors reported for the log")
            XCTAssertEqual(old.summary, new.summary, "Case \(old.name): summary")
            XCTAssertEqual(old.format, new.format, "Case \(old.name): AnkiFormat strings")
            XCTAssertEqual(old.progress, new.progress, "Case \(old.name): progress goal")
            XCTAssertEqual(old.activity, new.activity, "Case \(old.name): activity record")
            XCTAssertEqual(old.error, new.error, "Case \(old.name): error")
            XCTAssertEqual(old.connection, new.connection, "Case \(old.name): connection state")
        }
        XCTAssertEqual(stored, current, "The Anki client no longer matches \(url.lastPathComponent)")
    }

    /// The fixture's own inputs, replayed: a client that gets only the
    /// recorded replies, in order, sends the recorded requests and ends with
    /// the recorded outputs.
    func testStoredInputsReplayToStoredOutputs() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1", "Recording")
        let stored = try JSONDecoder().decode(AnkiGoldenFixture.self, from: Data(contentsOf: AnkiGoldenFixture.url))
        for storedCase in stored.cases {
            let replies = storedCase.exchanges.map(\.reply)
            let replayed = await AnkiGoldenFixture.run(
                name: storedCase.name, environment: storedCase.environment, activityLog: storedCase.activityLog
            ) { _, index in
                index < replies.count ? replies[index] : AnkiGoldenFixture.Reply(failure: "failed", failureMessage: "unexpected request")
            }
            XCTAssertEqual(replayed, storedCase, storedCase.name)
        }
    }
}

/// Any JSON value, so the fixture can hold request bodies as they go over
/// the wire and compare them by value, not by key order.
indirect enum AnkiGoldenJSON: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnkiGoldenJSON])
    case object([String: AnkiGoldenJSON])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([AnkiGoldenJSON].self) { self = .array(value) }
        else { self = .object(try container.decode([String: AnkiGoldenJSON].self)) }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    subscript(key: String) -> AnkiGoldenJSON? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var array: [AnkiGoldenJSON]? {
        if case .array(let value) = self { return value }
        return nil
    }
}

/// Answers each request with `respond(request, index)` and keeps every
/// request, its timeout and the reply it got.
private final class AnkiGoldenTransport: AnkiConnectTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [AnkiGoldenFixture.Exchange] = []
    private let respond: @Sendable (AnkiGoldenJSON, Int) -> AnkiGoldenFixture.Reply

    init(_ respond: @escaping @Sendable (AnkiGoldenJSON, Int) -> AnkiGoldenFixture.Reply) { self.respond = respond }

    var exchanges: [AnkiGoldenFixture.Exchange] { lock.withLock { log } }

    func post(_ body: Data, timeout: TimeInterval) async throws -> AnkiConnectHTTPResponse {
        let request = try JSONDecoder().decode(AnkiGoldenJSON.self, from: body)
        let reply: AnkiGoldenFixture.Reply = lock.withLock {
            let answer = respond(request, log.count)
            log.append(AnkiGoldenFixture.Exchange(request: request, timeout: timeout, reply: answer))
            return answer
        }
        switch reply.failure {
        case nil:
            return AnkiConnectHTTPResponse(statusCode: reply.status ?? 200, body: Data((reply.body ?? "").utf8))
        case "connectionRefused"?:
            throw AnkiConnectTransportError.connectionRefused
        case "timedOut"?:
            throw AnkiConnectTransportError.timedOut
        default:
            throw AnkiConnectTransportError.failed(reply.failureMessage ?? "")
        }
    }
}

/// The errors the client hands to `onError`, in order.
private final class AnkiGoldenErrorLog: @unchecked Sendable {
    private let lock = NSLock()
    private var log: [AnkiGoldenFixture.ReportedError] = []

    func add(_ action: String, _ error: AnkiConnectError) {
        lock.withLock { log.append(AnkiGoldenFixture.ReportedError(action: action, error: AnkiGoldenFixture.caseName(error))) }
    }

    var entries: [AnkiGoldenFixture.ReportedError] { lock.withLock { log } }
}

/// AnkiConnect conversations: what the client sent and what Anki answered,
/// then the summary or error the Anki tab ends with.
struct AnkiGoldenFixture: Codable, Equatable {
    static let schemaName = "tabbi.anki.golden"

    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/anki/anki.json")
    }

    /// The module id the activity record and progress goal carry.
    static let source: ModuleID = "anki"

    /// The locale the heatmap tooltips are written in.
    static let localeIdentifier = "en_US"

    // MARK: Inputs

    /// The world around the client: the clock, the time zone and rollover
    /// hour Anki days are counted in, the API key, and what the app knows
    /// about the Anki process (for explaining a refused connection).
    struct Environment: Codable, Equatable, Sendable {
        var now: Double
        var timeZone: String
        var rolloverHour: Int
        var apiKey: String?
        var ankiRunning: Bool
        var isInstalled: Bool
        var launchedAt: Double?
    }

    /// One reply from AnkiConnect: an HTTP `status` and raw `body`, or a
    /// transport `failure` (`connectionRefused`, `timedOut`, or `failed`
    /// with `failureMessage`).
    struct Reply: Codable, Equatable, Sendable {
        var status: Int?
        var body: String?
        var failure: String?
        var failureMessage: String?
    }

    struct Exchange: Codable, Equatable, Sendable {
        var request: AnkiGoldenJSON
        var timeout: Double
        var reply: Reply
    }

    /// A record already in the activity log, from `source`, of `kind`,
    /// counted toward the Anki day `ankiDay`.
    struct LoggedActivity: Codable, Equatable, Sendable {
        var source: String
        var kind: String
        var ankiDay: String?
        var quantity: Double?
    }

    // MARK: Outputs

    struct ReportedError: Codable, Equatable, Sendable {
        var action: String
        var error: String
    }

    struct Deck: Codable, Equatable {
        var deckID: Int64
        var name: String
        var newCount: Int
        var learnCount: Int
        var reviewCount: Int
        var totalInDeck: Int
        var dueTotal: Int
    }

    struct OutlineRow: Codable, Equatable {
        var deckID: Int64
        var depth: Int
        var title: String
    }

    struct DayCount: Codable, Equatable {
        var day: String
        var count: Int
    }

    struct Gap: Codable, Equatable {
        var action: String
        var message: String
    }

    struct Summary: Codable, Equatable {
        var day: String?
        var newDue: Int
        var learnDue: Int
        var reviewDue: Int
        var dueTotal: Int
        var reviewedToday: Int
        var hasReviewedToday: Bool
        var streak: Int
        var history: [DayCount]
        var retention: Double?
        var retentionSampleSize: Int
        var studyTimeToday: Double
        var completionFraction: Double
        var decks: [Deck]
        var topDecks: [String]
        var deckOutline: [OutlineRow]
        var missing: [String]
        var gaps: [Gap]
    }

    /// What the panel writes: the streak line, the ring's tooltip, and one
    /// heat level and tooltip per history day.
    struct Format: Codable, Equatable {
        var streak: String
        var progressHelp: String
        var heatLevels: [Int]
        var dayHelp: [String]
    }

    /// The shared progress goal Today and the ticker show.
    struct Progress: Codable, Equatable {
        var id: String
        var title: String
        var completed: Int
        var target: Int
        var unit: String
        var actionID: String?
        var actionTitle: String?
    }

    struct Activity: Codable, Equatable {
        var source: String
        var kind: String
        var start: Double
        var end: Double
        var quantity: Double?
        var unit: String?
        var metadata: [String: String]
    }

    /// The `AnkiConnectError` the refresh failed with: its case, the raw
    /// message for the unexplained ones, and the copy the panel shows.
    struct Failure: Codable, Equatable {
        var kind: String
        var message: String?
        var quotedMessage: String?
        var isUnexplained: Bool
        var failsWholeRefresh: Bool
        var title: String
        var suggestion: String
    }

    /// The `AnkiConnectionState` the refresh resolves to, and its
    /// Settings > Connections row.
    struct Connection: Codable, Equatable {
        var state: String
        var isSetupStep: Bool
        var keepsLastSummary: Bool
        var refreshInterval: Double
        var clearsBySelf: Bool
        var light: String
        var headline: String
        var detail: String
        var action: String?
        var actionTitle: String?
    }

    struct Case: Codable, Equatable {
        var name: String
        var environment: Environment
        var activityLog: [LoggedActivity]
        var exchanges: [Exchange]
        var reportedErrors: [ReportedError]
        var summary: Summary?
        var format: Format?
        var progress: Progress?
        var activity: Activity?
        var error: Failure?
        var connection: Connection
    }

    var schema = Self.schemaName
    var version = 1
    var cases: [Case]

    static func current() async -> AnkiGoldenFixture {
        var cases: [Case] = []
        for scenario in scenarios {
            let collection = scenario.collection
            let leading = scenario.leading
            cases.append(await run(name: scenario.name, environment: scenario.environment, activityLog: scenario.activityLog) { request, index in
                index < leading.count ? leading[index] : collection.reply(to: request)
            })
        }
        return AnkiGoldenFixture(cases: cases)
    }

    /// Runs one refresh (`AnkiConnectClient.summary`) against `respond` and
    /// records everything a port compares.
    static func run(
        name: String, environment: Environment, activityLog: [LoggedActivity],
        respond: @escaping @Sendable (AnkiGoldenJSON, Int) -> Reply
    ) async -> Case {
        let transport = AnkiGoldenTransport(respond)
        let reported = AnkiGoldenErrorLog()
        let running = environment.ankiRunning
        let client = AnkiConnectClient(transport: transport, apiKey: environment.apiKey, isAnkiRunning: { running },
                                       onError: { action, error in reported.add(action, error) })
        let calendar = Self.calendar(environment.timeZone)
        let now = Date(timeIntervalSince1970: environment.now)

        var summary: AnkiSummary?
        var failure: AnkiConnectError?
        do {
            summary = try await client.summary(now: now, rolloverHour: environment.rolloverHour, calendar: calendar)
        } catch let error as AnkiConnectError {
            failure = error
        } catch {
            XCTFail("Case \(name): unexpected \(error)")
            failure = .transport("\(error)")
        }
        let state = AnkiConnectionState.resolve(
            error: failure, isInstalled: environment.isInstalled,
            launchedAt: environment.launchedAt.map { Date(timeIntervalSince1970: $0) }, now: now
        )
        return Case(
            name: name,
            environment: environment,
            activityLog: activityLog,
            exchanges: transport.exchanges,
            reportedErrors: reported.entries,
            summary: summary.map(Self.summary),
            format: summary.map { format(of: $0, calendar: calendar) },
            progress: summary.map(Self.progress),
            activity: summary.flatMap { activity(of: $0, log: activityLog, now: now) },
            error: failure.map(Self.failure),
            connection: connection(of: state)
        )
    }

    static func calendar(_ timeZone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }

    /// An enum case's name without its payload, such as `anki` for
    /// `.anki("Deck counts unavailable.")`.
    static func caseName(_ value: Any) -> String {
        String(String(describing: value).prefix { $0 != "(" })
    }

    private static func summary(_ summary: AnkiSummary) -> Summary {
        Summary(
            day: summary.day?.description,
            newDue: summary.newDue,
            learnDue: summary.learnDue,
            reviewDue: summary.reviewDue,
            dueTotal: summary.dueTotal,
            reviewedToday: summary.reviewedToday,
            hasReviewedToday: summary.hasReviewedToday,
            streak: summary.streak,
            history: summary.history.map { DayCount(day: $0.day.description, count: $0.count) },
            retention: summary.retention,
            retentionSampleSize: summary.retentionSampleSize,
            studyTimeToday: summary.studyTimeToday,
            completionFraction: summary.completionFraction,
            decks: summary.decks.map {
                Deck(deckID: $0.deckID, name: $0.name, newCount: $0.newCount, learnCount: $0.learnCount,
                     reviewCount: $0.reviewCount, totalInDeck: $0.totalInDeck, dueTotal: $0.dueTotal)
            },
            topDecks: summary.topDecks.map(\.name),
            deckOutline: summary.deckOutline.map { OutlineRow(deckID: $0.deck.deckID, depth: $0.depth, title: $0.title) },
            missing: AnkiSummary.Piece.allCases.filter { summary.missing.contains($0) }.map(\.rawValue),
            gaps: summary.gaps.map { Gap(action: $0.action, message: $0.message) }
        )
    }

    private static func format(of summary: AnkiSummary, calendar: Calendar) -> Format {
        let locale = Locale(identifier: localeIdentifier)
        let dayHelp: [String] = summary.day.map { today in
            summary.history.map { AnkiFormat.dayHelp($0, today: today, calendar: calendar, locale: locale) }
        } ?? []
        return Format(
            streak: AnkiFormat.streak(summary.streak),
            progressHelp: AnkiFormat.progressHelp(summary),
            heatLevels: AnkiFormat.heatLevels(for: summary.history),
            dayHelp: dayHelp
        )
    }

    private static func progress(_ summary: AnkiSummary) -> Progress {
        let item = summary.progressItem(source: source)
        return Progress(id: item.id, title: item.title, completed: item.completed, target: item.target, unit: item.unit,
                        actionID: item.action?.id, actionTitle: item.action?.title)
    }

    private static func activity(of summary: AnkiSummary, log: [LoggedActivity], now: Date) -> Activity? {
        let logged = log.map { entry in
            ActivityRecord(
                id: UUID(uuidString: "6A1F1C1E-0000-4000-8000-000000000001")!,
                source: ModuleID(rawValue: entry.source), kind: ActivityKind(rawValue: entry.kind),
                start: now.addingTimeInterval(-3600), quantity: entry.quantity, unit: .cards,
                metadata: entry.ankiDay.map { [AnkiSummary.activityDayKey: $0] } ?? [:]
            )
        }
        guard let record = summary.reviewActivity(after: logged, source: source, now: now) else { return nil }
        return Activity(
            source: record.source.rawValue, kind: record.kind.rawValue,
            start: record.start.timeIntervalSince1970, end: record.end.timeIntervalSince1970,
            quantity: record.quantity, unit: record.unit?.rawValue, metadata: record.metadata
        )
    }

    private static func failure(_ error: AnkiConnectError) -> Failure {
        Failure(kind: caseName(error), message: error.message, quotedMessage: error.quotedMessage,
                isUnexplained: error.isUnexplained, failsWholeRefresh: error.failsWholeRefresh,
                title: error.title, suggestion: error.suggestion)
    }

    private static func connection(of state: AnkiConnectionState) -> Connection {
        let diagnosis = state.diagnosis
        let status = state.connectionStatus
        return Connection(
            state: diagnosis.technical, isSetupStep: state.isSetupStep, keepsLastSummary: state.keepsLastSummary,
            refreshInterval: state.refreshInterval(), clearsBySelf: diagnosis.clearsBySelf,
            light: status.light.rawValue, headline: status.headline, detail: status.detail,
            action: status.action.map(actionName), actionTitle: status.action?.title
        )
    }

    private static func actionName(_ action: ConnectionAction) -> String {
        switch action {
        case .download(let app): return "download.\(app.name)"
        case .openApp(let app): return "openApp.\(app.name)"
        case .showGuide(let guide): return "showGuide.\(guide.rawValue)"
        default: return caseName(action)
        }
    }

    // MARK: - Scenarios

    /// One refresh: the world it runs in, the activity already logged, the
    /// Anki collection that answers, and replies that override the first
    /// requests whatever they ask.
    struct Scenario: Sendable {
        var name: String
        var environment: Environment
        var activityLog: [LoggedActivity] = []
        var collection: AnkiGoldenCollection
        var leading: [Reply] = []
    }

    /// 2026-10-01 14:00 in New York (EDT), the Anki day 2026-10-01.
    static let afternoon: Double = 1_790_877_600
    /// 2026-10-02 02:30 in New York, before the 4am rollover: still the
    /// Anki day 2026-10-01.
    static let afterMidnight: Double = 1_790_922_600
    /// 2026-11-01 03:30 in New York (EST), the night clocks went back an
    /// hour: four hours earlier was 00:30 EDT, so the Anki day 2026-11-01.
    static let afterFallBack: Double = 1_793_521_800
    /// 2026-10-01 04:00 in New York, when the Anki day 2026-10-01 starts.
    static let rollover: Double = 1_790_841_600

    static func environment(_ now: Double = afternoon, apiKey: String? = nil, ankiRunning: Bool = true,
                            isInstalled: Bool = true, launchedAt: Double? = nil) -> Environment {
        Environment(now: now, timeZone: "America/New_York", rolloverHour: 4, apiKey: apiKey,
                    ankiRunning: ankiRunning, isInstalled: isInstalled, launchedAt: launchedAt)
    }

    static func ok(_ result: String) -> Reply {
        Reply(status: 200, body: #"{"result":"# + result + #","error":null}"#)
    }

    static func ankiError(_ message: String) -> Reply {
        Reply(status: 200, body: #"{"result":null,"error":"# + quoted(message) + "}")
    }

    static func quoted(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    /// One `cardReviews` row: `[id, cardID, usn, ease, ivl, lastIvl, factor, durationMs, type]`.
    static func row(_ ms: Int64, card: Int64, ease: Int, kind: Int = 1, duration: Int = 5_000) -> String {
        "[\(ms),\(card),-1,\(ease),10,5,2500,\(duration),\(kind)]"
    }

    static func ms(_ seconds: Double) -> Int64 { Int64(seconds * 1000) }

    static var scenarios: [Scenario] {
        let refused = Reply(failure: "connectionRefused")
        let bareCollection = AnkiGoldenCollection(decks: [AnkiGoldenCollection.Deck(1, "Default", counts: false)], modern: true)
        return [
            // AnkiConnect 2026.10: the hidden Default deck fails the first
            // getDeckStats, the second leaves it out. Full deck names,
            // children rolled into parents, a deck list in byte order
            // ("Biology Extra" before "Biology::Cells", "chemistry" last).
            Scenario(
                name: "modern-default-deck-retried",
                environment: environment(),
                activityLog: [
                    LoggedActivity(source: "anki", kind: "cards.reviewed", ankiDay: "2026-10-01", quantity: 25),
                    LoggedActivity(source: "anki", kind: "cards.reviewed", ankiDay: "2026-09-30", quantity: 120),
                    LoggedActivity(source: "study", kind: "cards.reviewed", ankiDay: "2026-10-01", quantity: 99),
                    LoggedActivity(source: "anki", kind: "focus.completed", ankiDay: "2026-10-01", quantity: 7),
                ],
                collection: AnkiGoldenCollection(
                    decks: [
                        .init(1_700_000_000_006, "Japanese", new: 10, review: 15, total: 1_506),
                        .init(1, "Default", counts: false),
                        .init(1_700_000_000_002, "Biology::Cells", new: 2, learn: 1, review: 6, total: 260),
                        .init(1_700_000_000_004, "chemistry", new: 3, learn: 1, total: 120),
                        .init(1_700_000_000_001, "Biology", new: 5, learn: 2, review: 20, total: 900, reviews: biologyReviews),
                        .init(1_700_000_000_003, "Biology Extra", review: 4, total: 50),
                        .init(1_700_000_000_005, "Japanese::JLPT N5", new: 10, review: 15, total: 1_506),
                        .init(1_700_000_000_007, "Archive", total: 3_000),
                        .init(1_700_000_000_008, "Biology::Cells::Mitosis", total: 80, reviews: [
                            row(ms(afternoon - 6_000), card: 5_010, ease: 1),
                            row(ms(afternoon - 7_000), card: 5_100, ease: 1, kind: 2, duration: 4_000),
                        ]),
                    ],
                    modern: true,
                    reviewedToday: ok("40"),
                    reviewedByDay: ok(#"[["2026-10-01",38],["2026-09-30",120],["2026-09-28",40],["2026-09-29",95],["2026-09-28",20],["2026-09-27",10],["2026-09-25",80],["2026-09-18",30],["2026-09-17",500]]"#)
                )
            ),
            // An older add-on: Default is skipped without a word and decks
            // are named by their leaf ("Cardio"), so replies match by id and
            // keep the full name. Nothing is due, and the refresh runs after
            // midnight but before the rollover, so it still counts toward
            // the previous Anki day; getNumCardsReviewedToday lags behind
            // getNumCardsReviewedByDay and the larger count wins.
            Scenario(
                name: "legacy-leaf-names-after-midnight",
                environment: environment(afterMidnight),
                activityLog: [
                    LoggedActivity(source: "anki", kind: "cards.reviewed", ankiDay: "2026-10-02", quantity: 5),
                ],
                collection: AnkiGoldenCollection(
                    decks: [
                        .init(1, "Default", counts: false),
                        .init(1_600_000_000_001, "Step1", total: 2_000),
                        .init(1_600_000_000_002, "Step1::Cardio", reportedName: "Cardio", total: 700, reviews: [
                            row(ms(rollover) - 1, card: 7_001, ease: 2, duration: 9_000),
                            row(ms(rollover), card: 7_002, ease: 4, duration: 7_000),
                            row(ms(afterMidnight - 5_400), card: 7_003, ease: 3, duration: 6_000),
                        ]),
                        .init(1_600_000_000_003, "Step1::Renal", reportedName: "Renal", total: 650),
                        .init(1_600_000_000_004, "Pharm", total: 1_200),
                    ],
                    modern: false,
                    reviewedToday: ok("0"),
                    reviewedByDay: ok(#"[["2026-10-01",12],["2026-09-29",40]]"#)
                )
            ),
            // A deck other than Default fails getDeckStats, so both batches
            // fail and the client asks deck by deck in one `multi`, keeping
            // the decks that answer. Every request carries the API key,
            // inner ones too. Nothing reviewed yet today, but the streak
            // from yesterday is still alive.
            Scenario(
                name: "deck-by-deck-multi-partial",
                environment: environment(apiKey: "s3cret"),
                collection: AnkiGoldenCollection(
                    decks: [
                        .init(1, "Default", counts: false),
                        .init(1_700_000_000_011, "Biology", new: 4, learn: 1, review: 7, total: 400),
                        .init(1_700_000_000_012, "Broken", counts: false),
                        .init(1_700_000_000_013, "Chemistry", new: 2, review: 10, total: 300),
                    ],
                    modern: true,
                    reviewedToday: ok("0"),
                    reviewedByDay: ok(#"[["2026-09-30",30],["2026-09-29",20]]"#)
                )
            ),
            // Every deck fails, one by one too: the refresh fails with
            // Anki's own words.
            Scenario(
                name: "deck-by-deck-all-fail",
                environment: environment(),
                collection: AnkiGoldenCollection(
                    decks: [.init(1, "Default", counts: false), .init(1_700_000_000_012, "Broken", counts: false)],
                    modern: true
                )
            ),
            // A new user with only the empty Default deck on AnkiConnect
            // 2026.10: there is nothing to retry without it, so the client
            // goes straight to `multi`, which fails too.
            Scenario(name: "modern-only-empty-default-deck", environment: environment(), collection: bareCollection),
            // The same collection on an older add-on: Default is skipped
            // and the refresh succeeds with nothing due.
            Scenario(
                name: "legacy-only-empty-default-deck",
                environment: environment(),
                collection: AnkiGoldenCollection(
                    decks: [.init(1, "Default", counts: false)], modern: false,
                    reviewedToday: ok("0"), reviewedByDay: ok("[]")
                )
            ),
            // No decks at all: no getDeckStats and no cardReviews request.
            Scenario(
                name: "no-decks",
                environment: environment(),
                collection: AnkiGoldenCollection(decks: [], modern: true, reviewedToday: ok("7"), reviewedByDay: ok("[]"))
            ),
            // Every optional action fails for a reason of its own: an add-on
            // without getNumCardsReviewedToday, an error from
            // getNumCardsReviewedByDay and a `multi` reply one short. The
            // due counts still show, the rest is marked missing. The
            // refresh runs the night clocks go back an hour.
            Scenario(
                name: "optional-pieces-fail",
                environment: environment(afterFallBack),
                collection: AnkiGoldenCollection(
                    decks: [.init(1_700_000_000_021, "Biology", new: 3, review: 9, total: 400),
                            .init(1_700_000_000_022, "Spanish", learn: 2, total: 100)],
                    modern: false,
                    reviewedToday: ankiError("unsupported action"),
                    reviewedByDay: ankiError("no such column: day"),
                    reviewsOverride: ok(#"[{"result":[],"error":null}]"#)
                )
            ),
            // AnkiConnect could not parse the first request body; the
            // client sends it once more and carries on.
            Scenario(
                name: "malformed-request-retried",
                environment: environment(),
                collection: AnkiGoldenCollection(
                    decks: [.init(1_700_000_000_031, "Spanish", new: 5, review: 3, total: 300)], modern: true,
                    reviewedToday: ok("3"), reviewedByDay: ok(#"[["2026-10-01",3],["2026-09-30",4]]"#)
                ),
                leading: [ankiError("Expecting value: line 1 column 1 (char 0)")]
            ),
            // The collection closes halfway through: the whole refresh
            // fails, the optional actions after it are never asked.
            Scenario(
                name: "collection-closed-mid-refresh",
                environment: environment(),
                collection: AnkiGoldenCollection(
                    decks: [.init(1_700_000_000_031, "Spanish", new: 5, total: 300)], modern: true,
                    reviewedToday: ok("3"), reviewedByDay: ankiError("Collection is not available.")
                )
            ),
            // A sync holds the collection while deck counts are asked for:
            // not retried without Default or deck by deck.
            Scenario(
                name: "collection-busy-on-deck-stats",
                environment: environment(),
                collection: AnkiGoldenCollection(
                    decks: [.init(1, "Default", counts: false), .init(1_700_000_000_031, "Spanish", new: 5, total: 300)],
                    modern: true, overrides: ["getDeckStats": ankiError("A collection operation is active.")]
                )
            ),
            Scenario(
                name: "anki-closed",
                environment: environment(ankiRunning: false),
                collection: bareCollection.overriding("deckNamesAndIds", refused)
            ),
            Scenario(
                name: "anki-not-installed",
                environment: environment(ankiRunning: false, isInstalled: false),
                collection: bareCollection.overriding("deckNamesAndIds", refused)
            ),
            Scenario(
                name: "anki-starting",
                environment: environment(launchedAt: afternoon - 5),
                collection: bareCollection.overriding("deckNamesAndIds", refused)
            ),
            Scenario(
                name: "add-on-missing",
                environment: environment(launchedAt: afternoon - 60),
                collection: bareCollection.overriding("deckNamesAndIds", refused)
            ),
            Scenario(
                name: "api-key-required",
                environment: environment(),
                collection: bareCollection.overriding("deckNamesAndIds", ankiError("valid api key must be provided"))
            ),
            Scenario(
                name: "origin-rejected",
                environment: environment(),
                collection: bareCollection.overriding("deckNamesAndIds", Reply(status: 403, body: ""))
            ),
            Scenario(
                name: "anki-busy",
                environment: environment(),
                collection: bareCollection.overriding("deckNamesAndIds", Reply(failure: "timedOut"))
            ),
            Scenario(
                name: "reply-not-json",
                environment: environment(),
                collection: bareCollection.overriding("deckNamesAndIds", Reply(status: 200, body: "<html>"))
            ),
            Scenario(
                name: "unknown-anki-error-shortened",
                environment: environment(),
                collection: bareCollection.overriding("deckNamesAndIds", ankiError(
                    "Traceback (most recent call last):\n  File \"plugin/__init__.py\", line 412, in handler\n"
                        + "    result = method(**params)\nAttributeError: 'NoneType' object has no attribute 'decks'"
                ))
            ),
            Scenario(
                name: "transport-failed",
                environment: environment(),
                collection: bareCollection.overriding("deckNamesAndIds", Reply(failure: "failed", failureMessage: "The network connection was lost."))
            ),
        ]
    }

    /// The parent deck's review log: twenty answers today (three Again),
    /// one right at the rollover, one a millisecond before it (yesterday),
    /// a learning step, a manual reschedule and one answer from before the
    /// 30-day window. A child deck repeats one of them, which counts once.
    static var biologyReviews: [String] {
        var rows: [String] = []
        for index in 0..<20 {
            let answeredAt: Double = afternoon - Double(600 * index)
            let ease: Int = index % 7 == 3 ? 1 : 3
            rows.append(row(ms(answeredAt), card: Int64(5_000 + index), ease: ease))
        }
        rows += [
            row(ms(rollover), card: 5_050, ease: 4, duration: 7_000),
            row(ms(rollover) - 1, card: 5_051, ease: 2, duration: 9_000),
            row(ms(afternoon - 3_600) + 1, card: 5_052, ease: 1, kind: 0, duration: 3_000),
            row(ms(afternoon - 7_200) + 1, card: 5_053, ease: 0, kind: 4, duration: 0),
            row(ms(afternoon - 31 * 86_400), card: 5_054, ease: 1),
        ]
        return rows
    }
}

/// A scripted Anki collection that answers AnkiConnect requests the way
/// the add-on does. `modern` is AnkiConnect 2026.10 (a `getDeckStats` call
/// with any deck it can't count fails whole with "Deck counts
/// unavailable.", and names decks in full); otherwise an older add-on
/// (such a deck is skipped, decks go by `reportedName`).
struct AnkiGoldenCollection: Sendable {
    struct Deck: Sendable {
        var id: Int64
        var name: String
        var reportedName: String?
        var counts: Bool
        var new: Int
        var learn: Int
        var review: Int
        var total: Int
        var reviews: [String]

        init(_ id: Int64, _ name: String, reportedName: String? = nil, counts: Bool = true, new: Int = 0,
             learn: Int = 0, review: Int = 0, total: Int = 0, reviews: [String] = []) {
            self.id = id
            self.name = name
            self.reportedName = reportedName
            self.counts = counts
            self.new = new
            self.learn = learn
            self.review = review
            self.total = total
            self.reviews = reviews
        }

        var statsEntry: String {
            #""\#(id)":{"deck_id":\#(id),"name":"\#(reportedName ?? name)","new_count":\#(new),"learn_count":\#(learn),"review_count":\#(review),"total_in_deck":\#(total)}"#
        }
    }

    var decks: [Deck]
    var modern: Bool
    var reviewedToday = AnkiGoldenFixture.ok("0")
    var reviewedByDay = AnkiGoldenFixture.ok("[]")
    /// Replaces the reply to a `multi` of `cardReviews`.
    var reviewsOverride: AnkiGoldenFixture.Reply?
    /// Replaces the reply to an action, by name.
    var overrides: [String: AnkiGoldenFixture.Reply] = [:]

    func overriding(_ action: String, _ reply: AnkiGoldenFixture.Reply) -> AnkiGoldenCollection {
        var copy = self
        copy.overrides[action] = reply
        return copy
    }

    func reply(to request: AnkiGoldenJSON) -> AnkiGoldenFixture.Reply {
        let action = request["action"]?.string ?? ""
        if let reply = overrides[action] { return reply }
        switch action {
        case "deckNamesAndIds":
            return AnkiGoldenFixture.ok("{" + decks.map { "\(AnkiGoldenFixture.quoted($0.name)):\($0.id)" }.joined(separator: ",") + "}")
        case "getDeckStats":
            return AnkiGoldenFixture.Reply(status: 200, body: inner(request))
        case "getNumCardsReviewedToday":
            return reviewedToday
        case "getNumCardsReviewedByDay":
            return reviewedByDay
        case "multi":
            let actions = request["params"]?["actions"]?.array ?? []
            if actions.first?["action"]?.string == "cardReviews", let reviewsOverride { return reviewsOverride }
            return AnkiGoldenFixture.ok("[" + actions.map(inner).joined(separator: ",") + "]")
        default:
            return AnkiGoldenFixture.ankiError("unsupported action")
        }
    }

    /// The `{"result", "error"}` body for one `getDeckStats` or
    /// `cardReviews` action.
    private func inner(_ request: AnkiGoldenJSON) -> String {
        let params = request["params"]
        switch request["action"]?.string {
        case "getDeckStats"?:
            let asked = (params?["decks"]?.array ?? []).compactMap(\.string).map { name in decks.first { $0.name == name } }
            if modern, asked.contains(where: { $0 == nil || $0?.counts == false }) {
                return #"{"result":null,"error":"Deck counts unavailable."}"#
            }
            let entries = asked.compactMap { $0 }.filter(\.counts).map(\.statsEntry)
            return #"{"result":{"# + entries.joined(separator: ",") + #"},"error":null}"#
        case "cardReviews"?:
            let name = params?["deck"]?.string
            let rows = decks.first { $0.name == name }?.reviews ?? []
            return #"{"result":["# + rows.joined(separator: ",") + #"],"error":null}"#
        default:
            return #"{"result":null,"error":"unsupported action"}"#
        }
    }
}
