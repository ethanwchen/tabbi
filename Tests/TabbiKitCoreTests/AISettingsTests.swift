import XCTest
import TabbiKitCore

final class AISettingsTests: XCTestCase {
    func testNothingIsActiveUntilTheUserPicks() {
        XCTAssertNil(AISettings().activeProvider(sandboxed: false))
        XCTAssertEqual(AISettings(provider: .gemini, consented: [.gemini]).activeProvider(sandboxed: true), .gemini)
    }

    func testAProviderThatSendsDataOffTheMacWaitsForPermission() {
        var settings = AISettings(provider: .anthropic)
        XCTAssertTrue(settings.needsConsent(for: .anthropic))
        XCTAssertNil(settings.activeProvider(sandboxed: false), "a pick without permission sends nothing")
        settings.choose(.anthropic)
        XCTAssertEqual(settings.activeProvider(sandboxed: false), .anthropic)
        XCTAssertFalse(settings.needsConsent(for: .anthropic))
        settings.choose(nil)
        settings.choose(.anthropic)
        XCTAssertEqual(settings.activeProvider(sandboxed: false), .anthropic, "asked only once per provider")
        XCTAssertTrue(settings.needsConsent(for: .openAI), "permission is per provider")
    }

    func testOllamaRunsOnTheMacAndNeedsNoPermission() {
        let settings = AISettings(provider: .ollama)
        XCTAssertFalse(settings.needsConsent(for: .ollama))
        XCTAssertEqual(settings.activeProvider(sandboxed: true), .ollama)
        var chosen = AISettings()
        chosen.choose(.ollama)
        XCTAssertEqual(chosen.consented, [], "nothing to allow")
    }

    func testTheDisclosureNamesTheReceiverAndWhatIsSent() {
        for provider in AIProviderID.allCases where provider.sendsDataOffMac {
            guard let vendor = provider.vendorName else { return XCTFail("\(provider) names no receiver") }
            XCTAssertTrue(provider.consentTitle.contains(vendor))
            let message = provider.consentMessage(appName: "Tabbi")
            for detail in [provider.displayName, vendor, "questions", "screenshot", "calendar event titles",
                           "study minutes", "terms and privacy policy", "None"] {
                XCTAssertTrue(message.contains(detail), "\(provider): \(detail)")
            }
        }
        XCTAssertNil(AIProviderID.ollama.vendorName)
    }

    func testTheSandboxCannotRunACommandLineTool() {
        let settings = AISettings(provider: .claudeCLI, consented: [.claudeCLI])
        XCTAssertEqual(settings.activeProvider(sandboxed: false), .claudeCLI)
        XCTAssertNil(settings.activeProvider(sandboxed: true))
    }

    func testModelsFallBackToTheDefaultAndDefaultsAreNotStored() {
        var settings = AISettings()
        XCTAssertEqual(settings.model(for: .ollama), "llama3.2")
        settings.setModel("  qwen3 ", for: .ollama)
        XCTAssertEqual(settings.model(for: .ollama), "qwen3")
        settings.setModel("llama3.2", for: .ollama)
        XCTAssertEqual(settings.models, [:], "picking the default again follows later default changes")
        settings.setModel("gpt-5", for: .openAI)
        settings.setModel(" ", for: .openAI)
        XCTAssertEqual(settings.models, [:])
    }

    func testSetupPagesAreOfficialHTTPSPages() {
        XCTAssertEqual(AIProviderID.gemini.setupPage.host(), "aistudio.google.com")
        XCTAssertEqual(AIProviderID.ollama.setupPage.host(), "ollama.com")
        for id in AIProviderID.allCases {
            XCTAssertEqual(id.setupPage.scheme, "https", "\(id)")
            XCTAssertEqual(id.setupPageTitle, id.requiresAPIKey ? "Get a Key" : "Install")
        }
    }

    func testSetupHintsCoverEveryProviderWithoutAKey() {
        for id in AIProviderID.allCases {
            XCTAssertEqual(id.setupHint(model: "m") == nil, id.requiresAPIKey, "\(id)")
        }
        XCTAssertEqual(AIProviderID.ollama.setupHint(model: AISettings().model(for: .ollama)),
                       "With Ollama open, run ollama pull llama3.2 in Terminal once.")
    }

