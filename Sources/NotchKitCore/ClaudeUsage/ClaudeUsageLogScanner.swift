import CryptoKit
import Foundation

/// Incrementally reads Claude Code session transcripts and keeps the usage
/// records of the last seven days.
///
/// A week of transcripts can be a gigabyte, so memory is bounded by design:
/// - files last modified before the window are skipped without opening them;
/// - files are read with POSIX `read` into one reused buffer, so no chunk is
///   ever allocated (Foundation's `FileHandle.read` returns autoreleased
///   `NSData`, and one synchronous scan on a cooperative thread never drains
///   its pool, which once held the whole week in memory at launch);
/// - each file's read offset is remembered, and persisted to `indexURL`
///   together with the records, so unchanged bytes are never read again,
///   not even after a relaunch;
/// - records are kept as fixed-size values keyed by a hash of the message id,
///   with model names interned, so a week of them is a few flat tables
///   instead of tens of thousands of small heap strings that would pin
///   fragmented malloc pages for the life of the app.
///
/// A trailing partial line (still being written) is left for the next scan.
/// Files that shrink or are replaced are re-read from the start. Strictly
/// read-only on the transcripts.
///
/// An actor so scans run off the main thread and never overlap.
public actor ClaudeUsageLogScanner {
    /// `~/.claude/projects`, where Claude Code stores session transcripts.
    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// `~/Library/Application Support/NotchDeck/ClaudeUsage/scan-index.json`.
    public static var defaultIndexURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchDeck/ClaudeUsage/scan-index.json", isDirectory: false)
    }

    /// Lines longer than this can't be usage records worth the memory; they
    /// are skipped. Real transcripts top out around a few megabytes.
    public static let maxLineLength = 32 << 20

    /// After a scan reads this much, hand freed pages back to the OS.
    private static let pressureReliefThreshold: UInt64 = 32 << 20

    private struct FileState: Codable {
        var offset: UInt64
        var identity: UInt64
    }

    private let root: URL
    private let indexURL: URL?
    private let chunkSize: Int
    private var files: [String: FileState] = [:]
    /// Keyed by message id so copies of a message (content-block lines,
    /// resumed or forked sessions) are counted once.
    private var records: [MessageKey: StoredRecord] = [:]
    /// Interned model names; `StoredRecord.model` indexes into this.
    private var models: [String] = []
    private var modelIndex: [String: UInt32] = [:]
    private var indexLoaded = false
    /// Reused across the files of a scan; grows only for a line longer than
    /// `chunkSize`, shrinks back after that file and is freed after the scan.
    private var buffer: ReadBuffer?

    /// - Parameters:
    ///   - indexURL: where offsets and records persist between launches;
    ///     nil keeps them in memory only.
    ///   - chunkSize: bytes per `read`; small values exercise boundaries in tests.
    public init(
        root: URL = ClaudeUsageLogScanner.defaultRoot,
        indexURL: URL? = nil,
        chunkSize: Int = 256 << 10
    ) {
        self.root = root
        self.indexURL = indexURL
        self.chunkSize = max(chunkSize, 1)
    }

    /// Reads whatever was appended since the last scan and returns fresh stats.
    public func scan(now: Date = Date(), calendar: Calendar = .current) -> ClaudeLocalStats {
        let windowStart = ClaudeLocalStats.windowStart(now: now, calendar: calendar)
        let isFirstScan = !indexLoaded
        if isFirstScan {
            indexLoaded = true
            loadIndex()
        }
        var bytesRead: UInt64 = 0
        var seen = Set<String>()
        autoreleasepool {
            for path in transcriptPaths() {
                seen.insert(path)
                bytesRead += scanFile(path, windowStart: windowStart)
            }
        }
        buffer = nil
        let staleFiles = files.keys.filter { !seen.contains($0) }
        for path in staleFiles { files[path] = nil }
        let recordCount = records.count
        let windowSeconds = windowStart.timeIntervalSince1970
        records = records.filter { $0.value.timestamp >= windowSeconds }
        if records.count != recordCount { compactModels() }

        if bytesRead > 0 || !staleFiles.isEmpty || records.count != recordCount { saveIndex() }
        // The scan itself allocates little, but reading a week of files or
        // decoding the index still leaves freed pages behind; return them once.
        if isFirstScan || bytesRead >= Self.pressureReliefThreshold { malloc_zone_pressure_relief(nil, 0) }
        // Aggregation ignores message ids; records are already unique.
        let models = self.models
        return ClaudeLocalStats.aggregate(records.values.lazy.map {
            ClaudeUsageRecord(messageID: "", model: models[Int($0.model)],
                              timestamp: Date(timeIntervalSince1970: $0.timestamp), usage: $0.usage)
        }, now: now, calendar: calendar)
    }

    private func transcriptPaths() -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [], options: [.skipsHiddenFiles]
        ) else { return [] }
        var paths: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            paths.append(url.path)
        }
        return paths
    }

    /// Returns the number of bytes read.
    private func scanFile(_ path: String, windowStart: Date) -> UInt64 {
        var info = stat()
        guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return 0 }
        let size = UInt64(info.st_size)
        let identity = UInt64(info.st_ino)
        let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)
            + TimeInterval(info.st_mtimespec.tv_nsec) / 1e9)
        if modified < windowStart {
            // Nothing in it can fall inside the window. Forget it: if it is
            // ever appended to, re-reading from the start is correct because
            // records dedupe by message id.
            files[path] = nil
            return 0
        }

        var state = files[path] ?? FileState(offset: 0, identity: identity)
        if size < state.offset || state.identity != identity {
            state = FileState(offset: 0, identity: identity)
        }
        defer { files[path] = state }
        guard size > state.offset else { return 0 }

        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return 0 }
        defer { close(fd) }
        guard lseek(fd, off_t(state.offset), SEEK_SET) == off_t(state.offset) else { return 0 }

        let buffer = self.buffer ?? ReadBuffer(capacity: chunkSize)
        self.buffer = buffer
        defer { buffer.resize(to: chunkSize) }
        var filled = 0
        /// Inside an over-long line: drop bytes until its newline.
        var discarding = false
        var bytesRead: UInt64 = 0

        while true {
            if filled == buffer.capacity {
                if buffer.capacity >= Self.maxLineLength {
                    state.offset += UInt64(filled)
                    filled = 0
                    discarding = true
                } else {
                    buffer.resize(to: min(buffer.capacity * 2, Self.maxLineLength))
                }
            }
            let count = read(fd, buffer.base + filled, buffer.capacity - filled)
            guard count > 0 else { break }
            bytesRead += UInt64(count)
            filled += count

            let base = buffer.base
            var start = 0
            if discarding {
                guard let newline = memchr(base, 0x0A, filled) else {
                    state.offset += UInt64(filled)
                    filled = 0
                    continue
                }
                discarding = false
                start = UnsafeRawPointer(newline) - UnsafeRawPointer(base) + 1
            }
            autoreleasepool {
                while start < filled, let newline = memchr(base + start, 0x0A, filled - start) {
                    let end = UnsafeRawPointer(newline) - UnsafeRawPointer(base)
                    ingest(UnsafeRawBufferPointer(start: base + start, count: end - start), windowStart: windowStart)
                    start = end + 1
                }
            }
            if start > 0, start < filled { memmove(base, base + start, filled - start) }
            state.offset += UInt64(start)
            filled -= start
        }
        return bytesRead
    }

    private func ingest(_ line: UnsafeRawBufferPointer, windowStart: Date) {
        guard let record = ClaudeUsageRecord.parse(bytes: line), record.timestamp >= windowStart else { return }
        records[MessageKey(record.messageID)] = StoredRecord(
            model: intern(record.model),
            timestamp: record.timestamp.timeIntervalSince1970,
            usage: record.usage
        )
    }

    private func intern(_ model: String) -> UInt32 {
        if let index = modelIndex[model] { return index }
        let index = UInt32(models.count)
        models.append(model)
        modelIndex[model] = index
        return index
    }

    /// Drops model names no record in the window uses any more.
    private func compactModels() {
        let used = Set(records.values.map(\.model)).sorted()
        guard used.count < models.count else { return }
        var remap: [UInt32: UInt32] = [:]
        for (new, old) in used.enumerated() { remap[old] = UInt32(new) }
        records = records.mapValues { record in
            var record = record
            record.model = remap[record.model]!
            return record
        }
        models = used.map { models[Int($0)] }
        modelIndex = Dictionary(uniqueKeysWithValues: models.enumerated().map { ($1, UInt32($0)) })
    }

    /// The first 128 bits of the id's SHA-256: fixed-size, stable across
    /// launches (unlike `Hasher`), and collision-free in practice.
    private struct MessageKey: Hashable {
        var high: UInt64
        var low: UInt64

        init(high: UInt64, low: UInt64) {
            self.high = high
            self.low = low
        }

        init(_ messageID: String) {
            let digest = SHA256.hash(data: Data(messageID.utf8))
            (high, low) = digest.withUnsafeBytes {
                ($0.loadUnaligned(fromByteOffset: 0, as: UInt64.self),
                 $0.loadUnaligned(fromByteOffset: 8, as: UInt64.self))
            }
        }
    }

    private struct StoredRecord {
        var model: UInt32
        /// Seconds since 1970.
        var timestamp: Double
        var usage: ClaudeTokenUsage
    }

    /// One malloc'd block, so growing or reading into it never touches
    /// Swift's collection machinery or the autorelease pool.
    private final class ReadBuffer {
        private(set) var base: UnsafeMutableRawPointer
        private(set) var capacity: Int

        init(capacity: Int) {
            self.capacity = capacity
            base = malloc(capacity)!
        }

        /// Keeps the first `min(old, new)` bytes.
        func resize(to newCapacity: Int) {
            guard newCapacity != capacity else { return }
            base = realloc(base, newCapacity)!
            capacity = newCapacity
        }

        deinit { free(base) }
    }

    // MARK: Index

    /// Records are packed into one binary blob (base64 in the JSON), so
    /// loading a week of them is a single allocation, not one per field.
    private struct Index: Codable {
        static let currentVersion = 2

        var version: Int
        var files: [String: FileState]
        var models: [String]
        var records: Data
    }

    /// key high, key low, model, timestamp bits, then the four token counts.
    private static let packedRecordSize = 8 + 8 + 4 + 8 + 4 * 8

    private func loadIndex() {
        guard let indexURL, let data = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder().decode(Index.self, from: data),
              index.version == Index.currentVersion,
              index.records.count.isMultiple(of: Self.packedRecordSize)
        else { return }
        let count = index.records.count / Self.packedRecordSize
        var loaded: [MessageKey: StoredRecord] = [:]
        loaded.reserveCapacity(count)
        let valid = index.records.withUnsafeBytes { bytes -> Bool in
            var reader = PackedReader(bytes: bytes)
            for _ in 0..<count {
                let key = MessageKey(high: reader.next(), low: reader.next())
                let model: UInt32 = reader.next()
                guard Int(model) < index.models.count else { return false }
                let timestamp = Double(bitPattern: reader.next())
                let usage = ClaudeTokenUsage(input: Int(reader.next() as Int64), output: Int(reader.next() as Int64),
                                             cacheRead: Int(reader.next() as Int64),
                                             cacheCreation: Int(reader.next() as Int64))
                loaded[key] = StoredRecord(model: model, timestamp: timestamp, usage: usage)
            }
            return true
        }
        guard valid else { return }
        files = index.files
        records = loaded
        models = index.models
        modelIndex = Dictionary(index.models.enumerated().map { ($1, UInt32($0)) }, uniquingKeysWith: { first, _ in first })
    }

    /// Best effort: a failed write only costs a re-read next launch.
    private func saveIndex() {
        guard let indexURL else { return }
        var packed = Data(capacity: records.count * Self.packedRecordSize)
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { packed.append(contentsOf: $0) }
        }
        for (key, record) in records {
            append(key.high)
            append(key.low)
            append(record.model)
            append(record.timestamp.bitPattern)
            for count in [record.usage.input, record.usage.output, record.usage.cacheRead, record.usage.cacheCreation] {
                append(Int64(count))
            }
        }
        let index = Index(version: Index.currentVersion, files: files, models: models, records: packed)
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? FileManager.default.createDirectory(
            at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: indexURL, options: .atomic)
    }

    /// Reads little-endian integers in order; callers check the length first.
    private struct PackedReader {
        let bytes: UnsafeRawBufferPointer
        var offset = 0

        mutating func next<T: FixedWidthInteger>() -> T {
            defer { offset += MemoryLayout<T>.size }
            return T(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: T.self))
        }
    }
}
