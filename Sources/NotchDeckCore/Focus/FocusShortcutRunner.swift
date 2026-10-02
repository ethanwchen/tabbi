import Foundation

/// How running a shortcut went, phrased for the Settings Test button.
public enum FocusShortcutResult: Equatable, Sendable {
    case succeeded
    /// No shortcut has this name.
    case notFound(name: String)
    /// The `shortcuts` command isn't available (it ships with macOS 12+).
    case unavailable
    /// The shortcut didn't finish within the runner's timeout.
    case timedOut
    /// The shortcut ran and failed; `message` is the tool's own explanation.
    case failed(message: String)

    public var succeeded: Bool { self == .succeeded }

    /// One short sentence for the user.
    public var message: String {
        switch self {
        case .succeeded: "Shortcut ran."
        case .notFound(let name): "No shortcut named \u{201C}\(name)\u{201D}. Check the name in Shortcuts."
        case .unavailable: "The Shortcuts command line tool isn't available on this Mac."
        case .timedOut: "The shortcut took too long and was stopped."
        case .failed(let message): message.isEmpty ? "The shortcut failed." : message
        }
    }

    /// Classifies a finished `shortcuts run` by exit status and stderr.
    public static func classify(status: Int32, stderr: String, name: String) -> FocusShortcutResult {
        guard status != 0 else { return .succeeded }
        let text = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        // "Error: The operation couldn’t be completed. Couldn’t find shortcut"
        if text.localizedCaseInsensitiveContains("find shortcut") { return .notFound(name: name) }
        let message = text.hasPrefix("Error: ") ? String(text.dropFirst("Error: ".count)) : text
        return .failed(message: message)
    }
}

/// Runs a named Shortcuts shortcut with `/usr/bin/shortcuts run`.
///
/// macOS has no public API for Do Not Disturb, but the Shortcuts "Set Focus"
/// action can toggle it, so focus mode runs user-made shortcuts instead.
/// Never throws: every outcome is a `FocusShortcutResult`, so a missing or
/// broken shortcut can't interrupt a focus session.
public struct FocusShortcutRunner: Sendable {
    public static let systemExecutable = URL(fileURLWithPath: "/usr/bin/shortcuts")

    public var executable: URL
    public var timeout: Duration

    public init(executable: URL = FocusShortcutRunner.systemExecutable, timeout: Duration = .seconds(15)) {
        self.executable = executable
        self.timeout = timeout
    }

    /// Runs `name` and waits for it to finish (or time out). Blank names
    /// count as not found without launching anything.
    public func run(_ name: String) async -> FocusShortcutResult {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .notFound(name: name) }
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { return .unavailable }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["run", name]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let stderr = Pipe()
        process.standardError = stderr

        let box = ProcessBox(process)
        let once = ResumeOnce()
        let timer = Task {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            if once.resume(false) { box.terminate() }
        }
        let finished: Bool = await withCheckedContinuation { continuation in
            once.arm(continuation)
            process.terminationHandler = { _ in once.resume(true) }
            do {
                try process.run()
            } catch {
                once.resume(false)
            }
        }
        timer.cancel()
        guard finished else {
            // The timer can fire before `run()` launched the process; the
            // closure above has finished by now, so stop it here too.
            box.terminate()
            return box.didLaunch ? .timedOut : .unavailable
        }
        let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return FocusShortcutResult.classify(status: process.terminationStatus, stderr: message, name: name)
    }
}

/// Lets the timeout task stop a process it doesn't own.
private final class ProcessBox: @unchecked Sendable {
    private let process: Process

    init(_ process: Process) { self.process = process }

    var didLaunch: Bool { process.processIdentifier != 0 }

    func terminate() {
        if process.isRunning { process.terminate() }
    }
}

/// Resumes a continuation exactly once, whichever of exit, launch failure
/// or timeout happens first.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    /// A result that arrived before `arm`, delivered as soon as it's armed.
    private var early: Bool?
    private var isDone = false

    func arm(_ continuation: CheckedContinuation<Bool, Never>) {
        lock.lock()
        if let early {
            lock.unlock()
            continuation.resume(returning: early)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    /// Returns true if this call did the resuming.
    @discardableResult
    func resume(_ value: Bool) -> Bool {
        lock.lock()
        guard !isDone else {
            lock.unlock()
            return false
        }
        isDone = true
        let pending = continuation
        continuation = nil
        if pending == nil { early = value }
        lock.unlock()
        pending?.resume(returning: value)
        return true
    }
}
