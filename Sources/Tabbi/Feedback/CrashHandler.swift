import Foundation
import TabbiKitCore

/// Leaves a small `CrashLog` on disk when Tabbi goes down, so the next
/// launch can offer to send it. Nothing leaves the Mac here: the log is
/// only read back by `takePendingReport()`, and sending it is the person's
/// choice.
///
/// Two paths write the log. An uncaught Objective-C exception is described
/// with Foundation (its name and call stack, never its reason). A fatal
/// signal (a crash or a Swift trap) runs in a signal handler, which may only
/// call async-signal-safe functions, so everything it needs (the file path,
/// the header bytes, the per-signal lines) is prepared in `install(in:environment:)`
/// and the handler only opens, copies bytes, `backtrace`s and re-raises,
/// so the system's own crash report still happens.
enum CrashHandler {
    /// The signals that end the app and that a report can explain.
    static let signals: [Int32] = [SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGTRAP, SIGFPE]

    /// The log a crash leaves, inside the edition's `Crash Reports` folder.
    static func logURL(in storage: EditionStorage) -> URL {
        storage.file("pending.crashlog", in: "Crash Reports")
    }

    /// Prepares the log's path and header and takes over the fatal signals
    /// and uncaught exceptions. Call once, early, in a live run.
    static func install(in storage: EditionStorage, environment: DiagnosticEnvironment) {
        guard !State.installed else { return }
        prepare(in: storage, environment: environment)
        installExceptionHandler()
        installSignalHandlers()
        State.installed = true
    }

    /// Creates the log's folder and prepares what the writers need, without
    /// taking over any signal. Internal so tests can write logs safely.
    static func prepare(in storage: EditionStorage, environment: DiagnosticEnvironment) {
        let url = logURL(in: storage)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        State.prepare(path: url.path, environment: environment)
    }

    /// The report a crash in an earlier run left, read once: the log is
    /// deleted whether or not it holds a usable report, so a crash is never
    /// offered twice.
    static func takePendingReport(in storage: EditionStorage) -> CrashReport? {
        let url = logURL(in: storage)
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return CrashLog.report(from: String(decoding: data, as: UTF8.self))
    }

    // MARK: Uncaught exceptions

    private static func installExceptionHandler() {
        State.previousExceptionHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler { exception in
            CrashHandler.writeExceptionLog(name: exception.name.rawValue, frames: exception.callStackSymbols)
            State.previousExceptionHandler?(exception)
        }
    }

    /// Writes the log for an uncaught exception and keeps the abort that
    /// follows from overwriting it. Internal so tests can check the file.
    static func writeExceptionLog(name: String, frames: [String]) {
        let thread = CrashReport.Thread(name: currentThreadName(), crashed: true, frames: frames)
        let text = CrashLog.text(environment: State.environment, kind: .exception, name: name, threads: [thread])
        guard FileManager.default.createFile(atPath: State.path, contents: Data(text.utf8)) else { return }
        State.logWritten.pointee = 1
    }

    private static func currentThreadName() -> String {
        if Thread.isMainThread { return mainThreadName }
        return Thread.current.name ?? ""
    }

    /// The main thread's name in a crash report, as Apple's reports call it.
    static let mainThreadName = "com.apple.main-thread"

    // MARK: Fatal signals

