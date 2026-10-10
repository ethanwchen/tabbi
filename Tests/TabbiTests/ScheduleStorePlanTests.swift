import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// The Schedule tab's Plan, Refine, Add and Skip through the store, with a
/// fixed clock and a mocked Ollama standing in for the AI the user picked.
/// The live store is never shown (`setVisible`) and never adds, so it
/// neither reads nor writes the real calendar even on a test host that has
/// calendar access: the plan fills an empty day. The demo store covers
/// Add, which writes nowhere in demo mode.
@MainActor
final class ScheduleStorePlanTests: XCTestCase {
    /// Monday 2026-10-12, 09:00 on this Mac's calendar: the whole working day is ahead.
    private let morning = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 9))!

    private let tasks = [
        ProvidedTask(id: "report", source: .planner, title: "Write the report", estimatedMinutes: 60),
        ProvidedTask(id: "slides", source: .planner, title: "Review the slides", estimatedMinutes: 30),
    ]

    private func makeAI(_ provider: AIProviderID?, transport: AIHTTPProvider.Transport? = nil) -> AIService {
        let suite = "ScheduleStorePlanTests.\(UUID().uuidString)"
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

    /// A live store at `morning` with two shared tasks to plan.
    private func makeStore(ai: AIService?) -> ScheduleStore {
        let store = ScheduleStore(ai: ai, runMode: .live, clock: { [morning] in morning })
        store.sharedTasks = tasks
        return store
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(10)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition(), "timed out", file: file, line: line)
    }

    /// Plans the morning and waits until Refine is offered.
    private func planAndWaitForRefine(_ store: ScheduleStore) async throws -> ScheduleDraft {
        store.planDay()
        let draft = try XCTUnwrap(store.draft)
        await waitUntil { store.canRefine }
        return draft
    }

    // MARK: - Plan

    func testPlanFillsTheRestOfTheDayFromTheFixedClock() throws {
        let store = makeStore(ai: nil)
        store.planDay()
        let draft = try XCTUnwrap(store.draft)
        XCTAssertEqual(Set(draft.items.map(\.title)), ["Write the report", "Review the slides"])
        for block in draft.items {
            XCTAssertGreaterThanOrEqual(block.start, morning, "\(block.title) starts after now")
            XCTAssertTrue(Calendar.current.isDate(block.start, inSameDayAs: morning))
            XCTAssertEqual(block.kind, .proposed)
        }
        XCTAssertEqual(store.shownItems.count, draft.items.count, "the offer shows on an empty timeline")
        XCTAssertFalse(store.aiReady)
        XCTAssertFalse(store.canRefine, "no AI picked, so Refine is not offered")
        store.refine()
        XCTAssertFalse(store.isRefining)
    }

    func testSkippingEveryBlockClearsTheOfferAndTheSelection() throws {
        let store = makeStore(ai: nil)
        store.planDay()
        let ids = try XCTUnwrap(store.draft).items.map(\.id)
        store.select(ids[0])
        XCTAssertEqual(store.selectedItem?.id, ids[0])

        store.skip(ids[0])
        XCTAssertNil(store.selectedID, "a skipped block can't stay selected")
        XCTAssertEqual(store.draft?.items.map(\.id), Array(ids.dropFirst()))
        for id in ids.dropFirst() { store.skip(id) }
        XCTAssertNil(store.draft, "an offer with nothing left goes away")
        XCTAssertTrue(store.items.isEmpty, "skipping writes nothing")
    }

    // MARK: - Refine

    func testRefineReplacesTheBlocksWithTheAIsValidatedPlan() async throws {
        let sent = SentScheduleRequests()
        let answer = #"{"blocks":[{"start":"13:00","end":"14:15","title":"Write the report"}]}"#
        let store = makeStore(ai: makeAI(.ollama, transport: ollama(answering: answer, into: sent)))
        _ = try await planAndWaitForRefine(store)
        XCTAssertEqual(store.assistantName, "Ollama")

        store.refine()
        XCTAssertTrue(store.isRefining)
        await waitUntil { !store.isRefining }

        XCTAssertFalse(store.refineFailed)
        let block = try XCTUnwrap(store.draft?.items.first)
        XCTAssertEqual(store.draft?.items.count, 1)
        XCTAssertEqual(block.title, "Write the report")
        XCTAssertEqual(block.start, morning.addingTimeInterval(4 * 3600))
        XCTAssertEqual(block.end, morning.addingTimeInterval(5 * 3600 + 15 * 60))
        XCTAssertFalse(store.canRefine, "a plan is refined once")
        let body = try XCTUnwrap(sent.all.first?.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertTrue(body.contains("Review the slides"), "the AI sees the local plan")
    }

    func testAnUnusableAnswerKeepsTheLocalPlan() async throws {
        let store = makeStore(ai: makeAI(.ollama, transport: ollama(answering: "Looks good to me.",
                                                                    into: SentScheduleRequests())))
        let local = try await planAndWaitForRefine(store)

        store.refine()
        await waitUntil { !store.isRefining }
        XCTAssertTrue(store.refineFailed)
        XCTAssertEqual(store.draft, local, "the local plan stays usable")

        store.planDay()
        XCTAssertFalse(store.refineFailed, "a new plan clears the old failure")
    }

    func testOfferedBlocksCannotBeSelectedOrSkippedWhileRefining() async throws {
        let gate = AnswerGate()
        let store = makeStore(ai: makeAI(.ollama, transport: gate.transport))
        let local = try await planAndWaitForRefine(store)
        let id = try XCTUnwrap(local.items.first?.id)

        store.refine()
        await waitUntil { gate.isHeld }
        store.select(id)
        XCTAssertNil(store.selectedID, "the block may move while the AI refines it")
        store.skip(id)
        XCTAssertEqual(store.draft, local)

        gate.release(answering: "not json")
        await waitUntil { !store.isRefining }
        XCTAssertTrue(store.refineFailed)
    }

    func testDiscardingWhileRefiningDropsTheLateAnswer() async throws {
        let gate = AnswerGate()
        let store = makeStore(ai: makeAI(.ollama, transport: gate.transport))
        _ = try await planAndWaitForRefine(store)

        store.refine()
        await waitUntil { gate.isHeld }
        store.discardPlan()
        XCTAssertFalse(store.isRefining)
        XCTAssertNil(store.draft)

        gate.release(answering: #"{"blocks":[{"start":"13:00","end":"14:00","title":"Write the report"}]}"#)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(store.draft, "a cancelled refine brings no plan back")
        XCTAssertFalse(store.refineFailed)
        XCTAssertFalse(store.isRefining)
    }

    func testPlanningAgainWhileRefiningKeepsTheNewPlan() async throws {
        let gate = AnswerGate()
        let store = makeStore(ai: makeAI(.ollama, transport: gate.transport))
        _ = try await planAndWaitForRefine(store)

        store.refine()
        await waitUntil { gate.isHeld }
        store.planDay()
        let fresh = try XCTUnwrap(store.draft)
        XCTAssertFalse(store.isRefining)

        gate.release(answering: #"{"blocks":[{"start":"16:00","end":"17:00","title":"Write the report"}]}"#)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(store.draft, fresh, "the old refine's answer doesn't land on the new plan")
        XCTAssertFalse(store.refineFailed, "nor does its cancellation show as a failure")
        XCTAssertTrue(store.canRefine)
    }

    func testAWeekPlanIsNeverRefined() async throws {
        let store = makeStore(ai: makeAI(.ollama, transport: ollama(answering: "{}", into: SentScheduleRequests())))
        _ = try await planAndWaitForRefine(store)
        store.show(.week)
        store.planWeek()
        XCTAssertEqual(store.draft?.isWeek, true)
        XCTAssertFalse(store.canRefine)
        store.refine()
        XCTAssertFalse(store.isRefining)
    }

    // MARK: - Add (demo, which writes nowhere)

    func testAddingOneBlockThenTheRestShowsThemAsPlanned() throws {
        let store = ScheduleStore(runMode: .demo)
        let before = store.items.count
        store.planDay()
        let offered = try XCTUnwrap(store.draft).items
        XCTAssertGreaterThan(offered.count, 1, "the demo plans several blocks")

        store.add(offered[0].id)
        XCTAssertFalse(store.writeFailed)
        XCTAssertEqual(store.draft?.items.count, offered.count - 1)
        XCTAssertEqual(store.items.count, before + 1)
        let added = try XCTUnwrap(store.items.last)
        XCTAssertEqual(added.kind, .planned)
        XCTAssertEqual(added.title, offered[0].title)
        XCTAssertEqual(added.start, offered[0].start)

        store.add()
        XCTAssertNil(store.draft, "every block is on the calendar, so the offer is done")
        XCTAssertEqual(store.items.count, before + offered.count)
        XCTAssertEqual(store.items.filter { $0.kind == .proposed }.count, 0)
    }

    func testAddWaitsWhileTheDemoRefinesAndTheDemoNeverAsksTheAI() async throws {
        let store = ScheduleStore(ai: makeAI(.ollama), runMode: .demo)
        let before = store.items.count
        store.planDay()
        let local = try XCTUnwrap(store.draft)
        XCTAssertTrue(store.canRefine)

        store.refine()
        XCTAssertTrue(store.isRefining)
        store.add()
        XCTAssertEqual(store.draft, local, "Add waits for the AI")
        XCTAssertEqual(store.items.count, before)

        await waitUntil { !store.isRefining }
        XCTAssertFalse(store.refineFailed)
        XCTAssertEqual(store.draft?.proposal.pending, local.proposal.pending, "the demo AI agrees with the plan")
        store.add()
        XCTAssertNil(store.draft)
        XCTAssertEqual(store.items.count, before + local.items.count)
    }

    // MARK: - Helpers

    /// An Ollama stream that answers `text`, recording each request.
    private func ollama(answering text: String, into sent: SentScheduleRequests) -> AIHTTPProvider.Transport {
        { request in
            sent.append(request)
            return ollamaResponse(text)
        }
    }
}

/// Ollama's one-line streamed reply carrying `text`.
private func ollamaLine(_ text: String) -> String {
    try! String(data: JSONSerialization.data(withJSONObject: [
        "message": ["role": "assistant", "content": text], "done": true,
    ]), encoding: .utf8)!
}

private func ollamaResponse(_ text: String) -> AIHTTPResponse {
    AIHTTPResponse(status: 200, lines: AsyncThrowingStream { continuation in
        continuation.yield(ollamaLine(text))
        continuation.finish()
    })
}

/// Requests a mocked transport received, read back on the main actor.
private final class SentScheduleRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func append(_ request: URLRequest) { lock.withLock { requests.append(request) } }
    var all: [URLRequest] { lock.withLock { requests } }
}

/// Holds the AI's answer until the test releases it, so a test can act
/// while Refine is waiting.
private final class AnswerGate: @unchecked Sendable {
    private let lock = NSLock()
    private var held = false
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?
    private var pending: String?

    var isHeld: Bool { lock.withLock { held } }

    var transport: AIHTTPProvider.Transport {
        { [self] _ in
            let (lines, continuation) = AsyncThrowingStream<String, Error>.makeStream()
            let early = lock.withLock { () -> String? in
                held = true
                self.continuation = continuation
                return pending
            }
            if let early { Self.answer(early, on: continuation) }
            return AIHTTPResponse(status: 200, lines: lines)
        }
    }

    func release(answering text: String) {
        let continuation = lock.withLock { () -> AsyncThrowingStream<String, Error>.Continuation? in
            pending = text
            return self.continuation
        }
        if let continuation { Self.answer(text, on: continuation) }
    }

    private static func answer(_ text: String, on continuation: AsyncThrowingStream<String, Error>.Continuation) {
        continuation.yield(ollamaLine(text))
        continuation.finish()
    }
}
