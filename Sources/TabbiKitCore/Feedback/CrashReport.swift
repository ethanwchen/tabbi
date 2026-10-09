import Foundation

/// A crash report as Tabbi sends it to `POST /v1/crashes`, after the person
/// agreed to send it: the app version, macOS version and edition, what kind
/// of crash it was, its signal or exception type, and the threads' names
/// and stack frames. Never an exception's reason, a file path inside a home
/// folder, or anything else that could name the person or quote what they
/// typed. `init` cleans every value to what the backend accepts (printable
/// ASCII, its length caps, home folders as `~`), so the report shown in the
/// prompt's disclosure is exactly the report that is sent.
public struct CrashReport: Equatable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// A fatal signal such as SIGSEGV, SIGABRT or SIGTRAP (a Swift trap).
        case signal
        /// An uncaught Objective-C exception.
        case exception
        /// The main thread stopped answering.
        case hang
    }

    public struct Thread: Equatable, Codable, Sendable {
        /// "com.apple.main-thread", or empty for an unnamed thread.
        public let name: String
        public let crashed: Bool
        /// One line per frame, innermost first: index, image, address, symbol.
        public let frames: [String]

        public init(name: String, crashed: Bool, frames: [String]) {
            self.name = CrashReport.printable(name, limit: CrashReport.maxThreadNameLength)
            self.crashed = crashed
            self.frames = frames.prefix(CrashReport.maxFrames).compactMap(CrashReport.cleanFrame)
        }

        private enum CodingKeys: String, CodingKey {
            case name, crashed, frames
        }

        /// Decoding cleans too, so a saved report can never skip the rules.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                name: try container.decode(String.self, forKey: .name),
                crashed: try container.decode(Bool.self, forKey: .crashed),
                frames: try container.decode([String].self, forKey: .frames)
            )
        }
    }

    // The backend's limits (backend/src/crashes.ts).
    public static let maxThreads = 64
    public static let maxFrames = 128
    public static let maxFrameLength = 512
    public static let maxThreadNameLength = 64
    public static let maxNameLength = 64
    /// The backend takes bodies up to 64 KB; a report is trimmed to fit under this.
    public static let maxEncodedBytes = 60 * 1024

    public let environment: DiagnosticEnvironment
    public let kind: Kind
    /// "SIGSEGV" or "NSInvalidArgumentException"; "unknown" when nothing usable is left.
    public let name: String
    public let threads: [Thread]

    /// Cleans every value, keeps at most one crashed thread, and drops
    /// threads (the last uncrashed ones first) and then frames until the
    /// encoded report fits `maxEncodedBytes`. Nil when no frame is left,
    /// since the backend refuses a report without a stack.
    public init?(environment: DiagnosticEnvironment, kind: Kind, name: String, threads: [Thread]) {
        var sawCrashed = false
        var kept = threads.prefix(Self.maxThreads).map { thread -> Thread in
            let crashed = thread.crashed && !sawCrashed
            sawCrashed = sawCrashed || crashed
            return crashed == thread.crashed ? thread : Thread(name: thread.name, crashed: false, frames: thread.frames)
        }
        let name = Self.cleanName(name)
        let fits = { (threads: [Thread]) in
            Self(trusted: environment, kind: kind, name: name, threads: threads).encodedSize <= Self.maxEncodedBytes
        }
        while !fits(kept) {
            if let last = kept.lastIndex(where: { !$0.crashed }), kept.count > 1 {
                kept.remove(at: last)
            } else if let longest = kept.indices.max(by: { kept[$0].frames.count < kept[$1].frames.count }),
                      kept[longest].frames.count > 1 {
                let thread = kept[longest]
                kept[longest] = Thread(name: thread.name, crashed: thread.crashed, frames: Array(thread.frames.prefix(thread.frames.count / 2)))
            } else {
                break
            }
        }
        guard kept.contains(where: { !$0.frames.isEmpty }) else { return nil }
        self.init(trusted: environment, kind: kind, name: name, threads: kept)
    }

    private init(trusted environment: DiagnosticEnvironment, kind: Kind, name: String, threads: [Thread]) {
        self.environment = environment
        self.kind = kind
        self.name = name
        self.threads = threads
    }

    private var encodedSize: Int { (try? jsonData())?.count ?? 0 }

    /// The request body: exactly `version`, `macos`, `edition`, `kind`, `name` and `threads`.
    public func jsonData(pretty: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// The body as the prompt's disclosure shows it, word for word.
    public var disclosure: String {
        (try? jsonData(pretty: true)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case version, macos, edition, kind, name, threads
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(environment.appVersion, forKey: .version)
        try container.encode(environment.systemVersion, forKey: .macos)
        try container.encode(environment.edition, forKey: .edition)
        try container.encode(kind, forKey: .kind)
        try container.encode(name, forKey: .name)
        try container.encode(threads, forKey: .threads)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let environment = DiagnosticEnvironment(
            appVersion: try container.decode(String.self, forKey: .version),
            systemVersion: try container.decode(String.self, forKey: .macos),
            edition: try container.decode(String.self, forKey: .edition)
        )
        guard let report = Self(
            environment: environment,
            kind: try container.decode(Kind.self, forKey: .kind),
            name: try container.decode(String.self, forKey: .name),
            threads: try container.decode([Thread].self, forKey: .threads)
        ) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [CodingKeys.threads], debugDescription: "A crash report needs a stack frame."))
        }
        self = report
    }

    // MARK: - Cleaning

    /// Letters, digits, `_` and `.`, capped; "unknown" when nothing is left.
    static func cleanName(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.")
        let kept = String(String.UnicodeScalarView(value.unicodeScalars.filter { allowed.contains($0) }).prefix(maxNameLength))
        return kept.isEmpty ? "unknown" : kept
    }

    /// A frame with home folders as `~`, runs of spaces (the padding
    /// `backtrace_symbols` adds) squeezed to one, other characters made
    /// printable ASCII, and capped; nil when nothing is left.
    static func cleanFrame(_ frame: String) -> String? {
        var text = frame.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        text = withoutHomeFolders(text).trimmingCharacters(in: .whitespaces)
        let cleaned = printable(text, limit: maxFrameLength)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Replaces `/Users/<name>` and `/home/<name>` with `~`. A frame names
    /// an image by path when it is loaded from inside a home folder (a build
    /// run from ~/Developer, say), and that path carries the person's name.
    static func withoutHomeFolders(_ text: String) -> String {
        text.replacingOccurrences(of: "(/Volumes/[^/]*)?/(Users|home)/[^/\\s]*", with: "~", options: .regularExpression)
    }

    /// Printable ASCII only (anything else becomes `?`), capped at `limit` characters.
    static func printable(_ value: String, limit: Int) -> String {
        String(String.UnicodeScalarView(value.unicodeScalars.prefix(limit).map { (0x20...0x7E).contains($0.value) ? $0 : "?" }))
    }
}