    func testInMemoryKeysTrimAndBlankDeletes() {
        let keys = InMemoryAIKeyStore([.openAI: "  sk-1\n"])
        XCTAssertEqual(keys.key(for: .openAI), "sk-1")
        keys.setKey("   ", for: .openAI)
        XCTAssertFalse(keys.hasKey(for: .openAI))
    }
}

final class AIProviderFactoryTests: XCTestCase {
    private final class Captured: @unchecked Sendable {
        var requests: [URLRequest] = []
        var runs: [AICommandLineProvider.Run] = []
    }

    private func factory(keys: InMemoryAIKeyStore = InMemoryAIKeyStore(), sandboxed: Bool = false,
                         captured: Captured = Captured()) -> AIProviderFactory {
        AIProviderFactory(
            keys: keys,
            sandboxed: sandboxed,
            locate: { _ in URL(fileURLWithPath: "/opt/homebrew/bin/tool") },
            transport: { request in
                captured.requests.append(request)
                return AIHTTPResponse(status: 200, lines: AsyncThrowingStream { $0.finish() })
            },
            runner: { run in
                captured.runs.append(run)
                return AsyncThrowingStream { continuation in
                    continuation.yield(#"{"type":"result","subtype":"success","is_error":false,"result":"Hi."}"#)
                    continuation.finish()
                }
            }
        )
    }

    private func body(_ request: URLRequest?) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request?.httpBody)) as? [String: Any])
    }

    func testSetupStateFollowsTheChoiceAndTheKey() {
        let keys = InMemoryAIKeyStore()
        let factory = factory(keys: keys)
        XCTAssertEqual(factory.setupState(for: AISettings()), .notChosen)
        XCTAssertEqual(factory.setupState(for: AISettings(provider: .anthropic, consented: [.anthropic])), .needsKey(.anthropic))
        keys.setKey("sk-ant", for: .anthropic)
        XCTAssertEqual(factory.setupState(for: AISettings(provider: .anthropic, consented: [.anthropic])), .ready(.anthropic))
        XCTAssertEqual(factory.setupState(for: AISettings(provider: .ollama)), .ready(.ollama), "Ollama needs no key")
        XCTAssertEqual(factory.setupState(for: AISettings(provider: .codexCLI, consented: [.codexCLI])), .ready(.codexCLI))
    }

    func testTheSandboxedBuildOffersNoCLIAndDoesNotRunOne() {
        let factory = factory(sandboxed: true)
        XCTAssertEqual(factory.availableProviders, [.anthropic, .openAI, .gemini, .ollama])
        XCTAssertEqual(factory.setupState(for: AISettings(provider: .claudeCLI, consented: [.claudeCLI])), .notChosen)
        XCTAssertNil(factory.provider(for: AISettings(provider: .claudeCLI, consented: [.claudeCLI])))
    }

    func testNoProviderMeansNothingCanBeSent() {
        XCTAssertNil(factory().provider(for: AISettings()))
    }

    func testAPIProviderSendsTheSavedKeyAndTheUsersModel() async throws {
        let captured = Captured()
        var settings = AISettings(provider: .anthropic, consented: [.anthropic])
        settings.setModel("claude-haiku-4-5", for: .anthropic)
        let provider = try XCTUnwrap(factory(keys: InMemoryAIKeyStore([.anthropic: "sk-ant"]), captured: captured)
            .provider(for: settings))
        XCTAssertEqual(provider.id, .anthropic)
        _ = try await provider.answer(.prompt("Hi"))
        _ = try await provider.answer(.prompt("Hi", model: "claude-opus-5-5"))
        XCTAssertEqual(captured.requests.first?.value(forHTTPHeaderField: "x-api-key"), "sk-ant")
        XCTAssertEqual(try body(captured.requests.first)["model"] as? String, "claude-haiku-4-5")
        XCTAssertEqual(try body(captured.requests.last)["model"] as? String, "claude-opus-5-5",
                       "a request that names a model keeps it")
    }

    func testAMissingKeyFailsWithASetupError() async throws {
        let provider = try XCTUnwrap(factory().provider(for: AISettings(provider: .gemini, consented: [.gemini])))
        do {
            _ = try await provider.answer(.prompt("Hi"))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? AIProviderError, .missingAPIKey)
        }
    }

    func testOllamaGoesToLocalhostWithTheDefaultModel() async throws {
        let captured = Captured()
        let provider = try XCTUnwrap(factory(captured: captured).provider(for: AISettings(provider: .ollama)))
        _ = try await provider.answer(.prompt("Hi"))
        XCTAssertEqual(captured.requests.first?.url?.host, "localhost")
        XCTAssertEqual(try body(captured.requests.first)["model"] as? String, "llama3.2")
    }

    func testCommandLineProviderRunsTheLocatedToolWithTheModel() async throws {
        let captured = Captured()
        let provider = try XCTUnwrap(factory(captured: captured).provider(for: AISettings(provider: .claudeCLI, consented: [.claudeCLI])))
        let answer = try await provider.answer(.prompt("Hi"))
        XCTAssertEqual(answer, "Hi.")
        let run = try XCTUnwrap(captured.runs.first)
        XCTAssertEqual(run.executable.path, "/opt/homebrew/bin/tool")
        let model = try XCTUnwrap(run.arguments.firstIndex(of: "--model"))
        XCTAssertEqual(run.arguments[model + 1], "sonnet")
    }
}

