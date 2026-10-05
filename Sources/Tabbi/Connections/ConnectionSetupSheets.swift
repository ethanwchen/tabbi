import SwiftUI
import TabbiKitCore

/// A sheet a Connections row opens for a step that takes more than one
/// click: a walkthrough, or the priming screen before a macOS prompt.
enum ConnectionSheet: Identifiable, Hashable {
    /// `asSuggestion`: opened from a connected row's quiet extra button.
    case guide(ConnectionGuide, ConnectionKind, asSuggestion: Bool)
    case priming(ConnectionPermission, ConnectionKind)
    /// "Something not working?": the checks behind the row, in plain words.
    case troubleshoot(ConnectionKind)
    /// Party's name and pet, the only setup it needs.
    case partySetup

    var id: Self { self }

    var kind: ConnectionKind {
        switch self {
        case .guide(_, let kind, _), .priming(_, let kind), .troubleshoot(let kind): kind
        case .partySetup: .party
        }
    }

    /// The sheet a row's button opens, or nil when the button acts directly.
    init?(_ action: ConnectionAction, for kind: ConnectionKind, status: ConnectionStatus) {
        switch action {
        case .showGuide(let guide):
            self = .guide(guide, kind, asSuggestion: status.action != action && status.suggestion == action)
        case .askPermission(let permission): self = .priming(permission, kind)
        case .setUp where kind == .party: self = .partySetup
        default: return nil
        }
    }
}

/// Shows a `ConnectionSheet` against the shared store: a walkthrough that
/// waits for its row to turn green, or a priming screen whose Continue
/// lets macOS ask.
struct ConnectionSheetView: View {
    let sheet: ConnectionSheet
    @ObservedObject var store: ConnectionsStore
    /// Runs a row button pressed inside this sheet (the troubleshooter's
    /// fix), which may close it and open the next sheet.
    let perform: (ConnectionAction, ConnectionKind) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch sheet {
        case .guide(let guide, let kind, let asSuggestion):
            let status = store.status(of: kind)
            ConnectionWalkthroughView(
                kind: kind, walkthrough: store.walkthrough(for: guide), light: status.light,
                isFinished: status.finishes(guide, openedAsSuggestion: asSuggestion),
                start: { store.run($0, for: kind) }, copy: store.copy, close: { dismiss() },
                test: kind == .doNotDisturb ? store.doNotDisturbTest : nil,
                runTest: kind == .doNotDisturb ? { store.testDoNotDisturb() } : nil
            )
            .onAppear { store.beginWaiting(for: kind) }
            .onDisappear { store.endWaiting(for: kind) }
        case .priming(let permission, let kind):
            ConnectionPrimingView(kind: kind, priming: permission.priming) {
                dismiss()
                Task { await store.request(permission, for: kind) }
            }
        case .troubleshoot(let kind):
            ConnectionTroubleshootView(
                kind: kind, diagnosis: store.diagnosis(of: kind), isChecking: store.running.contains(kind),
                perform: { perform($0, kind) }, checkAgain: { store.refresh([kind]) },
                copyDetails: { store.details(of: kind).map(store.copy) }, close: { dismiss() }
            )
            .onAppear { store.refresh([kind]) }
        case .partySetup:
            let draft = store.partyDraft
            PartySetupView(name: draft.name, species: draft.species, state: store.partyState,
                           start: store.startParty, copy: store.copy, close: { dismiss() })
        }
    }
}

/// A numbered walkthrough with one primary button. Below the steps it
/// shows whether the row works yet, and switches to a Done button once it
/// does, so the user sees the fix land without reporting back.
struct ConnectionWalkthroughView: View {
    let kind: ConnectionKind
    let walkthrough: ConnectionWalkthrough
    /// The row's light, which tints the icon.
    let light: ConnectionLight
    /// Whether the steps worked (see `ConnectionStatus.finishes`).
    let isFinished: Bool
    let start: (ConnectionStepAction) -> Void
    let copy: (String) -> Void
    let close: () -> Void
    /// The latest test of the finished setup, and how to run one, for rows
    /// that can prove themselves (Do Not Disturb); nil elsewhere.
    var test: DoNotDisturbTest?
    var runTest: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ConnectionSheetHeader(kind: kind, light: isFinished ? .connected : light, title: walkthrough.title,
                                  message: walkthrough.intro)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(walkthrough.steps.enumerated()), id: \.offset) { index, step in
                    WalkthroughStepRow(number: index + 1, step: step, copy: copy)
                }
            }

            Divider()

            progress

            HStack(spacing: 12) {
                if let learnMore = walkthrough.learnMore, !isFinished {
                    Link("More help", destination: learnMore)
                        .help("Open the official setup page")
                }
                Spacer(minLength: 8)
                if isFinished {
                    if let runTest {
                        Button("Test it", action: runTest)
                            .disabled(test?.isRunning == true)
                            .help("Turn \(kind.title) on for a moment, then off again")
                    }
                    Button("Done", action: close)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .help("Close this guide")
                } else {
                    Button("Not now", action: close)
                        .keyboardShortcut(.cancelAction)
                        .help("Close this guide. You can come back any time.")
                    Button(walkthrough.start.title) { start(walkthrough.start) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .help(walkthrough.start.help)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.spring(duration: 0.3), value: isFinished)
    }

    /// Whether the row works yet, on its own line above the buttons.
    @ViewBuilder private var progress: some View {
        if isFinished, let test {
            DoNotDisturbTestLine(test: test)
        } else if isFinished {
            Label("\(kind.title) is connected. You're all set.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout.weight(.medium))
        } else {
            Label {
                Text(ConnectionWalkthrough.waiting)
                    .foregroundStyle(.secondary)
            } icon: {
                ProgressView().controlSize(.small)
            }
            .font(.callout)
        }
    }
}

/// One numbered step, with its value to copy when it has one.
private struct WalkthroughStepRow: View {
    let number: Int
    let step: ConnectionWalkthrough.Step
    let copy: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: step.symbol)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    Text(step.text)
                }
                if let value = step.copyable {
                    CopyableValue(value: value, copy: copy)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 2)
        }
    }
}

