import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// Plan my day, Refine and Wrap up ask the AI the user picked through the
/// shared `AIService`, here backed by a mocked Ollama, and send nothing
/// while no provider is picked.
@MainActor
final class PlannerAITests: XCTestCase {
    private func makeAI(_ provider: AIProviderID?, transport: AIHTTPProvider.Transport? = nil) -> AIService {
        let suite = "PlannerAITests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(catalog: ModuleList.catalog, defaults: defaults, defaultKitID: "essentials",
                                     kitStore: nil, integratesWithSystem: false)
        settings.settings.ai.provider = provider
        let keys = InMemoryAIKeyStore()
        let factory = AIProviderFactory(keys: keys, sandboxed: false, transport: transport ?? { _ in
            XCTFail("nothing may be sent")
            return AIHTTPResponse(status: 500, lines: AsyncThrowingStream { $0.finish() })
        })
        return AIService(settings: settings, keys: keys, sandboxed: false, factory: factory)
    }

    /// An Ollama stream that answers `text`, recording each request.
    private func ollama(answering text: String, into sent: SentPlannerRequests) -> AIHTTPProvider.Transport {
        { request in
            sent.append(request)
            let line = try String(data: JSONSerialization.data(withJSONObject: [
                "message": ["role": "assistant", "content": text], "done": true,
            ]), encoding: .utf8)!
            return AIHTTPResponse(status: 200, lines: AsyncThrowingStream { continuation in
                continuation.yield(line)
                continuation.finish()
            })
        }
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(10)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition(), "timed out", file: file, line: line)
    }

    private func makeReview(_ ai: AIService?) -> DayReviewStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return DayReviewStore(storage: EditionStorage(root: folder), ai: ai, runMode: .live)
    }

    private var today: PlannerDay {
        PlannerDay(date: PlannerDayKey(date: Date()),
                   items: [PlannerItem(title: "Ship the beta", isDone: true, createdAt: Date(), completedAt: Date())])
    }

    func testWrapUpShowsTheLocalLineAtOnceWhileNoAIIsPicked() {
        let review = makeReview(makeAI(nil))
        review.wrapUp(day: today, activity: [])
        XCTAssertFalse(review.isSummarizing, "no shimmer waiting for an AI that was never picked")
        XCTAssertEqual(review.review?.summary, review.review.map(DayReviewer.fallbackSummary(for:)))
    }

    func testWrapUpAsksThePickedAIForItsSummary() async throws {
        let sent = SentPlannerRequests()
        let review = makeReview(makeAI(.ollama, transport: ollama(answering: "\"Nice work shipping the beta.\"",
                                                                    into: sent)))
        review.wrapUp(day: today, activity: [])
        XCTAssertTrue(review.isSummarizing)
        await waitUntil { !review.isSummarizing }
        XCTAssertEqual(review.review?.summary, "Nice work shipping the beta.", "cleaned like Claude's answer was")
        let request = try XCTUnwrap(sent.all.first)
        XCTAssertEqual(request.url?.host, "localhost")
        let body = try XCTUnwrap(String(data: XCTUnwrap(request.httpBody), encoding: .utf8))
        XCTAssertTrue(body.contains("Ship the beta"), "the prompt lists what got done")
    }

    func testRefineIsOfferedOnlyOnceTheAIIsReady() async {
        let settings = TodayPlanSettings()
        XCTAssertEqual(settings.planMode, .local)

        let ready = DayPlanStore(upNext: UpNextStore(runMode: .live), settings: settings,
                                 ai: makeAI(.ollama, transport: ollama(answering: "{}", into: SentPlannerRequests())),
                                 runMode: .live)
        ready.plan(tasks: [PlannerItem(title: "Write the report", createdAt: Date())])
        await waitUntil { ready.canRefine }
        ready.cancel()

        let unpicked = DayPlanStore(upNext: UpNextStore(runMode: .live), settings: settings, ai: makeAI(nil),
                                    runMode: .live)
        unpicked.plan(tasks: [PlannerItem(title: "Write the report", createdAt: Date())])
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(unpicked.canRefine)
        unpicked.cancel()
    }

    func testPlanFailuresNameTheProvider() {
        XCTAssertEqual(DayPlanStore.Failure.aiNotSetUp(nil).title, "Choose an AI to plan with")
        XCTAssertEqual(DayPlanStore.Failure.aiNotSetUp(.gemini).detail, "Add your Gemini API key in Settings.")
        XCTAssertEqual(DayPlanStore.Failure.aiNotSetUp(.codexCLI).detail, "Install Codex CLI to plan with it.")
        XCTAssertEqual(DayPlanStore.Failure.aiFailed(assistant: "Gemini").detail,
                       "Gemini didn't send back a usable plan. Try again in a moment.")
        XCTAssertTrue(DayPlanStore.Failure.aiNotSetUp(nil).opensConnections)
        XCTAssertTrue(DayPlanStore.Failure.aiFailed(assistant: "AI").canRetry)
        XCTAssertFalse(DayPlanStore.Failure.calendarOff.canRetry)
    }
}

/// Requests a mocked transport received, read back on the main actor.
private final class SentPlannerRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func append(_ request: URLRequest) { lock.withLock { requests.append(request) } }
    var all: [URLRequest] { lock.withLock { requests } }
}
