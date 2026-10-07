import Foundation

public struct ProcessFailure: Error, Equatable, CustomStringConvertible {
    public var status: Int32
    public var stderr: String

    public var description: String {
        stderr.isEmpty ? "process exited with status \(status)" : stderr
    }
}

/// Runs a subprocess and streams its stdout line by line.
public enum StreamingProcess {
    /// Yields each stdout line (without the newline). Finishes when the process
    /// exits; throws `ProcessFailure` on a non-zero exit. Cancelling the
    /// consumer terminates the process. `input`, when given, is written to
    /// the process's stdin, which is then closed.
    public static func lines(
        executable: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil,
        input: Data? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            if let currentDirectory { process.currentDirectoryURL = currentDirectory }
            if let environment { process.environment = environment }

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            let stdin = input.map { _ in Pipe() }
            process.standardInput = stdin ?? FileHandle.nullDevice

            let buffer = LineBuffer()
            // Finishes once stdout reaches its end and the process has
            // exited, in either order: finishing on exit alone could drop
            // lines the reader took just before it.
            let done = DispatchGroup()
            done.enter()
            done.enter()
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    done.leave()
                    return
                }
                for line in buffer.append(data) { continuation.yield(line) }
            }
            process.terminationHandler = { _ in done.leave() }
            done.notify(queue: .global(qos: .userInitiated)) {
                if let last = buffer.flush() { continuation.yield(last) }

                if process.terminationReason == .exit && process.terminationStatus == 0 {
                    continuation.finish()
                } else {
                    let message = String(
                        data: stderr.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    ) ?? ""
                    continuation.finish(throwing: ProcessFailure(
                        status: process.terminationStatus,
                        stderr: message.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                }
            }

            continuation.onTermination = { termination in
                if case .cancelled = termination, process.isRunning { process.terminate() }
            }

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: error)
                return
            }
            if let input, let writer = stdin?.fileHandleForWriting {
                // A process that exits before reading everything must not
                // kill the app with SIGPIPE; the write just fails instead.
                _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
                // Off the caller's thread: a large input blocks until read.
                DispatchQueue.global(qos: .userInitiated).async {
                    try? writer.write(contentsOf: input)
                    try? writer.close()
                }
            }
        }
    }
}

/// Splits a byte stream into UTF-8 lines. Thread-safe.
final class LineBuffer: @unchecked Sendable {
    private var pending = Data()
    private let lock = NSLock()

    func append(_ data: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        pending.append(data)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = pending[pending.startIndex..<newline]
            pending.removeSubrange(pending.startIndex...newline)
            lines.append(String(decoding: lineData, as: UTF8.self))
        }
        return lines
    }

    func flush() -> String? {
        lock.lock(); defer { lock.unlock() }
        guard !pending.isEmpty else { return nil }
        defer { pending.removeAll() }
        return String(decoding: pending, as: UTF8.self)
    }
}
