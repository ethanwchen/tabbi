import Foundation

/// The finished focus sessions waiting to be reported to the crew board.
///
/// The server never trusts a total: it credits sessions, each a start, an
/// end and the minutes focused in it, and refuses one that overlaps another
/// it already has. A shared Party session and the user's own timer can log
/// the same stretch, so sessions are merged here first and one stretch of
/// time is sent once. The queue survives a quit (`CrewSessionQueueFile`),
/// is sent in batches, and forgets a session once the server answered for it.
public struct CrewSessionQueue: Codable, Hashable, Sendable {
    /// Sessions not yet answered for, oldest first, never overlapping.
    public private(set) var pending: [CrewSession]

    /// Sessions older than this are dropped unsent: the week they belong to
    /// has frozen, so the server would only answer `week_closed`.
    public static let maxAge: TimeInterval = 8 * 86_400

    public init(pending: [CrewSession] = []) {
        self.pending = pending
    }

    /// The session a finished focus record stands for, or nil for anything
    /// else (a break, cards, a stretch under a minute).
    public static func session(for record: ActivityRecord) -> CrewSession? {
        guard record.kind == .focusCompleted, let quantity = record.quantity, record.end > record.start else { return nil }
        let minutes = min(Int(quantity.rounded(.down)), Self.maxMinutes(start: record.start, end: record.end))
        guard minutes >= 1 else { return nil }
        return CrewSession(start: record.start, end: record.end, minutes: minutes)
    }

    /// The most minutes a stretch can hold: its length rounded up, and never
    /// more than `CrewCatalog.maxSessionMinutes`.
    static func maxMinutes(start: Date, end: Date) -> Int {
        let length = Int((end.timeIntervalSince(start) / 60).rounded(.up))
        return min(length, CrewCatalog.maxSessionMinutes)
    }

    /// Adds a session, merged with any pending one it overlaps or touches.
    public mutating func add(_ session: CrewSession) {
        var merged = session
        var rest: [CrewSession] = []
        for other in pending {
            if other.start <= merged.end && merged.start <= other.end {
                let start = min(other.start, merged.start), end = max(other.end, merged.end)
                // Overlapping logs count the shared time once: at most the
                // merged stretch's length, and at least either one alone.
                let minutes = min(other.minutes + merged.minutes, Self.maxMinutes(start: start, end: end))
                merged = CrewSession(start: start, end: end, minutes: max(minutes, max(other.minutes, merged.minutes)))
            } else {
                rest.append(other)
            }
        }
        rest.append(merged)
        pending = rest.sorted { $0.start < $1.start }
    }

    /// Drops sessions too old to count anywhere.
    public mutating func prune(now: Date) {
        pending.removeAll { now.timeIntervalSince($0.end) > Self.maxAge }
    }

    /// The next batch to send: the oldest sessions, at most a request's worth.
    public var nextBatch: [CrewSession] { Array(pending.prefix(CrewCatalog.maxSessionsPerReport)) }

    /// Forgets the sessions the server answered for.
    public mutating func didSend(_ batch: [CrewSession]) {
        pending.removeAll { batch.contains($0) }
    }
}

/// Where the queue is kept: one small versioned JSON file in the edition's
/// Party storage folder.
public struct CrewSessionQueueFile: Sendable {
    public static let fileName = "crew-sessions.json"
    public static let schema = VersionedJSON(current: 1)

    public let url: URL

    public init(folder: URL) {
        url = folder.appendingPathComponent(Self.fileName)
    }

    public func load() -> CrewSessionQueue {
        guard let data = try? Data(contentsOf: url),
              let queue = try? Self.schema.decode(CrewSessionQueue.self, from: data, using: Self.decoder)
        else { return CrewSessionQueue() }
        return queue
    }

    public func save(_ queue: CrewSessionQueue) throws {
        let data = try Self.schema.encode(queue, using: Self.encoder)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
