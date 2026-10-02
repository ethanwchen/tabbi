import AppKit
import SwiftUI
import NotchDeckCore

/// Ask Claude: a small chat with the local `claude` CLI. Messages fill the
/// panel and a text field sits at the bottom. The notch stays pinned open
/// while the focused field holds a draft or an answer is streaming, so an
/// idle Ask tab still closes when the pointer leaves.
struct ClaudeAskPanel: View {
    @ObservedObject var session: ClaudeAskSession
    @EnvironmentObject private var notch: NotchViewModel
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private var conversation: ClaudeAskConversation { session.conversation }
    private var accent: Color { Theme.Palette.accent(for: .claudeAsk) }

    /// `ImageRenderer` (used by `--snapshot`) can't draw AppKit-backed views
    /// such as `ScrollView` and `TextField`, so snapshots get static stand-ins.
    static let isSnapshot = CommandLine.arguments.contains("--snapshot")

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            if session.isClaudeMissing && conversation.isEmpty {
                ClaudeMissingView { session.prepare(force: true) }
                    .transition(.opacity)
            } else {
                Group {
                    if conversation.isEmpty {
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
        .animation(Theme.Motion.content, value: conversation.isEmpty)
        .animation(Theme.Motion.content, value: session.isClaudeMissing)
        .onAppear { session.prepare() }
        .task {
            // Wait for the notch panel to become key before focusing.
            try? await Task.sleep(for: .milliseconds(80))
            fieldFocused = true
        }
        .onChange(of: (fieldFocused && !draft.isEmpty) || session.isStreaming, initial: true) { _, pinned in
            notch.isPinned = pinned
        }
        .onDisappear { notch.isPinned = false }
    }

    // MARK: Input

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !session.isStreaming
    }

    private var inputBar: some View {
        HStack(spacing: Theme.Spacing.s) {
            InputField(text: $draft, focused: $fieldFocused, accent: accent, onSubmit: { send(draft) })
            if session.isStreaming {
                IconButton(symbol: "stop.fill", size: 32, help: "Stop answering") { session.stop() }
                    .transition(.scale.combined(with: .opacity))
            } else {
                IconButton(symbol: "arrow.up", size: 32, help: "Send (Return)") { send(draft) }
                    .disabled(!canSend)
                    .opacity(canSend ? 1 : 0.45)
                    .transition(.scale.combined(with: .opacity))
            }
            if !conversation.isEmpty {
                IconButton(symbol: "square.and.pencil", size: 32, help: "New chat") {
                    session.newChat()
                    draft = ""
                    fieldFocused = true
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.snappy, value: session.isStreaming)
    }

    private func send(_ prompt: String) {
        guard !session.isStreaming,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        session.ask(prompt)
        draft = ""
        fieldFocused = true
    }
}

/// The rounded question field. Return sends; Shift-Return adds a line.
private struct InputField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let accent: Color
    let onSubmit: () -> Void
    @State private var hovering = false

    var body: some View {
        Card(padding: 0) {
            field
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .help("Return to send, Shift-Return for a new line")
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
        .animation(Theme.Motion.snappy, value: focused.wrappedValue)
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
                .lineLimit(1...3)
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
                        DispatchQueue.main.async(execute: onSubmit)
                    }
                    return .handled
                }
                .onSubmit { DispatchQueue.main.async(execute: onSubmit) }
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
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
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
                withAnimation(Theme.Motion.snappy) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
            .onChange(of: conversation.messages.count) {
                withAnimation(Theme.Motion.snappy) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
        }
        .animation(Theme.Motion.snappy, value: conversation.messages.count)
    }

    @ViewBuilder
    private func row(for message: ClaudeAskMessage, isLast: Bool) -> some View {
        switch message.role {
        case .user:
            UserBubble(text: message.text, accent: accent)
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
    let text: String
    let accent: Color

    var body: some View {
        HStack {
            Spacer(minLength: 72)
            Text(text)
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
        .animation(Theme.Motion.snappy, value: hovering)
    }

    private var canCopy: Bool { message.status != .streaming && !message.text.isEmpty }

    @ViewBuilder
    private var content: some View {
        if message.status == .streaming {
            // Re-rendered on a timer so the caret blinks while text streams in.
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let visible = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
                let caret = Text(" ▍").foregroundStyle(accent.opacity(visible ? 1 : 0.25))
                if message.text.isEmpty {
                    Text("Thinking").foregroundStyle(Theme.Palette.tertiaryText) + caret
                } else {
                    Text(ClaudeAskMarkdown.attributed(message.text)) + caret
                }
            }
        } else if message.text.isEmpty {
            Text("No answer").foregroundStyle(Theme.Palette.tertiaryText)
        } else {
            Text(ClaudeAskMarkdown.attributed(message.text))
        }
    }
}

/// Copies an answer's markdown; shows a checkmark briefly after copying.
private struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        IconButton(symbol: copied ? "checkmark" : "doc.on.doc", size: 22, help: "Copy answer") {
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
                if let onRetry {
                    PillButton(title: "Retry", symbol: "arrow.clockwise", help: "Ask this question again", action: onRetry)
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
        }
    }

    private var title: String {
        switch failure {
        case .claudeNotFound: "Can't find the claude CLI"
        case .process, nil: "Claude couldn't answer"
        }
    }

    private var detail: String? {
        switch failure {
        case .claudeNotFound: "Install Claude Code, or set `\(ClaudeCLI.overrideVariable)` to its path."
        case .process(let detail): detail
        case nil: nil
        }
    }
}

// MARK: - Empty and setup states

private struct EmptyChatView: View {
    let accent: Color
    let onPick: (String) -> Void

    private static let examples = [
        "Explain git rebase simply",
        "Regex for an email address",
        "Tips for commit messages",
    ]

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(accent)
            VStack(spacing: Theme.Spacing.xxs) {
                Text("Ask Claude anything")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                Text("Quick text answers from your local Claude Code, with no tools or file access.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
            }
            HStack(spacing: Theme.Spacing.s) {
                ForEach(Self.examples, id: \.self) { prompt in
                    PillButton(title: prompt, help: "Ask “\(prompt)”") { onPick(prompt) }
                }
            }
            .padding(.top, Theme.Spacing.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ClaudeMissingView: View {
    let onCheckAgain: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: "terminal")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.Palette.warning)
            VStack(spacing: Theme.Spacing.xs) {
                Text("Can't find the claude CLI")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                (Text("Install Claude Code and sign in, or set ")
                    + Text(ClaudeCLI.overrideVariable).font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    + Text(" to the full path of your claude binary."))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 340)
            }
            PillButton(title: "Check again", symbol: "arrow.clockwise", help: "Look for claude again", action: onCheckAgain)
                .padding(.top, Theme.Spacing.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A small capsule text button with a hover state.
private struct PillButton: View {
    let title: String
    var symbol: String?
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
            .foregroundStyle(hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s - Theme.Spacing.xxs)
            .background(Capsule().fill(hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface))
            .overlay(Capsule().strokeBorder(Theme.Palette.stroke, lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
    }
}
