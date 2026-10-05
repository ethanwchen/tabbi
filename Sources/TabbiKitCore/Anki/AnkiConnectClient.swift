import Foundation

/// Typed async client for the AnkiConnect add-on (API version 6).
///
/// Every request is a `POST` of `{"action", "version": 6, "params", "key"}`
/// and every reply is `{"result", "error"}` with HTTP 200, so errors are read
/// from the body. Failures come back as `AnkiConnectError`. The HTTP probe is
/// the source of truth for reachability; `isAnkiRunning` (the app's
/// bundle-id check) only decides how to explain a refused connection.
public struct AnkiConnectClient: Sendable {
    /// The API version this client speaks. Older add-ons are rejected.
    public static let apiVersion = 6
    /// Bundle ids Anki has shipped under: the 25.07+ launcher and older builds.
    public static let ankiBundleIdentifiers = ["net.ankiweb.anki", "net.ankiweb.dtop"]
    /// The add-on's AnkiWeb code, for install instructions.
    public static let addOnCode = "2055492159"

    public var transport: any AnkiConnectTransport
    /// Sent as `key` when the user configured one in AnkiConnect.
    public var apiKey: String?
    /// Short timeout for polling reads.
    public var requestTimeout: TimeInterval
    /// A `multi` batch runs every inner query on Anki's main thread before
    /// replying, so it gets more time than a single read.
    public var batchTimeout: TimeInterval
    /// `sync` runs on Anki's main thread and can take many seconds.
    public var syncTimeout: TimeInterval
    /// Whether an Anki process is running (by bundle id or name).
    public var isAnkiRunning: @Sendable () async -> Bool

    public init(
        transport: any AnkiConnectTransport = URLSessionAnkiConnectTransport(),
        apiKey: String? = nil,
        requestTimeout: TimeInterval = 3,
        batchTimeout: TimeInterval = 20,
        syncTimeout: TimeInterval = 90,
        isAnkiRunning: @escaping @Sendable () async -> Bool = { false }
    ) {
        self.transport = transport
        self.apiKey = apiKey
        self.requestTimeout = requestTimeout
        self.batchTimeout = batchTimeout
        self.syncTimeout = syncTimeout
        self.isAnkiRunning = isAnkiRunning
    }

    /// True when a running app looks like Anki. The launcher's GUI process
    /// may not carry either bundle id, so the name is a fallback.
    public static func isAnkiApp(bundleIdentifier: String?, localizedName: String?) -> Bool {
        if let id = bundleIdentifier, ankiBundleIdentifiers.contains(id) { return true }
        return localizedName == "Anki"
    }

    // MARK: Actions

    /// The add-on's API version.
    public func version() async throws -> Int {
        try await invoke("version", as: Int.self)
    }

    /// Asks for access. Native callers are trusted, so no dialog appears.
    public func requestPermission() async throws -> AnkiPermission {
        try await invoke("requestPermission", as: AnkiPermission.self)
    }

    /// The recommended handshake: permission must be granted and the add-on
    /// must speak version 6 or later.
    public func connect() async throws -> AnkiPermission {
        let permission = try await requestPermission()
        guard permission.granted else { throw AnkiConnectError.permissionDenied }
        if let version = permission.version, version < Self.apiVersion {
            throw AnkiConnectError.addOnOutdated(version: version)
        }
        return permission
    }

    /// All decks, sorted by name so parents precede their children.
    public func decks() async throws -> [AnkiDeck] {
        let map = try await invoke("deckNamesAndIds", as: [String: Int64].self)
        return map.map { AnkiDeck(id: $0.value, name: $0.key) }.sorted { $0.name < $1.name }
    }

    /// Due counts for the decks, in the order asked for. Decks Anki doesn't
    /// return are left out. `getDeckStats` names each deck by its leaf only
    /// ("Cardio" for "Step1::Cardio"), so replies are matched by id and keep
    /// the deck's full name.
    public func deckStats(for decks: [AnkiDeck]) async throws -> [AnkiDeckStats] {
        guard !decks.isEmpty else { return [] }
        let replies = try await invoke("getDeckStats", params: ["decks": decks.map(\.name)], as: [String: AnkiDeckStats].self)
        let byID = Dictionary(replies.values.map { ($0.deckID, $0) }, uniquingKeysWith: { first, _ in first })
        return decks.compactMap { deck in
            byID[deck.id].map {
                AnkiDeckStats(
                    deckID: deck.id, name: deck.name, newCount: $0.newCount, learnCount: $0.learnCount,
                    reviewCount: $0.reviewCount, totalInDeck: $0.totalInDeck
                )
            }
        }
    }

    /// Reviews (button presses) since today's rollover.
    public func numCardsReviewedToday() async throws -> Int {
        try await invoke("getNumCardsReviewedToday", as: Int.self)
    }

    /// Review counts for every day with reviews, newest first.
    public func numCardsReviewedByDay() async throws -> [AnkiDayCount] {
        try await invoke("getNumCardsReviewedByDay", as: [AnkiDayCount].self)
    }

    /// Card ids matching an Anki search query, e.g. `deck:"Step1" is:due`.
    public func findCards(query: String) async throws -> [Int64] {
        try await invoke("findCards", params: ["query": query], as: [Int64].self)
    }

    /// Review-log rows for one deck after `startID` (exclusive, ms epoch).
    /// Child decks are not included; query each subdeck separately.
    public func cardReviews(deck: String, startID: Int64) async throws -> [AnkiReview] {
        try await invoke("cardReviews", params: CardReviewsParams(deck: deck, startID: startID), as: [AnkiReview].self)
    }

