import XCTest
@testable import TabbiKitCore

final class AIExecutableLocatorTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("locator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeExecutable(_ name: String) throws -> String {
        let path = folder.appendingPathComponent(name).path
        FileManager.default.createFile(atPath: path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        return path
    }

    func testEachToolHasItsOwnOverrideVariable() {
        XCTAssertEqual(AIExecutableLocator.overrideVariable(for: "claude"), ClaudeCLI.overrideVariable)
        XCTAssertEqual(AIExecutableLocator.overrideVariable(for: "codex"), "TABBI_CODEX_PATH")
        XCTAssertEqual(AIExecutableLocator.overrideVariable(for: "gemini"), "TABBI_GEMINI_PATH")
    }

    func testOverridesWinAndBrokenOnesFallThroughToTheShell() throws {
        let codex = try makeExecutable("codex")
        let found = AIExecutableLocator.locate("codex", environment: ["TABBI_CODEX_PATH": codex], loginShellLookup: { _ in nil })
        XCTAssertEqual(found?.path, codex)

        let gemini = try makeExecutable("gemini")
        var asked: [String] = []
        let fallback = AIExecutableLocator.locate(
            "gemini",
            pathOverride: "/nowhere/gemini",
            environment: [:],
            loginShellLookup: { asked.append($0); return gemini }
        )
        XCTAssertEqual(fallback?.path, gemini)
        XCTAssertEqual(asked, ["gemini"])
    }

    func testCandidatesCoverTheUsualInstallers() {
        let paths = AIExecutableLocator.candidatePaths(for: "codex", home: "/Users/a")
        XCTAssertTrue(paths.contains("/opt/homebrew/bin/codex"))
        XCTAssertTrue(paths.contains("/Users/a/.volta/bin/codex"))
        XCTAssertFalse(paths.contains { $0.contains(".claude/local") })
        XCTAssertTrue(AIExecutableLocator.candidatePaths(for: "claude", home: "/Users/a").contains("/Users/a/.claude/local/claude"))
    }

    func testEnvironmentPutsTheToolsFolderOnPathOnce() {
        let environment = AIExecutableLocator.environment(
            running: URL(fileURLWithPath: "/Users/a/.volta/bin/gemini"),
            base: ["PATH": "/usr/bin:/opt/homebrew/bin", "HOME": "/Users/a"]
        )
        XCTAssertEqual(environment["PATH"], "/Users/a/.volta/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")
        XCTAssertEqual(environment["HOME"], "/Users/a")
    }
}

final class AICommandLineFormatTests: XCTestCase {
    private func chat(resume: String? = nil) -> AIRequest {
        AIRequest(
            system: "Be brief.",
            messages: [.user("What is 2+2?"), .assistant("4."), .user("-and times 3?")],
            resumeSessionID: resume
        )
    }

    func testClaudeSendsTheQuestionOnStdinWithNoTools() throws {
        let invocation = try AICommandLineFormat.invocation(for: .claudeCLI, chat(resume: "s1"))
        let arguments = invocation.arguments
        XCTAssertEqual(Array(arguments.prefix(1)), ["-p"])
        XCTAssertTrue(arguments.contains("--strict-mcp-config"))
        XCTAssertEqual(arguments[try XCTUnwrap(arguments.firstIndex(of: "--tools")) + 1], "")
        XCTAssertEqual(arguments[try XCTUnwrap(arguments.firstIndex(of: "--model")) + 1], "sonnet")
        XCTAssertEqual(arguments[try XCTUnwrap(arguments.firstIndex(of: "--resume")) + 1], "s1")
        XCTAssertEqual(arguments[try XCTUnwrap(arguments.firstIndex(of: "--system-prompt")) + 1], "Be brief.")
        let input = try XCTUnwrap(invocation.input.flatMap { String(data: $0, encoding: .utf8) })
        // Resuming sends only the new question.
        XCTAssertTrue(input.contains("-and times 3?"))
        XCTAssertFalse(input.contains("What is 2+2?"))
    }

    func testPlanMyDayHandsClaudeItsSchemaAndOtherToolsOnlyThePrompt() throws {
        let request = DayPlanner.request(prompt: "Plan my day")
        XCTAssertEqual(request.responseSchema, DayPlanner.jsonSchema)
        let claude = try AICommandLineFormat.invocation(for: .claudeCLI, request).arguments
        XCTAssertEqual(claude[try XCTUnwrap(claude.firstIndex(of: "--json-schema")) + 1], DayPlanner.jsonSchema)
        XCTAssertFalse(try AICommandLineFormat.invocation(for: .claudeCLI, .prompt("Hi")).arguments.contains("--json-schema"))
        XCTAssertFalse(try AICommandLineFormat.invocation(for: .codexCLI, request).arguments.contains("--json-schema"))
        XCTAssertFalse(try AICommandLineFormat.invocation(for: .geminiCLI, request).arguments.contains("--json-schema"))
    }

