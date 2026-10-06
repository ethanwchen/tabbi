import AppKit
import SwiftUI
import TabbiKitCore
import TabbiKit

/// Ask Claude: a small chat with the local `claude` CLI. Messages fill the
/// panel and a text field sits at the bottom. The notch stays pinned open
/// while the focused field holds a draft or an answer is streaming, so an
/// idle Ask tab still closes when the pointer leaves. The chat can grow
/// into a larger view (Expand, or Command-Return to send and expand),
/// which stays open until Esc, Collapse or a click elsewhere.
struct ClaudeAskPanel: View {
    /// The large chat view's canvas: room for a long answer at a
    /// comfortable reading width, still anchored under the notch.
    static let largeSize = CGSize(width: 720, height: 460)

    @ObservedObject var session: ClaudeAskSession
    @EnvironmentObject private var notch: NotchViewModel
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private var conversation: ClaudeAskConversation { session.conversation }
    private var accent: Color { AskClaudeModule.descriptor.accentColor }

    /// `ImageRenderer` (used by `--snapshot`) can't draw AppKit-backed views
    /// such as `ScrollView` and `TextField`, so snapshots get static stand-ins.
    static var isSnapshot: Bool { RunMode.current.isSnapshot }

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            if session.isClaudeMissing && conversation.isEmpty {
                ClaudeMissingView()
                    .transition(.opacity)
            } else {
                Group {
                    if session.isAskingScreenAccess {
                        ScreenAccessView(session: session, accent: accent)
                    } else if session.isShowingHistory {
                        HistoryList(session: session, accent: accent)
                    } else if conversation.isEmpty {
                        EmptyChatView(accent: accent) { send($0) }
                    } else {
                        MessageList(session: session, accent: accent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                inputBar
                    .layoutPriority(1)
            }
        }
        .motion(Theme.Motion.content, value: conversation.isEmpty)
        .motion(Theme.Motion.content, value: session.isShowingHistory)
        .motion(Theme.Motion.content, value: session.isClaudeMissing)
        .motion(Theme.Motion.content, value: session.isAskingScreenAccess)
        .onAppear {
            session.prepare()
            session.recheckScreenAccess()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            session.recheckScreenAccess()
        }
        .task {
            // Wait for the notch panel to become key before focusing.
            try? await Task.sleep(for: .milliseconds(80))
            fieldFocused = true
        }
        .onChange(of: (fieldFocused && !draft.isEmpty) || session.isStreaming || isLarge, initial: true) { _, pinned in
            notch.isPinned = pinned
        }
        .onDisappear { notch.isPinned = false }
    }

    // MARK: Input

    private var isLarge: Bool { notch.isEnlarged }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !session.isStreaming
    }

    private var inputBar: some View {
        // Bottom-aligned: with screenshots above the text, the buttons stay
        // level with the line being typed.
        HStack(alignment: .bottom, spacing: Theme.Spacing.s) {
            InputField(text: $draft, focused: $fieldFocused, accent: accent, maxLines: isLarge ? 6 : 3,
                       help: fieldHelp, onSubmit: { expand in send(draft, expand: expand) }) {
                PendingAttachments(session: session)
            } trailing: {
                AttachButton(session: session)
            }
            if session.isStreaming {
                IconButton(symbol: "stop.fill", size: 32, help: "Stop answering") { session.stop() }
                    .transition(.motionPop)
            } else {
                IconButton(symbol: "arrow.up", size: 32, help: "Send (Return)") { send(draft) }
                    .disabled(!canSend)
                    .opacity(canSend ? 1 : 0.45)
                    .transition(.motionPop)
            }
            if session.isShowingHistory || !session.savedChats.isEmpty {
                IconButton(symbol: session.isShowingHistory ? "xmark" : "clock.arrow.circlepath", size: 32,
                           help: session.isShowingHistory ? "Back to the chat" : "Chat history") {
                    session.isShowingHistory.toggle()
                }
                .transition(.motionPop)
            }
            if !conversation.isEmpty {
                IconButton(symbol: "square.and.pencil", size: 32, help: "New chat") {
                    session.newChat()
                    draft = ""
                    fieldFocused = true
                }
                .transition(.motionPop)
            }
            if isLarge || (!conversation.isEmpty && largeView.offersExpand) {
                IconButton(symbol: isLarge ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                           size: 32,
                           help: isLarge ? "Back to the notch (Esc)" : expandHelp) {
                    notch.requestOpenSize(isLarge ? nil : Self.largeSize)
                }
                .transition(.motionPop)
            }
        }
        .motion(Theme.Motion.snappy, value: session.isStreaming)
        .motion(Theme.Motion.snappy, value: isLarge)
        .motion(Theme.Motion.snappy, value: session.isShowingHistory)
        .motion(Theme.Motion.snappy, value: session.savedChats.isEmpty)
    }

