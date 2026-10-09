import Foundation

/// Claude Code, Codex or Gemini CLI: the tool the user already signed in
/// to, run once per request with `AICommandLineFormat`'s arguments.
///
/// Discovery and the process are injected so tests replay recorded output;
/// the app uses `AIExecutableLocator` and `StreamingProcess`.
public struct AICommandLineProvider: AIProvider {
    /// One process run: stdout lines, finishing on exit and throwing
    /// `ProcessFailure` on a non-zero status.
    public struct Run: Sendable {
        public var executable: URL
        public var arguments: [String]
        public var input: Data?
        public var workingDirectory: URL
        public var environment: [String: String]
    }

    public typealias Runner = @Sendable (Run) -> AsyncThrowingStream<String, Error>
    public typealias Locator = @Sendable () -> URL?

    public let id: AIProviderID
    private let locate: Locator
    private let runner: Runner
    private let workingDirectory: URL

    /// `workingDirectory` stays the same across runs because Claude Code
    /// and Gemini CLI keep sessions per folder, and a chat resumes there.
    public init(
        id: AIProviderID,
        locate: Locator? = nil,
        workingDirectory: URL = FileManager.default.temporaryDirectory,
        runner: @escaping Runner = AICommandLineProvider.process
    ) {
        guard case .cli(let executable) = id.transport else {
            preconditionFailure("\(id) is not a command line tool")
        }
        self.id = id
        self.locate = locate ?? { AIExecutableLocator.locate(executable) }
        self.workingDirectory = workingDirectory
        self.runner = runner
    }

    public func stream(_ request: AIRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        let (id, locate, runner, workingDirectory) = (id, locate, runner, workingDirectory)
        return AsyncThrowingStream { continuation in
            let task = Task {
                var imageFolder: URL?
                defer { imageFolder.map { try? FileManager.default.removeItem(at: $0) } }
                do {
                    guard let executable = locate() else { throw AIProviderError.notInstalled }
                    var imagePaths: [String] = []
                    let images = request.messages.last?.images ?? []
                    if id != .claudeCLI, !images.isEmpty {
                        let name = "tabbi-images-\(UUID().uuidString)"
                        let folder = workingDirectory.appendingPathComponent(name, isDirectory: true)
                        imageFolder = folder
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        for (index, image) in images.enumerated() {
                            let file = "image-\(index + 1).png"
                            try image.write(to: folder.appendingPathComponent(file))
                            imagePaths.append("\(name)/\(file)")
                        }
                    }
                    let invocation = try AICommandLineFormat.invocation(for: id, request, imagePaths: imagePaths)
                    let lines = runner(Run(
                        executable: executable,
                        arguments: invocation.arguments,
                        input: invocation.input,
                        workingDirectory: workingDirectory,
                        environment: AIExecutableLocator.environment(running: executable)
                    ))
                    var finished = false
                    do {
                        for try await line in lines {
                            for event in try AICommandLineFormat.events(fromLine: line, provider: id) where !finished {
                                if case .finished = event { finished = true }
                                continuation.yield(event)
                            }
                        }
                    } catch is ProcessFailure where finished {
                        // A complete answer followed by a non-zero exit still counts.
                    }
                    if !finished { continuation.yield(.finished(text: nil)) }
                    continuation.finish()
                } catch let failure as ProcessFailure {
                    continuation.finish(throwing: AIProviderError.service(detail: Self.detail(failure, provider: id)))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The last line of the tool's error output, which is where they put
    /// the reason, or a plain sentence when it printed nothing.
    static func detail(_ failure: ProcessFailure, provider: AIProviderID) -> String {
        let last = failure.stderr.split(whereSeparator: \.isNewline).last.map(String.init)?
            .trimmingCharacters(in: .whitespaces)
        guard let last, !last.isEmpty else {
            return "\(provider.displayName) stopped with status \(failure.status)."
        }
        return last
    }

    /// Runs the tool with `StreamingProcess`.
    public static let process: Runner = { run in
        StreamingProcess.lines(
            executable: run.executable,
            arguments: run.arguments,
            currentDirectory: run.workingDirectory,
            environment: run.environment,
            input: run.input
        )
    }
}
