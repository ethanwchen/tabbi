import Foundation

/// The small text file Tabbi's crash handler leaves on disk when the app
/// goes down, read on the next launch to build a `CrashReport`.
///
/// A signal handler may only call a few async-signal-safe functions, so it
/// cannot build JSON. It writes this plain format instead: the `header`
/// (prepared at launch, so it only copies bytes), a `kind` and a `name`
/// line, then for each thread a `thread` or `crashed-thread` line followed
/// by its frames, one per line, as `backtrace_symbols_fd` prints them.
///
///     tabbi-crash 1
///     version 1.4.0 (52)
///     macos 15.1.0
///     edition tabbi
///     kind signal
///     name SIGSEGV
///     crashed-thread com.apple.main-thread
///     0   Tabbi   0x0000000102a3c4e8 $s5Tabbi4mainyyF + 120
public enum CrashLog {
    public static let magic = "tabbi-crash 1"

    public enum Key {
        public static let version = "version"
        public static let macos = "macos"
        public static let edition = "edition"
        public static let kind = "kind"
        public static let name = "name"
        public static let thread = "thread"
        public static let crashedThread = "crashed-thread"
    }

    /// The lines the crash handler writes first, prepared once at launch.
    public static func header(for environment: DiagnosticEnvironment) -> String {
        """
        \(magic)
        \(Key.version) \(environment.appVersion)
        \(Key.macos) \(environment.systemVersion)
        \(Key.edition) \(environment.edition)

        """
    }

    /// The whole file for a crash the app can describe with Foundation (an
    /// uncaught exception or a hang), in the format the signal handler writes.
    public static func text(environment: DiagnosticEnvironment, kind: CrashReport.Kind, name: String, threads: [CrashReport.Thread]) -> String {
        var text = header(for: environment) + "\(Key.kind) \(kind.rawValue)\n\(Key.name) \(name)\n"
        for thread in threads {
            text += "\(thread.crashed ? Key.crashedThread : Key.thread) \(thread.name)\n"
            text += thread.frames.map { $0 + "\n" }.joined()
        }
        return text
    }

    /// The report a crash log describes, cleaned by `CrashReport`. Nil for a
    /// file that is not a crash log, has no known kind, or holds no frame
    /// (a handler that died halfway through).
    public static func report(from text: String) -> CrashReport? {
        var lines = text.split(whereSeparator: \.isNewline).map(String.init)[...]
        guard lines.popFirst() == magic else { return nil }
        var fields: [String: String] = [:]
        var threads: [(name: String, crashed: Bool, frames: [String])] = []
        for line in lines {
            let (key, value) = split(line)
            if key == Key.thread || key == Key.crashedThread {
                threads.append((value, key == Key.crashedThread, []))
            } else if !threads.isEmpty {
                threads[threads.count - 1].frames.append(line)
            } else if fields[key] == nil {
                fields[key] = value
            }
        }
        guard let kind = fields[Key.kind].flatMap(CrashReport.Kind.init(rawValue:)) else { return nil }
        let environment = DiagnosticEnvironment(
            appVersion: fields[Key.version] ?? "",
            systemVersion: fields[Key.macos] ?? "",
            edition: fields[Key.edition] ?? ""
        )
        return CrashReport(
            environment: environment,
            kind: kind,
            name: fields[Key.name] ?? "",
            threads: threads.map { CrashReport.Thread(name: $0.name, crashed: $0.crashed, frames: $0.frames) }
        )
    }

    private static func split(_ line: String) -> (key: String, value: String) {
        guard let space = line.firstIndex(of: " ") else { return (line, "") }
        return (String(line[..<space]), String(line[line.index(after: space)...]))
    }
}
