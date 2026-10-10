import SwiftUI
import TabbiKitCore
import TabbiKit

/// The Connections pane in Settings: one row per app or permission the
/// current tabs use, each with a live light and the one button that fixes
/// its current state.
struct ConnectionsSettingsPane: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.aiService) private var ai
    @State private var showsMore = false

    var body: some View {
        let enabled = settings.settings.modules.enabled
        // The AI choice shows while a tab with AI features is on.
        let aiChoice = enabled.contains(where: AIService.featureModules.contains) ? ai : nil
        let model = aiChoice?.setupState.provider
        let kinds = ConnectionKind.relevant(to: enabled, localTools: Edition.current.runsLocalTools,
                                            usesClaudeCode: model == .claudeCLI)
        Form {
            // First, so Ask's Choose AI button lands on it.
            if let aiChoice {
                AIProviderSection(ai: aiChoice)
            }
            Section {
                ConnectionsList(kinds: kinds)
            } header: {
                Text("Apps and permissions")
            } footer: {
                SectionFooter("Fixed something in another app? Come back here and the light updates by itself.")
            }
            // The advanced settings here: the AI model and where claude lives.
            if kinds.contains(.claude) || model != nil {
                Section {
                    MoreOptionsToggle(isExpanded: $showsMore)
                }
                if showsMore {
                    if let model {
                        AIModelSection(provider: model)
                            .id(model)
                    }
                    if kinds.contains(.claude) {
                        ClaudeLocationSection()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .motion(Motion.snappy, value: showsMore)
        .connectionsHost(watching: kinds)
        // Matches the other panes' width; scrolls when many tabs are on.
        .frame(width: paneWidth, height: 520)
    }
}

/// The rows for some connections. Onboarding and the tabs' empty states
/// can embed it with just the rows they need, inside a container that has
/// `.connectionsHost(watching:)` with the same rows, which opens their
/// sheets and keeps them checked.
struct ConnectionsList: View {
    let kinds: [ConnectionKind]
    @ObservedObject var store: ConnectionsStore = .shared
    @EnvironmentObject private var sheets: ConnectionSheetPresenter

    var body: some View {
        if kinds.isEmpty {
            Text("None of your tabs need another app right now.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(kinds) { kind in
                ConnectionRow(kind: kind, status: store.status(of: kind),
                              test: kind == .doNotDisturb ? store.doNotDisturbTest : nil,
                              perform: { sheets.perform($0, for: kind, in: store) },
                              troubleshoot: { sheets.show(.troubleshoot(kind)) })
            }
        }
    }
}

/// Which Connections sheet is open. One per host rather than per row: in
/// a Form, modifiers on a list's rows land on every row, so each row would
/// get its own sheet and its own watcher.
@MainActor
final class ConnectionSheetPresenter: ObservableObject {
    @Published var sheet: ConnectionSheet?
    /// A sheet to open once the current one has closed (the troubleshooter
    /// handing over to a walkthrough), since only one shows at a time.
    private var nextSheet: ConnectionSheet?

    func show(_ next: ConnectionSheet) {
        if sheet == nil {
            sheet = next
        } else {
            nextSheet = next
            sheet = nil
        }
    }

    /// Runs a row's button, opening its sheet when it has one. From inside
    /// a sheet, the current sheet closes first and the next follows.
    func perform(_ action: ConnectionAction, for kind: ConnectionKind, in store: ConnectionsStore) {
        guard let next = ConnectionSheet(action, for: kind, status: store.status(of: kind)) else {
            store.perform(action, for: kind)
            return
        }
        show(next)
    }

    func showNextSheet() {
        guard let next = nextSheet else { return }
        nextSheet = nil
        sheet = next
    }
}

/// Opens the sheets of the `ConnectionsList`s inside, and checks the
/// connections they show while shown (and on every return to Tabbi).
private struct ConnectionsHost: ViewModifier {
    let kinds: [ConnectionKind]
    @ObservedObject var store: ConnectionsStore
    @StateObject private var sheets = ConnectionSheetPresenter()

    func body(content: Content) -> some View {
        content
            .environmentObject(sheets)
            .onAppear { store.beginWatching(kinds) }
            .onDisappear { store.endWatching(kinds) }
            .onChange(of: kinds) { old, new in
                store.beginWatching(new)
                store.endWatching(old)
            }
            .sheet(item: $sheets.sheet, onDismiss: sheets.showNextSheet) {
                ConnectionSheetView(sheet: $0, store: store, perform: { sheets.perform($0, for: $1, in: store) })
            }
    }
}

extension View {
    /// Hosts the `ConnectionsList`s inside this view, which show `kinds`.
    /// Apply it once, to the container (a Form or a stack), never to the
    /// list itself.
    func connectionsHost(watching kinds: [ConnectionKind], _ store: ConnectionsStore = .shared) -> some View {
        modifier(ConnectionsHost(kinds: kinds, store: store))
    }
}

/// One connection: what it unlocks, its light, where it stands and the
/// button for the next step.
struct ConnectionRow: View {
    let kind: ConnectionKind
    let status: ConnectionStatus
    /// The latest "Test it" result, for the Do Not Disturb row.
    var test: DoNotDisturbTest?
    let perform: (ConnectionAction) -> Void
    /// Opens the "Something not working?" troubleshooter.
    let troubleshoot: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: kind.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(status.light.tint.gradient,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(kind.title)
                        .fontWeight(.semibold)
                    ConnectionLightBadge(light: status.light)
                }
                Text(kind.unlocks)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if !status.isConnected {
                    Text("\(Text(status.headline).fontWeight(.medium)). \(status.detail)")
                        .font(.callout)
                        .padding(.top, 2)
                } else if case .copyFriendCode(let code) = status.suggestion {
                    Text("Your friend code: \(Text(code).fontWeight(.semibold).monospacedDigit())")
                        .font(.callout)
                        .textSelection(.enabled)
                        .padding(.top, 2)
                }
                if status.isConnected, let test {
                    DoNotDisturbTestLine(test: test)
                        .padding(.top, 2)
                }
                Button("Something not working?", action: troubleshoot)
                    .buttonStyle(.link)
                    .font(.caption)
                    .padding(.top, 2)
                    .help("Run a checkup on \(kind.title) and see what's wrong, in plain words")
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if let action = status.action {
                Button(action.title) { perform(action) }
                    .buttonStyle(.borderedProminent)
                    .help(action.help(for: kind))
            } else if let suggestion = status.suggestion {
                Button(suggestion.title) { perform(suggestion) }
                    .disabled(test?.isRunning == true)
                    .help(suggestion.help(for: kind))
            }
        }
        .padding(.vertical, 4)
        .animation(.spring(duration: 0.3), value: status)
        .accessibilityElement(children: .combine)
    }
}

/// Where the Do Not Disturb test stands: a spinner while it runs, then a
/// green check or an orange warning with one plain sentence.
struct DoNotDisturbTestLine: View {
    let test: DoNotDisturbTest

    var body: some View {
        Label {
            Text(test.message)
                .foregroundStyle(test.isRunning ? .secondary : .primary)
        } icon: {
            if test.isRunning {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: test.isFailure ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(test.isFailure ? .orange : .green)
            }
        }
        .font(.callout)
        .help(test.isFailure ? "Fix the shortcut in the Shortcuts app, then test again"
                             : "What happened when Tabbi ran your shortcuts")
    }
}

/// The colored dot and words for a light.
struct ConnectionLightBadge: View {
    let light: ConnectionLight

    var body: some View {
        HStack(spacing: 4) {
            if light == .checking {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Circle()
                    .fill(light.tint)
                    .frame(width: 7, height: 7)
            }
            Text(light.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(light == .connected ? light.tint : .secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(light.tint.opacity(0.14), in: Capsule())
        .help(light.help)
    }
}

extension ConnectionLight {
    var tint: Color {
        switch self {
        case .checking: .gray
        case .connected: .green
        case .needsStep: .orange
        case .notSetUp: .blue
        case .notInstalled: .gray
        }
    }

    var help: String {
        switch self {
        case .checking: "Tabbi is checking this right now"
        case .connected: "This works. Nothing to do."
        case .needsStep: "Almost there: one thing left to do"
        case .notSetUp: "Not connected to Tabbi yet"
        case .notInstalled: "The app this needs isn't on this Mac"
        }
    }
}

extension ConnectionAction {
    /// The button's tooltip: what pressing it does.
    func help(for kind: ConnectionKind) -> String {
        switch self {
        case .download(let app): "Open the official page to download \(app.name)"
        case .openApp(let app): "Open \(app.name), then Tabbi checks again"
        case .showGuide: "Walk through the steps to connect \(kind.title)"
        case .askPermission: "macOS asks once whether Tabbi may use \(kind.title)"
        case .openSettings: "Open the right page in System Settings"
        case .checkAgain: "Check \(kind.title) again"
        case .setUp: "Set up \(kind.title)"
        case .copyFriendCode: "Copy your friend code to send to a friend"
        case .testDoNotDisturb: "Turn Do Not Disturb on for a moment, then off again"
        case .turnOnDoNotDisturb: "Turn on Do Not Disturb whenever the focus timer runs"
        }
    }
}