/// A value to paste somewhere, with a Copy button that confirms itself.
struct CopyableValue: View {
    let value: String
    let copy: (String) -> Void
    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Button {
                copy(value)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .frame(minWidth: 64)
            }
            .controlSize(.small)
            .fixedSize()
            .help("Copy \u{201C}\(value)\u{201D} so you can paste it")
        }
    }
}

/// The screen just before a macOS prompt: what it will ask, which button
/// to click, and why it's safe. Its only button leads to the prompt.
struct ConnectionPrimingView: View {
    let kind: ConnectionKind
    let priming: ConnectionPriming
    let proceed: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ConnectionSheetHeader(kind: kind, light: nil, title: priming.title, message: priming.message)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(priming.points, id: \.self) { point in
                    Label {
                        Text(point)
                    } icon: {
                        Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                    }
                }
            }
            .font(.callout)
            HStack {
                Spacer()
                Button(priming.button, action: proceed)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .help("Your Mac asks next")
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

/// "Something not working?": runs the row's checks again and lists them
/// as plain questions and answers, with the row's one fix as the main
/// button and "Copy details" for writing to support.
struct ConnectionTroubleshootView: View {
    let kind: ConnectionKind
    /// Nil until the first check finishes.
    let diagnosis: ConnectionDiagnosis?
    let isChecking: Bool
    let perform: (ConnectionAction) -> Void
    let checkAgain: () -> Void
    let copyDetails: () -> Void
    let close: () -> Void
    @State private var copied = false

    private var light: ConnectionLight { isChecking ? .checking : diagnosis?.status.light ?? .checking }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ConnectionSheetHeader(kind: kind, light: light, title: "\(kind.title) checkup",
                                  message: isChecking || diagnosis == nil
                                      ? "Tabbi is checking \(kind.title) right now. This takes a second."
                                      : diagnosis?.verdict ?? "")

            if let diagnosis {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(diagnosis.checks.enumerated()), id: \.offset) { _, check in
                        TroubleshootCheckRow(check: check)
                    }
                }
                .opacity(isChecking ? 0.5 : 1)
            }

            Divider()

            HStack(spacing: 12) {
                Button {
                    copyDetails()
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy details", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .disabled(diagnosis == nil)
                .help("Copy what Tabbi found, to paste into a message if you ask someone for help")

                Spacer(minLength: 8)

                if let fix = diagnosis?.status.action, !isChecking {
                    Button("Not now", action: close)
                        .keyboardShortcut(.cancelAction)
                        .help("Close the checkup")
                    Button(fix.title) { perform(fix) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .help(fix.help(for: kind))
                } else {
                    Button("Check again", action: checkAgain)
                        .disabled(isChecking)
                        .help("Run the checks for \(kind.title) again")
                    Button("Done", action: close)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .help("Close the checkup")
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.spring(duration: 0.3), value: diagnosis)
        .animation(.spring(duration: 0.3), value: isChecking)
    }
}

/// One question and its answer, with an icon for how it went.
private struct TroubleshootCheckRow: View {
    let check: ConnectionCheck

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: check.outcome.symbol)
                .foregroundStyle(check.outcome.tint)
                .frame(width: 18)
                .help(check.outcome.help)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.question)
                    .fontWeight(.medium)
                Text(check.answer)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension ConnectionCheck.Outcome {
    var symbol: String {
        switch self {
        case .passed: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        case .skipped: "circle.dashed"
        case .note: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .passed: .green
        case .failed: .orange
        case .skipped: .secondary
        case .note: .blue
        }
    }

    var help: String {
        switch self {
        case .passed: "This part works"
        case .failed: "This is what needs fixing"
        case .skipped: "Not checked yet"
        case .note: "Optional"
        }
    }
}

/// The icon, title and message at the top of a Connections sheet.
struct ConnectionSheetHeader: View {
    let kind: ConnectionKind
    /// Tints the icon like the row's light; nil for the neutral blue.
    let light: ConnectionLight?
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: kind.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background((light?.tint ?? .blue).gradient,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(message)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension ConnectionStepAction {
    /// The start button's tooltip.
    var help: String {
        switch self {
        case .copyAndOpen(_, let app): "Copy what you need to paste, then open \(app.name)"
        case .openApp(let app): "Open \(app.name)"
        case .openSettings: "Open the right page in System Settings"
        }
    }
}