    private var largeView: ClaudeAskLargeView { session.preferences.largeView }

    private var expandHelp: String {
        largeView == .always ? "Open in the large view" : "Open in the large view (Command-Return sends and expands)"
    }

    private var fieldHelp: String {
        largeView == .askEachTime && !isLarge
            ? "Return to send, Command-Return to send in the large view, Shift-Return for a new line"
            : "Return to send, Shift-Return for a new line"
    }

    /// Sends `prompt`, growing the chat into the large view when the user's
    /// preference says so; `expand` is true for Command-Return.
    private func send(_ prompt: String, expand: Bool = false) {
        guard !session.isStreaming,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if !isLarge && largeView.opensLarge(commandReturn: expand) { notch.requestOpenSize(Self.largeSize) }
        session.ask(prompt)
        draft = ""
        fieldFocused = true
    }
}

/// The rounded question field. Return sends, Command-Return sends and opens
/// the large view, and Shift-Return adds a line. `top` sits above the text
/// (the screenshots to send) and `trailing` at its right edge.
private struct InputField<Top: View, Trailing: View>: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let accent: Color
    let maxLines: Int
    /// The tooltip, which names Command-Return only when it expands.
    let help: String
    /// Called with true for Command-Return.
    let onSubmit: (_ expand: Bool) -> Void
    @ViewBuilder let top: () -> Top
    @ViewBuilder let trailing: () -> Trailing
    @State private var hovering = false

    var body: some View {
        Card(padding: 0) {
            HStack(alignment: .bottom, spacing: Theme.Spacing.xs) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    top()
                    field
                        .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
                }
                .padding(.leading, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s)
                trailing()
                    .padding(.trailing, Theme.Spacing.xs)
                    .padding(.bottom, Theme.Spacing.xs)
            }
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: focused.wrappedValue)
    }

    @ViewBuilder
    private var field: some View {
        if ClaudeAskPanel.isSnapshot {
            Text("Ask Claude anything…")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.tertiaryText)
        } else {
            TextField("Ask Claude anything…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.primaryText)
                .lineLimit(1...maxLines)
                .focused(focused)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) {
                        // Insert at the caret through the field editor; it
                        // syncs the binding itself.
                        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return .ignored }
                        editor.insertNewlineIgnoringFieldEditor(nil)
                    } else {
                        // Deferred: the field editor ignores binding changes made
                        // while it handles the key, so clearing the draft here
                        // would leave the sent text in the field.
                        let expand = press.modifiers.contains(.command)
                        Task { @MainActor in onSubmit(expand) }
                    }
                    return .handled
                }
                .onSubmit { Task { @MainActor in onSubmit(false) } }
        }
    }

    private var borderColor: Color {
        if focused.wrappedValue { return accent.opacity(0.55) }
        return hovering ? Theme.Palette.stroke.opacity(2) : .clear
    }
}

// MARK: - Messages

private struct MessageList: View {
    @ObservedObject var session: ClaudeAskSession
    let accent: Color

    private static let bottomID = "bottom"

