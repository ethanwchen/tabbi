import Foundation

/// Incrementally reads Claude Code session transcripts and keeps the usage
/// records of the last seven days.
///
/// Transcripts are append-only and can be tens of megabytes, so each file's
/// read offset is remembered and later scans only read new bytes. A trailing
/// partial line (still being written) is left for the next scan. Files that
/// shrink or are replaced are re-read from the start. Strictly read-only.
///
/// An actor so scans run off the main thread and never overlap.
public actor ClaudeUsageLogScanner {
    /// `~/.claude/projects`, where Claude Code stores session transcripts.
    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    private struct FileState {
        var offset: UInt64
        var identity: Int?
    }

    private let root: URL
    private let chunkSize: Int
    private var files: [String: FileState] = [:]
    /// Keyed by message id so copies of a message (content-block lines,
    /// resumed or forked sessions) are counted once.
    private var records: [String: ClaudeUsageRecord] = [:]

    public init(root: URL = ClaudeUsageLogScanner.defaultRoot, chunkSize: Int = 1 << 20) {
        self.root = root
        self.chunkSize = max(chunkSize, 1)
    }

    /// Reads whatever was appended since the last scan and returns fresh stats.
    public func scan(now: Date = Date(), calendar: Calendar = .current) -> ClaudeLocalStats {
        let windowStart = ClaudeLocalStats.windowStart(now: now, calendar: calendar)
        for url in transcriptURLs() {
            scanFile(url, windowStart: windowStart)
        }
        records = records.filter { $0.value.timestamp >= windowStart }
        return ClaudeLocalStats.aggregate(records.values, now: now, calendar: calendar)
    }

    private func transcriptURLs() -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }
        var urls: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            if (try? url.resourceValues(forKeys: Set(keys)))?.isRegularFile == true { urls.append(url) }
        }
        return urls
    }

    private func scanFile(_ url: URL, windowStart: Date) {
        let path = url.path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value
        else { return }
        let identity = (attributes[.systemFileNumber] as? NSNumber)?.intValue
        var state = files[path] ?? FileState(offset: 0, identity: identity)

        if state.offset == 0, let modified = attributes[.modificationDate] as? Date, modified < windowStart {
            return // Nothing in it can fall inside the window; skip without remembering.
        }
        if size < state.offset || state.identity != identity {
            state = FileState(offset: 0, identity: identity)
        }
        guard size > state.offset, let handle = try? FileHandle(forReadingFrom: url) else {
            files[path] = state
            return
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: state.offset)
            var pending = Data()
            while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
                pending.append(chunk)
                guard let lastNewline = pending.lastIndex(of: UInt8(ascii: "\n")) else { continue }
                let complete = pending[pending.startIndex...lastNewline]
                ingest(complete, windowStart: windowStart)
                state.offset += UInt64(complete.count)
                pending.removeSubrange(pending.startIndex...lastNewline)
            }
        } catch {
            // Keep whatever was consumed; the rest is retried next scan.
        }
        files[path] = state
    }

    /// Walks complete lines in place; only lines that pass the byte prefilter
    /// in `ClaudeUsageRecord.parse(bytes:)` are ever copied or decoded.
    private func ingest(_ data: Data, windowStart: Date) {
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let base = buffer.baseAddress else { return }
            var start = 0
            while start < buffer.count {
                let newline = memchr(base + start, 0x0A, buffer.count - start)
                let end = newline.map { UnsafeRawPointer($0) - base } ?? buffer.count
                let line = UnsafeRawBufferPointer(rebasing: buffer[start..<end])
                if let record = ClaudeUsageRecord.parse(bytes: line), record.timestamp >= windowStart {
                    records[record.messageID] = record
                }
                start = end + 1
            }
        }
    }
}
