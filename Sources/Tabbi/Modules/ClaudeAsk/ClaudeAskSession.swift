import AppKit
import Foundation
import SwiftUI
import TabbiKitCore

/// Drives the Ask Claude panel: sends questions to the local `claude` CLI,
/// folds its stream into a `ClaudeAskConversation`, and supports stop,
/// retry, and New chat. Finished exchanges are saved to the chat history
/// on this Mac (live runs only), and a saved chat can be reopened.
/// Screenshots attached to a question go with it to the CLI's stdin and
/// are kept with the saved chat; a capture whose chat is never saved is
/// deleted once it is answered.
@MainActor
final class ClaudeAskSession: ObservableObject {
    @Published private(set) var conversation: ClaudeAskConversation
    /// True when the last lookup found no `claude` executable, so the panel
    /// can explain setup before the user types a question.
    @Published private(set) var isClaudeMissing = false
    /// Saved chats, the most recently answered first. Demo runs keep a
    /// sample list in memory.
    @Published private(set) var savedChats: [ClaudeAskChat] = []
    /// True while the panel lists saved chats instead of the conversation.
    @Published var isShowingHistory = false
    /// Saved as soon as it changes (live runs only).
    @Published var preferences: ClaudeAskPreferences {
        didSet { if preferences != oldValue { preferencesStorage?.save(preferences) } }
    }
    /// Screenshots waiting to go with the next question.
    @Published private(set) var pendingAttachments: [ClaudeAskAttachment] = []
    /// True while a screenshot is being taken.
    @Published private(set) var isCapturing = false
    /// True while the panel explains why Screen Recording is needed,
    /// before the system is asked.
    @Published var isAskingScreenAccess = false
    /// Set when a capture failed, cleared by the next attempt or question.
    @Published private(set) var captureFailed = false

    /// Enough for a before and after; more would mostly cost tokens.
    static let maxPendingAttachments = 3

    /// True with `TABBI_DEMO=1`: shows a sample chat and never runs the CLI.
    let isDemo: Bool
    private let isSnapshot: Bool

    /// Nil in demo and snapshot runs, which save nothing.
    private let history: ClaudeAskHistory?
    /// Nil in demo and snapshot runs, which keep preferences in memory.
    private let preferencesStorage: ClaudeAskPreferencesStorage?
    private let attachmentStore: ClaudeAskAttachmentStore
    /// Thumbnails by attachment id. A capture's image is cached when it is
    /// staged, so it still shows after an unsaved file is discarded.
    private var thumbnails: [UUID: NSImage] = [:]
    /// Images of sample screenshots (demo and snapshot runs), which have no
    /// file and outlive the cache.
    private var sampleThumbnails: [UUID: NSImage] = [:]
    /// The chat a snapshot shot replaced, put back for the next shot.
    private var conversationBeforeSnapshot: ClaudeAskConversation?
    private var task: Task<Void, Never>?
    /// Bumped on every ask, stop, and New chat so a superseded run can't
    /// write into the conversation after it was cancelled.
    private var generation = 0
    /// Bumped on every lookup so a slow one for an old path can't overwrite
    /// `isClaudeMissing` after a newer one finished.
    private var lookupGeneration = 0