    var body: some View {
        if ClaudeAskPanel.isSnapshot {
            // Bottom-anchored like the live list after auto-scroll.
            rows
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .bottom)
                .clipped()
        } else {
            scrollingList
        }
    }

    private var rows: some View {
        let conversation = session.conversation
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(conversation.messages) { message in
                row(for: message, isLast: message.id == conversation.messages.last?.id)
            }
        }
    }

    private var scrollingList: some View {
        let conversation = session.conversation
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    ForEach(conversation.messages) { message in
                        row(for: message, isLast: message.id == conversation.messages.last?.id)
                            .transition(.motionRow(from: .bottom))
                    }
                    Color.clear.frame(height: 0).id(Self.bottomID)
                }
            }
            .scrollIndicators(.never)
            .defaultScrollAnchor(.bottom)
            // Older messages fade out under the header instead of being cut off.
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: Theme.Spacing.m)
                    Color.black
                }
            )
            // Follows streamed text and the taller stopped/failed rows that replace it.
            .onChange(of: conversation.messages.last?.text) {
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
            .onChange(of: conversation.messages.last?.status) {
                withMotion(Theme.Motion.snappy) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
            .onChange(of: conversation.messages.count) {
                withMotion(Theme.Motion.snappy) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
        }
        .motion(Theme.Motion.snappy, value: conversation.messages.count)
    }

    @ViewBuilder
    private func row(for message: ClaudeAskMessage, isLast: Bool) -> some View {
        switch message.role {
        case .user:
            UserBubble(session: session, message: message, accent: accent)
        case .assistant:
            if message.status == .failed {
                FailureRow(failure: isLast ? session.conversation.failure : nil,
                           onRetry: isLast ? { session.retry() } : nil)
            } else {
                AssistantBubble(message: message, accent: accent)
            }
        }
    }
}

private struct UserBubble: View {
    let session: ClaudeAskSession
    let message: ClaudeAskMessage
    let accent: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
            if !message.attachments.isEmpty {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(message.attachments) { attachment in
                        AttachmentThumbnail(image: session.thumbnail(for: attachment), attachment: attachment, height: 56)
                    }
                }
            }
            bubble
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var bubble: some View {
        HStack {
            Spacer(minLength: 72)
            Text(message.text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                        .fill(accent.opacity(0.22))
                )
        }
    }
}

private struct AssistantBubble: View {
    let message: ClaudeAskMessage
    let accent: Color
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
            Card(padding: 0) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    // Stopped before any text arrived: the "Stopped" note says it all.
                    if !(message.status == .stopped && message.text.isEmpty) {
                        content
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.primaryText)
                            .lineSpacing(Theme.Spacing.xxs)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    if message.status == .stopped {
                        Label("Stopped", systemImage: "stop.circle")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.tertiaryText)
                    }
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s)
            }
            // Beside the card rather than over it, so short answers stay readable.
            CopyButton(text: message.text)
                .opacity(hovering && canCopy ? 1 : 0)
                .allowsHitTesting(hovering && canCopy)
            Spacer(minLength: 0)
        }
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }

    private var canCopy: Bool { message.status != .streaming && !message.text.isEmpty }

    @ViewBuilder
    private var content: some View {
        if message.status == .streaming && message.text.isEmpty {
            // Claude often takes seconds to start; the paw trail says it's on its way.
            HStack(spacing: Theme.Spacing.s) {
                Text("Thinking").foregroundStyle(Theme.Palette.tertiaryText)
                PawLoader(tint: accent, size: 16, label: "Thinking")
            }
        } else if message.status == .streaming {
            // Re-rendered on a timer so the caret blinks while text streams in.
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let visible = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
                AnswerBody(text: message.text,
                           caret: Text(" ▍").foregroundStyle(accent.opacity(visible ? 1 : 0.25)))
            }
        } else if message.text.isEmpty {
            Text("No answer").foregroundStyle(Theme.Palette.tertiaryText)
        } else {
            AnswerBody(text: message.text, caret: nil)
        }
    }
}

/// An answer's prose and code blocks, top to bottom. `caret` (while the
/// answer streams) follows the last block, prose or code.
private struct AnswerBody: View {
    let text: String
    let caret: Text?

    var body: some View {
        let blocks = ClaudeAskMarkdown.blocks(text)
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                let caret = index == blocks.count - 1 ? caret : nil
                switch block {
                case .text(let prose):
                    Text(Self.styled(prose)) + (caret ?? Text(""))
                case .code(let language, let code, let isClosed):
                    CodeBlock(language: language, code: code, canCopy: isClosed || self.caret == nil, caret: caret)
                }
            }
        }
    }
}