final class AISettingsStorageTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "TabbiTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testAFreshInstallHasNoProvider() {
        XCTAssertNil(SettingsRepository(defaults: defaults).load().ai.provider)
    }

    func testProviderAndModelsRoundTrip() {
        let repository = SettingsRepository(defaults: defaults)
        var settings = repository.load()
        settings.ai.choose(.gemini)
        settings.ai.setModel("gemini-pro-latest", for: .gemini)
        repository.save(settings)
        let loaded = SettingsRepository(defaults: defaults).load()
        XCTAssertEqual(loaded.ai, settings.ai)

        var cleared = loaded
        cleared.ai = AISettings()
        repository.save(cleared)
        XCTAssertEqual(SettingsRepository(defaults: defaults).load().ai, AISettings())
    }

    func testUnknownStoredValuesAreIgnored() {
        defaults.set("someday-ai", forKey: "settings.ai.provider")
        defaults.set(["someday-ai": "x", "ollama": "qwen3"], forKey: "settings.ai.models")
        let ai = SettingsRepository(defaults: defaults).load().ai
        XCTAssertNil(ai.provider)
        XCTAssertEqual(ai.models, [.ollama: "qwen3"])
    }

    func testVersionSixUsersKeepClaudeCode() {
        defaults.set(6, forKey: SettingsSchema.versionKey)
        defaults.set("essentials", forKey: "settings.kit")
        XCTAssertEqual(SettingsRepository(defaults: defaults).load().ai.provider, .claudeCLI)
        XCTAssertEqual(defaults.string(forKey: "settings.ai.provider"), "claude-cli", "recorded on disk by the step")
    }

    func testAChoiceSavedBeforeTabbiAskedSendsNothingUntilAllowed() {
        defaults.set(6, forKey: SettingsSchema.versionKey)
        defaults.set("essentials", forKey: "settings.kit")
        let ai = SettingsRepository(defaults: defaults).load().ai
        XCTAssertNil(ai.activeProvider(sandboxed: false))
        XCTAssertTrue(ai.needsConsent(for: .claudeCLI))
    }

    func testPermissionRoundTripsAndUnknownProvidersAreDropped() {
        defaults.set(["gemini", "someday-ai"], forKey: "settings.ai.consented")
        let repository = SettingsRepository(defaults: defaults)
        var settings = repository.load()
        XCTAssertEqual(settings.ai.consented, [.gemini])
        settings.ai.choose(.openAI)
        repository.save(settings)
        XCTAssertEqual(SettingsRepository(defaults: defaults).load().ai.consented, [.gemini, .openAI])
        XCTAssertEqual(defaults.stringArray(forKey: "settings.ai.consented"), ["gemini", "openai"])
    }

    func testTheProviderStepLeavesAFreshInstallAndAChoiceAlone() {
        SettingsSchema.migrate(defaults)
        XCTAssertNil(defaults.object(forKey: "settings.ai.provider"))

        let suite = "TabbiTests.\(UUID().uuidString)"
        let saved = UserDefaults(suiteName: suite)!
        defer { saved.removePersistentDomain(forName: suite) }
        saved.set(6, forKey: SettingsSchema.versionKey)
        saved.set("essentials", forKey: "settings.kit")
        saved.set("ollama", forKey: "settings.ai.provider")
        XCTAssertEqual(SettingsRepository(defaults: saved).load().ai.provider, .ollama)
    }
}