    func testANewRunOfAChatWritesOutTheHistory() {
        let prompt = AICommandLineFormat.prompt(for: chat())
        XCTAssertTrue(prompt.contains("User: What is 2+2?\n\nAssistant: 4."))
        XCTAssertTrue(prompt.hasSuffix("-and times 3?"))
        XCTAssertEqual(AICommandLineFormat.prompt(for: .prompt("Hi")), "Hi")
    }

    func testCodexRunsReadOnlyAndKeepsThePromptOutOfFlagParsing() throws {
        let invocation = try AICommandLineFormat.invocation(
            for: .codexCLI,
            AIRequest(system: "Be brief.", messages: [.user("-v")], model: "gpt-5", resumeSessionID: "t1"),
            imagePaths: ["run/image-1.png"]
        )
        XCTAssertEqual(invocation.arguments, [
            "exec", "--json", "--skip-git-repo-check", "--sandbox", "read-only",
            "--model", "gpt-5", "--image=run/image-1.png", "resume", "t1", "--", "-v",
        ])
        XCTAssertNil(invocation.input)
    }

    func testCodexPutsInstructionsInFrontOfANewRun() throws {
        let invocation = try AICommandLineFormat.invocation(for: .codexCLI, AIRequest(system: "Be brief.", messages: [.user("Hi")]))
        XCTAssertEqual(invocation.arguments.last, "Be brief.\n\nHi")
        XCTAssertFalse(invocation.arguments.contains("--model"), "the CLI's own default follows the user's plan")
    }

    func testGeminiAttachesImagesByReference() throws {
        let invocation = try AICommandLineFormat.invocation(
            for: .geminiCLI,
            AIRequest(messages: [.user("What is this?")], resumeSessionID: "g1"),
            imagePaths: ["run/image-1.png"]
        )
        XCTAssertEqual(invocation.arguments, [
            "--output-format", "stream-json", "--resume", "g1", "--prompt=@run/image-1.png What is this?",
        ])
    }