extension AnswerBody {
    /// The prose's markdown with inline code in the code blocks' monospaced
    /// size, so it sits level with the rounded body text (bold code stays bold).
    static func styled(_ prose: String) -> AttributedString {
        var text = ClaudeAskMarkdown.attributed(prose)
        // Typed attribute keys, not `run.font`-style key paths, which the
        // concurrency checker flags as non-Sendable.
        typealias Intent = AttributeScopes.FoundationAttributes.InlinePresentationIntentAttribute
        typealias FontKey = AttributeScopes.SwiftUIAttributes.FontAttribute
        for run in text.runs {
            guard let intent = run.attributes[Intent.self], intent.contains(.code) else { continue }
            let weight: Font.Weight = intent.contains(.stronglyEmphasized) ? .semibold : .regular
            text[run.range][FontKey.self] = .system(size: 11, weight: weight, design: .monospaced)
        }
        return text
    }
}

/// A fenced code block: monospaced on a darker inset, with its language and
/// a Copy button above. Long lines wrap, since the notch can't scroll sideways.
private struct CodeBlock: View {
    let language: String?
    let code: String
    let canCopy: Bool
    let caret: Text?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Spacing.s) {
                Text(language ?? "Code")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.s)
                CopyButton(text: code, help: "Copy code")
                    .opacity(canCopy ? 1 : 0)
                    .allowsHitTesting(canCopy)
            }
            .padding(.leading, Theme.Spacing.s)
            .padding(.trailing, Theme.Spacing.xxs)
            .frame(height: 24)
            Rectangle()
                .fill(Theme.Palette.stroke)
                .frame(height: 0.5)
            (Text(code) + (caret ?? Text("")))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.Palette.primaryText)
                .lineSpacing(Theme.Spacing.xxs)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.vertical, Theme.Spacing.s)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                .fill(Theme.Palette.background.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                .strokeBorder(Theme.Palette.stroke, lineWidth: 0.5)
        )
    }
}

/// Copies text (an answer's markdown or a code block); shows a checkmark
/// briefly after copying.
private struct CopyButton: View {
    let text: String
    var help = "Copy answer"
    @State private var copied = false

    var body: some View {
        IconButton(symbol: copied ? "checkmark" : "doc.on.doc", size: 22, help: copied ? "Copied" : help) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        }
    }
}

/// Shown in place of an answer that failed. Only the latest failure explains
/// itself and offers retry; older ones stay as a quiet note.
private struct FailureRow: View {
    let failure: ClaudeAskFailure?
    let onRetry: (() -> Void)?

    var body: some View {
        Card(padding: 0) {
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.warning)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(title)
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(Theme.Palette.primaryText)
                    if let detail {
                        Text(ClaudeAskMarkdown.attributed(detail))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                Spacer(minLength: Theme.Spacing.s)
                if failure == .claudeNotFound {
                    PillButton(title: "Set up Claude", symbol: "link", help: "Open Connections to set up Claude") {
                        ConnectionsStore.shared.showHub()
                    }
                } else if let onRetry {
                    PillButton(title: "Retry", symbol: "arrow.clockwise", help: "Ask this question again", action: onRetry)
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
        }
    }

    private var title: String {
        switch failure {
        case .claudeNotFound: "Claude isn't set up yet"
        case .process, nil: "Claude couldn't answer"
        }
    }

    private var detail: String? {
        switch failure {
        case .claudeNotFound: "Connections shows you how to add it."
        case .process(let detail): detail
        case nil: nil
        }
    }
}

// MARK: - History

/// Saved chats, newest first: open one to continue it, or delete it.
/// The first line says where they live and offers Clear All.
private struct HistoryList: View {
    @ObservedObject var session: ClaudeAskSession
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.s) {
                Label("Chats stay on this Mac", systemImage: "lock.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .help("Saved chats are kept only on this Mac and never uploaded")
                Spacer(minLength: Theme.Spacing.s)
                if !session.savedChats.isEmpty {
                    ClearAllButton { session.deleteAllChats() }
                        .transition(.opacity)
                }
            }
            // As tall as Clear All, so the line stays put when it goes.
            .frame(height: 26)
            if session.savedChats.isEmpty {
                VStack(spacing: Theme.Spacing.xxs) {
                    Text("No saved chats")
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(Theme.Palette.secondaryText)
                    Text("Chats are saved here once Claude answers.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            } else if ClaudeAskPanel.isSnapshot {
                rows
                    .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
                    .clipped()
                    .mask(bottomFade)
            } else {
                ScrollView { rows }
                    .scrollIndicators(.never)
                    .mask(bottomFade)
            }
        }
        .motion(Theme.Motion.snappy, value: session.savedChats.map(\.id))
    }

    /// Older chats fade out above the input bar instead of being cut off.
    private var bottomFade: some View {
        VStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: Theme.Spacing.m)
        }
    }

    private var rows: some View {
        // One clock for every row, so a list that stays open past midnight
        // relabels together.
        let now = Date()
        return LazyVStack(spacing: Theme.Spacing.xxs) {
            ForEach(session.savedChats) { chat in
                HistoryRow(chat: chat, date: chat.dateLabel(now: now),
                           isOpen: chat.id == session.conversation.chatID, accent: accent,
                           open: { session.open(chat) }, delete: { session.delete(chat) })
                    .transition(.motionRow(from: .top))
            }
        }
    }
}