    init(runMode: RunMode, storage: EditionStorage) {
        isDemo = runMode.isDemo
        isSnapshot = runMode.isSnapshot
        let savesNothing = runMode.isDemo || runMode.isSnapshot
        history = savesNothing ? nil : ClaudeAskHistory(storage: storage)
        preferencesStorage = savesNothing ? nil : ClaudeAskPreferencesStorage()
        preferences = preferencesStorage?.load() ?? ClaudeAskPreferences()
        // The live app has one staging folder per edition, cleared at launch
        // for captures a previous run left behind. Demo and snapshot runs
        // stage in a folder of their own per process, so they can never
        // clear a capture the live app is still waiting to send.
        let editionStaging = FileManager.default.temporaryDirectory
            .appendingPathComponent("Ask Claude Screenshots", isDirectory: true)
            .appendingPathComponent(storage.root.lastPathComponent, isDirectory: true)
        let staging = savesNothing
            ? editionStaging.appendingPathComponent("Sample Runs", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            : editionStaging
        attachmentStore = ClaudeAskAttachmentStore(stagingDirectory: staging, history: history)
        if !savesNothing { attachmentStore.clearStaging() }
        // Demo history has a question asked about a sample screenshot.
        let capture = isDemo ? ClaudeAskScreenCapture.demoCapture() : nil
        let screenshot = capture.map { ClaudeAskAttachment(pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight) }
        if isDemo {
            let samples = ClaudeAskChat.demoHistory(now: Date(), screenshot: screenshot)
            conversation = samples.first.map(ClaudeAskConversation.init(restoring:)) ?? .demo
            savedChats = samples
        } else {
            conversation = ClaudeAskConversation()
            savedChats = history?.chats() ?? []
        }
        if let capture, let screenshot {
            sampleThumbnails[screenshot.id] = NSImage(data: capture.pngData)
        }
    }

    var isStreaming: Bool { conversation.isStreaming }

    /// Sends `prompt` with the pending screenshots, continuing the current
    /// chat when there is one.
    func ask(_ prompt: String) {
        let question = ClaudeAskQuestion(text: prompt, attachments: pendingAttachments)
        guard send(question) else { return }
        pendingAttachments = []
    }

    /// Returns false when there was nothing to send.
    @discardableResult
    private func send(_ question: ClaudeAskQuestion) -> Bool {
        guard !isStreaming else { return false }
        isShowingHistory = false
        captureFailed = false
        guard let prompt = conversation.begin(prompt: question.text, attachments: question.attachments) else {
            return false
        }
        generation += 1
        let generation = generation
        let sessionID = conversation.sessionID
        let outgoing = conversation.outgoingPrompt(prompt)
        let images = question.attachments.compactMap { attachmentStore.data(for: $0, in: conversation.chatID) }

        // Never send a question without a screenshot its thumbnail promised.
        guard images.count == question.attachments.count else {
            conversation.fail(.process(detail: "A screenshot for this question is gone. Ask again without it."))
            exchangeEnded()
            return true
        }

        if isDemo {
            conversation.apply(.result(ClaudeResult(
                text: "This is a demo. Run \(Edition.current.name) without `TABBI_DEMO` to ask the real Claude.",
                sessionID: sessionID,
                isError: false
            )))
            exchangeEnded()
            return true
        }

        task = Task { [weak self] in
            guard let executable = await self?.resolveExecutable() else {
                self?.update(generation) { $0.fail(.claudeNotFound) }
                return
            }
            guard !Task.isCancelled else { return }
            do {
                // Every question goes in as a stream-json message, the one
                // way the CLI takes images; text-only questions use it too
                // so there is a single path.
                let events = ClaudeCLI.stream(
                    executable: executable,
                    inputLine: try ClaudeAskRequest.inputLine(prompt: outgoing, images: images),
                    extraArguments: ClaudeAskRequest.extraArguments(resuming: sessionID)
                )
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
        return true
    }

    /// Stops the answer in progress, keeping what has arrived so far.
    func stop() {
        guard isStreaming else { return }
        invalidateRun()
        conversation.cancel()
        exchangeEnded()
    }

    /// Sends the failed question again, with its screenshots.
    func retry() {
        guard !isStreaming, let question = conversation.takeRetryQuestion() else { return }
        send(question)
    }

    // MARK: - Screenshots

    /// Takes a screenshot for the next question, first explaining Screen
    /// Recording when Tabbi isn't allowed yet. Demo runs attach a sample.
    func attachScreenshot() {
        guard !isCapturing, pendingAttachments.count < Self.maxPendingAttachments else { return }
        captureFailed = false
        if isDemo {
            if let capture = ClaudeAskScreenCapture.demoCapture() { stage(capture) }
            return
        }
        guard ClaudeAskScreenCapture.hasAccess else {
            isShowingHistory = false
            isAskingScreenAccess = true
            return
        }
        isAskingScreenAccess = false
        isCapturing = true
        Task { [weak self] in
            let capture = try? await ClaudeAskScreenCapture.captureDisplay()
            guard let self else { return }
            isCapturing = false
            if let capture { stage(capture) } else { captureFailed = true }
        }
    }

    /// From the priming screen: puts Tabbi in the Screen Recording list
    /// (the system asks the first time) and opens that Settings pane.
    func openScreenRecordingSettings() {
        ClaudeAskScreenCapture.requestAccess()
        NSWorkspace.shared.open(ClaudeAskScreenCapture.settingsURL)
    }

    /// Called when the panel shows again: once access was granted, the
    /// priming screen gives way to the capture the user asked for.
    func recheckScreenAccess() {
        guard !isDemo, !isSnapshot, isAskingScreenAccess, ClaudeAskScreenCapture.hasAccess else { return }
        attachScreenshot()
    }

    /// Takes a screenshot off the next question and deletes its file.
    func removePending(_ attachment: ClaudeAskAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
        attachmentStore.discard([attachment])
        thumbnails[attachment.id] = nil
    }

    /// The image for a thumbnail, from the cache or the file on disk.
    func thumbnail(for attachment: ClaudeAskAttachment) -> NSImage? {
        if let cached = thumbnails[attachment.id] ?? sampleThumbnails[attachment.id] { return cached }
        guard let url = attachmentStore.url(for: attachment, in: conversation.chatID),
              let image = NSImage(contentsOf: url) else { return nil }
        thumbnails[attachment.id] = image
        return image
    }

    /// What a `--snapshot` shot of the panel shows besides the chat.
    enum SnapshotState {
        case chat
        /// A sample screenshot waiting to go with the next question.
        case pendingScreenshot
        /// The Screen Recording priming screen.
        case screenAccess
        /// An answered question that was sent with a sample screenshot.
        case sentScreenshot
    }

    /// Snapshot runs only: puts the panel in `state` for the next shot.
    func showForSnapshot(_ state: SnapshotState) {
        guard isSnapshot else { return }
        isAskingScreenAccess = state == .screenAccess
        if state == .sentScreenshot {
            if conversationBeforeSnapshot == nil { conversationBeforeSnapshot = conversation }
            if let screenshot = sampleScreenshot() {
                conversation = ClaudeAskConversation(restoring: .demoScreenshotChat(screenshot, at: Date()))
            }
        } else if let previous = conversationBeforeSnapshot {
            conversation = previous
            conversationBeforeSnapshot = nil
        }
        let wantsPending = state == .pendingScreenshot
        if wantsPending, pendingAttachments.isEmpty, let capture = ClaudeAskScreenCapture.demoCapture() {
            stage(capture)
        } else if !wantsPending {
            for attachment in pendingAttachments { removePending(attachment) }
        }
    }

    /// A sample screenshot with its image cached, never written to disk.
    private func sampleScreenshot() -> ClaudeAskAttachment? {
        guard let capture = ClaudeAskScreenCapture.demoCapture() else { return nil }
        let attachment = ClaudeAskAttachment(pixelWidth: capture.pixelWidth, pixelHeight: capture.pixelHeight)
        sampleThumbnails[attachment.id] = NSImage(data: capture.pngData)
        return attachment
    }

    private func stage(_ capture: ClaudeAskScreenCapture.Capture) {
        // A full tray is not a failed capture; the Attach button is already off.
        guard pendingAttachments.count < Self.maxPendingAttachments else { return }
        guard let attachment = try? attachmentStore.stage(pngData: capture.pngData, pixelWidth: capture.pixelWidth,
                                                          pixelHeight: capture.pixelHeight) else {
            captureFailed = true
            return
        }
        thumbnails[attachment.id] = NSImage(data: capture.pngData)
        pendingAttachments.append(attachment)
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
        leaveConversation()
        for attachment in pendingAttachments { removePending(attachment) }
        conversation.reset()
        isShowingHistory = false
    }

    /// Reopens a saved chat; the next question continues its CLI session.
    func open(_ chat: ClaudeAskChat) {
        guard chat.id != conversation.chatID else {
            isShowingHistory = false
            return
        }
        // Stopping a running answer saves what arrived before switching.
        stop()
        invalidateRun()
        leaveConversation()
        conversation = ClaudeAskConversation(restoring: chat)
        isShowingHistory = false
    }

    /// Removes a chat from the history. Deleting the open chat clears it
    /// too, rather than saving it again with its next answer.
    func delete(_ chat: ClaudeAskChat) {
        try? history?.delete(chat.id)
        if conversation.chatID == chat.id {
            invalidateRun()
            leaveConversation()
            conversation.reset()
        }
        reloadHistory(removing: [chat.id])
    }

    /// Removes every saved chat and starts a new one.
    func deleteAllChats() {
        try? history?.deleteAll()
        invalidateRun()
        leaveConversation()
        conversation.reset()
        reloadHistory(removing: Set(savedChats.map(\.id)))
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
        guard wasStreaming && !conversation.isStreaming else { return }
        // The CLI deletes old sessions; such a chat goes on as a new one,
        // seeded with what was said so far.
        if let question = conversation.takeQuestionForLostSession() {
            send(question)
        } else {
            exchangeEnded()
        }
    }

    /// Saves the chat once an exchange ends, with its screenshots. The last
    /// question's screenshots that the saved chat leaves out (all of them in
    /// runs that save nothing) are deleted; a failed question keeps them for
    /// Retry until the chat is left.
    private func exchangeEnded() {
        let chat = history == nil ? nil : conversation.savedChat()
        if let history, let chat {
            try? attachmentStore.keep(chat.messages.flatMap(\.attachments), in: chat.id)
            try? history.save(chat)
            reloadHistory()
        }
        guard conversation.failure == nil,
              let question = conversation.messages.last(where: { $0.role == .user }) else { return }
        let kept = Set(chat?.messages.flatMap(\.attachments).map(\.id) ?? [])
        attachmentStore.discard(question.attachments.filter { !kept.contains($0.id) })
    }

    /// Deletes screenshots of the current chat that were never saved, such
    /// as those of a failed question, before it is replaced.
    private func leaveConversation() {
        let attachments = conversation.messages.flatMap(\.attachments)
        attachmentStore.discard(attachments)
        for attachment in attachments { thumbnails[attachment.id] = nil }
    }

    /// Rereads the saved chats; demo runs, which have no files, drop
    /// `removing` from the sample list instead.
    private func reloadHistory(removing removed: Set<UUID> = []) {
        if let history {
            savedChats = history.chats()
        } else {
            savedChats.removeAll { removed.contains($0.id) }
        }
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