    private static func installSignalHandlers() {
        // A stack overflow leaves no stack to run the handler on, so it
        // gets one of its own.
        let size = Int(SIGSTKSZ) * 4
        var stack = stack_t(ss_sp: UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16), ss_size: size, ss_flags: 0)
        sigaltstack(&stack, nil)
        for signal in signals {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = crashSignalHandler
            action.sa_flags = SA_ONSTACK
            sigemptyset(&action.sa_mask)
            sigaction(signal, &action, nil)
        }
    }

    /// Writes the log for a fatal signal using only async-signal-safe calls.
    /// Internal so tests can call it without ending the process.
    static func writeSignalLog(_ signal: Int32) {
        guard State.logWritten.pointee == 0 else { return }
        State.logWritten.pointee = 1
        let fd = State.cPath.pointer.withMemoryRebound(to: CChar.self, capacity: State.cPath.count) {
            open($0, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        }
        guard fd >= 0 else { return }
        State.write(State.header, to: fd)
        State.write(State.signalLines(for: signal), to: fd)
        State.write(pthread_main_np() != 0 ? State.mainThreadLine : State.threadLine, to: fd)
        let count = backtrace(State.frames, Int32(CrashReport.maxFrames))
        backtrace_symbols_fd(State.frames, count, fd)
        close(fd)
    }

    /// Everything the signal handler reads, allocated before any crash.
    /// Static stored properties initialize lazily, so `prepare` touches each
    /// one before a handler can run.
    fileprivate enum State {
        nonisolated(unsafe) static var installed = false
        nonisolated(unsafe) static var environment = DiagnosticEnvironment(appVersion: "", systemVersion: "", edition: "")
        nonisolated(unsafe) static var path = ""
        nonisolated(unsafe) static var cPath = Bytes("")
        nonisolated(unsafe) static var header = Bytes("")
        nonisolated(unsafe) static var previousExceptionHandler: (@convention(c) (NSException) -> Void)?
        /// Set once a log is written, so the abort after an exception (or a
        /// second crashing thread) keeps the first, more telling log.
        nonisolated(unsafe) static let logWritten: UnsafeMutablePointer<sig_atomic_t> = {
            let flag = UnsafeMutablePointer<sig_atomic_t>.allocate(capacity: 1)
            flag.initialize(to: 0)
            return flag
        }()
        nonisolated(unsafe) static let frames = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: CrashReport.maxFrames)
        static let mainThreadLine = Bytes("\(CrashLog.Key.crashedThread) \(CrashHandler.mainThreadName)\n")
        static let threadLine = Bytes("\(CrashLog.Key.crashedThread) \n")
        static let sigsegv = signalLines("SIGSEGV")
        static let sigbus = signalLines("SIGBUS")
        static let sigill = signalLines("SIGILL")
        static let sigabrt = signalLines("SIGABRT")
        static let sigtrap = signalLines("SIGTRAP")
        static let sigfpe = signalLines("SIGFPE")
        static let unknownSignal = signalLines("unknown")

        static func prepare(path: String, environment: DiagnosticEnvironment) {
            self.environment = environment
            self.path = path
            cPath = Bytes(path, terminated: true)
            header = Bytes(CrashLog.header(for: environment))
            logWritten.pointee = 0
            _ = (frames, mainThreadLine, threadLine, sigsegv, sigbus, sigill, sigabrt, sigtrap, sigfpe, unknownSignal)
        }

        /// The kind and name lines for a signal, a plain switch so the
        /// handler neither hashes nor allocates.
        static func signalLines(for signal: Int32) -> Bytes {
            switch signal {
            case SIGSEGV: sigsegv
            case SIGBUS: sigbus
            case SIGILL: sigill
            case SIGABRT: sigabrt
            case SIGTRAP: sigtrap
            case SIGFPE: sigfpe
            default: unknownSignal
            }
        }

        static func write(_ bytes: Bytes, to fd: Int32) {
            _ = Darwin.write(fd, bytes.pointer, bytes.count)
        }

        private static func signalLines(_ name: String) -> Bytes {
            Bytes("\(CrashLog.Key.kind) \(CrashReport.Kind.signal.rawValue)\n\(CrashLog.Key.name) \(name)\n")
        }
    }

    /// A string copied into memory that is never freed, so a signal handler
    /// can write it without touching Swift's string machinery.
    /// Never written after `init`, so sharing it across threads is safe.
    fileprivate struct Bytes: @unchecked Sendable {
        let pointer: UnsafeMutablePointer<UInt8>
        let count: Int

        /// `terminated` adds a NUL, for a path handed to `open`.
        init(_ string: String, terminated: Bool = false) {
            let utf8 = Array(string.utf8) + (terminated ? [0] : [])
            count = utf8.count
            pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: max(count, 1))
            pointer.initialize(from: utf8, count: count)
        }
    }
}

/// The signal handler: a C function, so it captures nothing.
private func crashSignalHandler(_ signal: Int32) {
    CrashHandler.writeSignalLog(signal)
    // Back to the default action (SA_RESETHAND does not reset SIGILL or
    // SIGTRAP on macOS), so the re-raised signal ends the process and the
    // system writes its own report as usual.
    Darwin.signal(signal, SIG_DFL)
    raise(signal)
}
