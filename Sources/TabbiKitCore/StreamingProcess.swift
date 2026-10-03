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
    /// consumer terminates the process.
    public static func lines(
        executable: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil
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
            process.standardInput = FileHandle.nullDevice

            let buffer = LineBuffer()
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                for line in buffer.append(data) { continuation.yield(line) }
            }

            process.terminationHandler = { process in
                stdout.fileHandleForReading.readabilityHandler = nil
                let rest = stdout.fileHandleForReading.readDataToEndOfFile()
                for line in buffer.append(rest) { continuation.yield(line) }
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