    func testClaudeEvents() throws {
        XCTAssertEqual(try AICommandLineFormat.events(fromLine: #"{"type":"system","subtype":"init","session_id":"s1"}"#, provider: .claudeCLI), [.sessionStarted("s1")])
        XCTAssertEqual(try AICommandLineFormat.events(fromLine: #"{"type":"result","subtype":"success","result":"4","session_id":"s1","is_error":false}"#, provider: .claudeCLI), [.finished(text: "4")])
        XCTAssertThrowsError(try AICommandLineFormat.events(fromLine: #"{"type":"result","result":"Not logged in","is_error":true}"#, provider: .claudeCLI)) {
            XCTAssertEqual($0 as? AIProviderError, .service(detail: "Not logged in"))
        }
    }

    func testCodexEvents() throws {
        let lines = [
            #"{"type":"thread.started","thread_id":"t1"}"#,
            #"{"type":"turn.started"}"#,
            #"{"type":"item.completed","item":{"id":"item_0","type":"reasoning","text":"thinking"}}"#,
            #"{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"4."}}"#,
            #"{"type":"turn.completed","usage":{"input_tokens":10}}"#,
        ]
        let events = try lines.flatMap { try AICommandLineFormat.events(fromLine: $0, provider: .codexCLI) }
        XCTAssertEqual(events, [.sessionStarted("t1"), .textDelta("4."), .finished(text: nil)])
        XCTAssertThrowsError(try AICommandLineFormat.events(fromLine: #"{"type":"turn.failed","error":{"message":"usage limit"}}"#, provider: .codexCLI)) {
            XCTAssertEqual($0 as? AIProviderError, .service(detail: "usage limit"))
        }
    }

    func testGeminiEvents() throws {
        let lines = [
            #"{"type":"init","session_id":"g1","model":"gemini-2.5-flash"}"#,
            #"{"type":"message","role":"user","content":"Hi"}"#,
            #"{"type":"message","role":"assistant","content":"Hel","delta":true}"#,
            #"{"type":"message","role":"assistant","content":"lo","delta":true}"#,
            #"{"type":"error","severity":"warning","message":"slow"}"#,
            #"{"type":"result","status":"success","stats":{}}"#,
            "not json",
        ]
        let events = try lines.flatMap { try AICommandLineFormat.events(fromLine: $0, provider: .geminiCLI) }
        XCTAssertEqual(events, [.sessionStarted("g1"), .textDelta("Hel"), .textDelta("lo"), .finished(text: nil)])
        XCTAssertThrowsError(try AICommandLineFormat.events(fromLine: #"{"type":"result","status":"error","error":{"message":"quota"}}"#, provider: .geminiCLI)) {
            XCTAssertEqual($0 as? AIProviderError, .service(detail: "quota"))
        }
    }
}

final class AICommandLineProviderTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        var runs: [AICommandLineProvider.Run] = []
        var imagesSeen: [Data] = []
    }

    private func replay(_ lines: [String], failure: Error? = nil, recorder: Recorder? = nil) -> AICommandLineProvider.Runner {
        { run in
            recorder?.runs.append(run)
            for argument in run.arguments where argument.hasPrefix("--prompt=@") || argument.hasSuffix(".png") {
                let path = argument.hasPrefix("--prompt=@")
                    ? String(argument.dropFirst("--prompt=@".count).split(separator: " ")[0])
                    : argument
                if let data = FileManager.default.contents(atPath: run.workingDirectory.appendingPathComponent(path).path) {
                    recorder?.imagesSeen.append(data)
                }
            }
            return AsyncThrowingStream { continuation in
                lines.forEach { continuation.yield($0) }
                continuation.finish(throwing: failure)
            }
        }
    }

    private static let executable = URL(fileURLWithPath: "/opt/homebrew/bin/tool")

    func testAMissingToolSaysItIsNotInstalled() async {
        let provider = AICommandLineProvider(id: .codexCLI, locate: { nil }, runner: replay([]))
        do {
            _ = try await provider.answer(.prompt("Hi"))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? AIProviderError, .notInstalled)
        }
    }

    func testCodexAnswerRunsInTheWorkingFolderWithNodeOnPath() async throws {
        let recorder = Recorder()
        let folder = FileManager.default.temporaryDirectory
        let provider = AICommandLineProvider(
            id: .codexCLI,
            locate: { Self.executable },
            workingDirectory: folder,
            runner: replay([
                #"{"type":"thread.started","thread_id":"t1"}"#,
                #"{"type":"item.completed","item":{"type":"agent_message","text":"Four."}}"#,
                #"{"type":"turn.completed"}"#,
            ], recorder: recorder)
        )
        let answer = try await provider.answer(.prompt("2+2?"))
        XCTAssertEqual(answer, "Four.")
        let run = try XCTUnwrap(recorder.runs.first)
        XCTAssertEqual(run.executable, Self.executable)
        XCTAssertEqual(run.workingDirectory, folder)
        XCTAssertTrue(run.environment["PATH"]?.hasPrefix("/opt/homebrew/bin:") == true)
    }

    func testCodexAndGeminiRunInAnEmptyFolderOfTheirOwn() async throws {
        let temporary = FileManager.default.temporaryDirectory
        XCTAssertEqual(AICommandLineProvider.defaultWorkingDirectory(for: .claudeCLI), temporary)
        let codex = AICommandLineProvider.defaultWorkingDirectory(for: .codexCLI)
        let gemini = AICommandLineProvider.defaultWorkingDirectory(for: .geminiCLI)
        XCTAssertNotEqual(codex, gemini)
        XCTAssertEqual(codex.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL, temporary.standardizedFileURL)

        let recorder = Recorder()
        let provider = AICommandLineProvider(
            id: .geminiCLI,
            locate: { Self.executable },
            runner: replay([#"{"type":"result","status":"success"}"#], recorder: recorder)
        )
        _ = try await provider.answer(.prompt("Hi"))
        let run = try XCTUnwrap(recorder.runs.first)
        XCTAssertEqual(run.workingDirectory, gemini)
        var isFolder: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: gemini.path, isDirectory: &isFolder) && isFolder.boolValue)
    }

    func testImagesAreWrittenForTheRunAndRemovedAfter() async throws {
        let recorder = Recorder()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let provider = AICommandLineProvider(
            id: .geminiCLI,
            locate: { Self.executable },
            workingDirectory: folder,
            runner: replay([#"{"type":"result","status":"success"}"#], recorder: recorder)
        )
        _ = try await provider.answer(AIRequest(messages: [.user("What is this?", images: [png])]))
        XCTAssertEqual(recorder.imagesSeen, [png])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
    }

    func testAFailedExitReportsTheLastErrorLine() async {
        let provider = AICommandLineProvider(
            id: .geminiCLI,
            locate: { Self.executable },
            runner: replay([], failure: ProcessFailure(status: 1, stderr: "Loading...\nPlease set an Auth method"))
        )
        do {
            _ = try await provider.answer(.prompt("Hi"))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? AIProviderError, .service(detail: "Please set an Auth method"))
        }
    }

    func testACompleteAnswerSurvivesANonZeroExit() async throws {
        let provider = AICommandLineProvider(
            id: .claudeCLI,
            locate: { Self.executable },
            runner: replay(
                [#"{"type":"result","subtype":"success","result":"Done","is_error":false}"#],
                failure: ProcessFailure(status: 1, stderr: "")
            )
        )
        let answer = try await provider.answer(.prompt("Hi"))
        XCTAssertEqual(answer, "Done")
    }

    func testStreamEndsWithExactlyOneFinished() async throws {
        let provider = AICommandLineProvider(
            id: .geminiCLI,
            locate: { Self.executable },
            runner: replay([#"{"type":"message","role":"assistant","content":"Hi"}"#])
        )
        var events: [AIStreamEvent] = []
        for try await event in provider.stream(.prompt("Hi")) { events.append(event) }
        XCTAssertEqual(events, [.textDelta("Hi"), .finished(text: nil)])
    }
}