private struct HistoryRow: View {
    let chat: ClaudeAskChat
    let date: String
    let isOpen: Bool
    let accent: Color
    let open: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Button(action: open) {
                HStack(spacing: Theme.Spacing.s) {
                    Circle()
                        .fill(isOpen ? accent : .clear)
                        .frame(width: 6, height: 6)
                    Text(chat.title)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: Theme.Spacing.s)
                    Text(date)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isOpen ? "This chat is open" : "Open this chat and continue it")
            IconButton(symbol: "trash", size: 22, help: "Delete this chat", action: delete)
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
        }
        .padding(.leading, Theme.Spacing.s)
        .padding(.trailing, Theme.Spacing.xxs)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                .fill(hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface)
        )
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// Clear All asks once more before deleting: the first click turns it into
/// a warning, and it settles back if the second never comes.
private struct ClearAllButton: View {
    let action: () -> Void
    @State private var armed = false

    var body: some View {
        PillButton(title: armed ? "Delete All Chats?" : "Clear All", symbol: armed ? "trash" : nil,
                   tint: armed ? Theme.Palette.warning : nil,
                   help: armed ? "Click again to delete every saved chat" : "Delete every saved chat") {
            if armed {
                armed = false
                action()
            } else {
                armed = true
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    armed = false
                }
            }
        }
        .motion(Theme.Motion.snappy, value: armed)
    }
}

// MARK: - Empty and setup states

private struct EmptyChatView: View {
    let accent: Color
    let onPick: (String) -> Void

    private static let examples = [
        "Quick dinner ideas",
        "Write a polite reminder",
        "Tips to focus better",
    ]

    var body: some View {
        StatusMessage(symbol: "sparkles", tint: accent, title: "Ask Claude anything",
                      message: "Quick answers right here. Claude can't see your files.") {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(Self.examples, id: \.self) { prompt in
                    PillButton(title: prompt, help: "Ask “\(prompt)”") { onPick(prompt) }
                }
            }
        }
    }
}

/// Shown when Claude isn't on this Mac: one plain sentence and the one
/// button that leads to Connections, which walks through setting it up.
/// The panel looks again each time it opens.
private struct ClaudeMissingView: View {
    var body: some View {
        StatusMessage(symbol: "sparkles", tint: AskClaudeModule.descriptor.accentColor,
                      title: "Set up Claude to ask questions",
                      message: "Claude is an AI helper that answers questions right here. "
                          + "Connections shows you how to add it.") {
            PillButton(title: "Set up Claude", symbol: "link", help: "Open Connections to set up Claude") {
                ConnectionsStore.shared.showHub()
            }
        }
    }
}

/// A small capsule text button with a hover state.
struct PillButton: View {
    let title: String
    var symbol: String?
    /// Replaces the text color, e.g. for a confirmation.
    var tint: Color?
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 9.5, weight: .bold))
                }
                Text(title).lineLimit(1)
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(tint ?? (hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText))
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s - Theme.Spacing.xxs)
            .background(Capsule().fill(hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface))
            .overlay(Capsule().strokeBorder(Theme.Palette.stroke, lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}
