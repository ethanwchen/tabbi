import Foundation
import SwiftUI
import TabbiKitCore

/// Drives the Ask Claude panel: sends questions to the local `claude` CLI,
/// folds its stream into a `ClaudeAskConversation`, and supports stop,
/// retry, and New chat. Finished exchanges are saved to the chat history
/// on this Mac (live runs only), and a saved chat can be reopened.
@MainActor
final class ClaudeAskSession: ObservableObject {
    @Published private(set) var conversation: ClaudeAskConversation
    /// True when the last lookup found no `claude` executable, so the panel
    /// can explain setup before the user types a question.
    @Published private(set) var isClaudeMissing = false
    /// Saved chats, the most recently answered first.
    @Published private(set) var savedChats: [ClaudeAskChat] = []

    /// True with `TABBI_DEMO=1`: shows a sample chat and never runs the CLI.
    let isDemo: Bool

    /// Nil in demo and snapshot runs, which save nothing.
    private let history: ClaudeAskHistory?
    private var task: Task<Void, Never>?
    /// Bumped on every ask, stop, and New chat so a superseded run can't
    /// write into the conversation after it was cancelled.
    private var generation = 0
    /// Bumped on every lookup so a slow one for an old path can't overwrite
    /// `isClaudeMissing` after a newer one finished.
    private var lookupGeneration = 0

    init(runMode: RunMode, storage: EditionStorage) {
        isDemo = runMode.isDemo
        conversation = isDemo ? .demo : ClaudeAskConversation()
        history = runMode.isDemo || runMode.isSnapshot ? nil : ClaudeAskHistory(storage: storage)
        savedChats = history?.chats() ?? []
    }

    var isStreaming: Bool { conversation.isStreaming }

    /// Sends `prompt`, continuing the current chat when there is one.
    func ask(_ prompt: String) {
        guard let prompt = conversation.begin(prompt: prompt) else { return }
        generation += 1
        let generation = generation
        let sessionID = conversation.sessionID

        if isDemo {
            conversation.apply(.result(ClaudeResult(
                text: "This is a demo. Run \(Edition.current.name) without `TABBI_DEMO` to ask the real Claude.",
                sessionID: sessionID,
                isError: false
            )))
            return
        }

        task = Task { [weak self] in
            guard let executable = await self?.resolveExecutable() else {
                self?.update(generation) { $0.fail(.claudeNotFound) }
                return
            }
            guard !Task.isCancelled else { return }
            let events = ClaudeCLI.stream(
                executable: executable,
                prompt: prompt,
                extraArguments: ClaudeAskRequest.extraArguments(resuming: sessionID)
            )
            do {
                for try await event in events {
                    self?.update(generation) { $0.apply(event) }
                }
                self?.update(generation) { $0.finish() }
            } catch {
                // A failed `result` event already explained the error better
                // than the non-zero exit that follows it.
                self?.update(generation) { conversation in
                    if conversation.isStreaming { conversation.fail(ClaudeAskFailure(error: error)) }
                }
            }
        }
    }

    /// Stops the answer in progress, keeping what has arrived so far.
    func stop() {
        guard isStreaming else { return }
        invalidateRun()
        conversation.cancel()
        saveConversation()
    }

    /// Sends the failed question again.
    func retry() {
        guard let prompt = conversation.takeRetryPrompt() else { return }
        ask(prompt)
    }

    /// Looks up `claude` ahead of the first question (the panel calls this
    /// when it appears, and again from the "not found" view). Cheap once
    /// found; misses are looked up afresh.
    func prepare() {
        guard !isDemo else { return }
        Task { _ = await resolveExecutable() }
    }

    /// Called when the user changes the `claude` path in Settings.
    func claudePathDidChange() {
        prepare()
    }

    /// Clears the chat; the next question starts a fresh CLI session.
    func newChat() {
        invalidateRun()
        conversation.reset()
    }

    /// Reopens a saved chat; the next question continues its CLI session.
    func open(_ chat: ClaudeAskChat) {
        invalidateRun()
        conversation = ClaudeAskConversation(restoring: chat)
    }

    /// Removes a chat from the history. The chat on screen stays, so
    /// deleting the open chat clears it too rather than saving it again.
    func delete(_ chat: ClaudeAskChat) {
        try? history?.delete(chat.id)
        if conversation.chatID == chat.id { newChat() }
        reloadHistory()
    }

    /// Removes every saved chat and starts a new one.
    func deleteAllChats() {
        try? history?.deleteAll()
        newChat()
        reloadHistory()
    }

    // MARK: - Helpers

    private func invalidateRun() {
        generation += 1
        task?.cancel()
        task = nil
    }

    private func update(_ generation: Int, _ change: (inout ClaudeAskConversation) -> Void) {
        guard generation == self.generation else { return }
        let wasStreaming = conversation.isStreaming
        change(&conversation)
        if wasStreaming && !conversation.isStreaming { saveConversation() }
    }

    /// Saves the chat once an exchange ends. A chat with nothing finished
    /// yet (or only failures) is not written.
    private func saveConversation() {
        guard let history, let chat = conversation.savedChat() else { return }
        try? history.save(chat)
        reloadHistory()
    }

    private func reloadHistory() {
        savedChats = history?.chats() ?? []
    }

    /// Locates `claude` off the main thread (the login-shell fallback blocks).
    /// The shared resolver caches hits and follows the Settings override.
    private func resolveExecutable() async -> URL? {
        lookupGeneration += 1
        let lookup = lookupGeneration
        let found = await Task.detached(priority: .userInitiated) { ClaudeExecutableResolver.shared.resolve() }.value
        if lookup == lookupGeneration { isClaudeMissing = found == nil }
        return found
    }
}