    /// Review-log rows for several decks in one round trip, batched through
    /// `multi` because `cardReviews` takes a single deck and skips children.
    /// Rows come back in deck order; any deck's error fails the whole call.
    public func cardReviews(decks: [String], startID: Int64) async throws -> [AnkiReview] {
        guard !decks.isEmpty else { return [] }
        let actions = decks.map {
            MultiAction(action: "cardReviews", version: Self.apiVersion, params: CardReviewsParams(deck: $0, startID: startID))
        }
        let replies = try await invoke("multi", params: ["actions": actions], timeout: batchTimeout, as: [MultiReply<[AnkiReview]>].self)
        guard replies.count == decks.count else {
            throw AnkiConnectError.invalidResponse("multi: expected \(decks.count) replies, got \(replies.count)")
        }
        var rows: [AnkiReview] = []
        for reply in replies {
            if let message = reply.error { throw AnkiConnectError.fromAnkiMessage(message, action: "cardReviews") }
            rows += reply.result ?? []
        }
        return rows
    }

    /// Opens the deck and starts reviewing. Anki is not brought to the
    /// front; the app must activate it.
    @discardableResult
    public func guiDeckReview(name: String) async throws -> Bool {
        try await invoke("guiDeckReview", params: ["name": name], as: Bool.self)
    }

    /// Opens the deck's overview screen.
    @discardableResult
    public func guiDeckOverview(name: String) async throws -> Bool {
        try await invoke("guiDeckOverview", params: ["name": name], as: Bool.self)
    }

    /// Syncs with AnkiWeb, using the long timeout.
    public func sync() async throws {
        _ = try await send("sync", params: EmptyParams?.none, timeout: syncTimeout)
    }

    // MARK: Plumbing

    private struct EmptyParams: Encodable, Sendable {}

    private struct CardReviewsParams: Encodable, Sendable {
        let deck: String
        let startID: Int64
    }

    /// One inner action of a `multi` batch. Inner actions default to API
    /// version 4 (bare results), so each carries its own `version`.
    private struct MultiAction<Params: Encodable & Sendable>: Encodable, Sendable {
        let action: String
        let version: Int
        let params: Params
    }

    /// One inner `{result, error}` reply of a `multi` batch.
    private struct MultiReply<Result: Decodable>: Decodable {
        let result: Result?
        let error: String?
    }

    private struct Envelope<Params: Encodable>: Encodable {
        let action: String
        let version: Int
        let params: Params?
        let key: String?
    }

    private struct ErrorReply: Decodable {
        let error: String?
    }

    private struct ResultReply<Result: Decodable>: Decodable {
        let result: Result
    }

    private func invoke<Result: Decodable>(_ action: String, as type: Result.Type) async throws -> Result {
        try await invoke(action, params: EmptyParams?.none, as: type)
    }

    private func invoke<Params: Encodable, Result: Decodable>(
        _ action: String, params: Params?, timeout: TimeInterval? = nil, as type: Result.Type
    ) async throws -> Result {
        let body = try await send(action, params: params, timeout: timeout ?? requestTimeout)
        do {
            return try JSONDecoder().decode(ResultReply<Result>.self, from: body).result
        } catch {
            throw AnkiConnectError.invalidResponse("\(action): \(Self.describe(error))")
        }
    }

    /// Posts one action and returns the body once the `error` field is clear.
    /// A cancelled caller always gets `CancellationError`, never an
    /// `AnkiConnectError`, so a refresh abandoned mid-flight (panel closed,
    /// newer refresh started) can't flash an error state.
    private func send<Params: Encodable>(_ action: String, params: Params?, timeout: TimeInterval) async throws -> Data {
        try Task.checkCancellation()
        let envelope = Envelope(action: action, version: Self.apiVersion, params: params, key: apiKey)
        let request: Data
        do {
            request = try JSONEncoder().encode(envelope)
        } catch {
            throw AnkiConnectError.invalidResponse("\(action): could not encode request")
        }

        let response: AnkiConnectHTTPResponse
        do {
            response = try await transport.post(request, timeout: timeout)
        } catch let error as AnkiConnectTransportError {
            try Task.checkCancellation()
            switch error {
            case .connectionRefused:
                throw await isAnkiRunning() ? AnkiConnectError.addOnMissing : AnkiConnectError.ankiNotRunning
            case .timedOut:
                throw AnkiConnectError.timeout
            case .failed(let message):
                throw AnkiConnectError.transport(message)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            throw AnkiConnectError.transport(Self.describe(error))
        }
        try Task.checkCancellation()

        if response.statusCode == 403 { throw AnkiConnectError.permissionDenied }
        guard (200..<300).contains(response.statusCode) else {
            throw AnkiConnectError.transport("HTTP \(response.statusCode)")
        }
        let reply: ErrorReply
        do {
            reply = try JSONDecoder().decode(ErrorReply.self, from: response.body)
        } catch {
            throw AnkiConnectError.invalidResponse("\(action): not JSON")
        }
        if let message = reply.error {
            throw AnkiConnectError.fromAnkiMessage(message, action: action)
        }
        return response.body
    }

    private static func describe(_ error: Error) -> String {
        if let decoding = error as? DecodingError {
            switch decoding {
            case .typeMismatch(_, let context), .valueNotFound(_, let context),
                 .keyNotFound(_, let context), .dataCorrupted(let context):
                return context.debugDescription
            @unknown default:
                return "\(decoding)"
            }
        }
        return error.localizedDescription
    }
}
