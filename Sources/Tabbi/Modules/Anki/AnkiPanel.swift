import AppKit
import SwiftUI
import TabbiKitCore
import TabbiKit

/// The Anki tab. Connected, it shows today's due cards in a progress ring
/// (the panel's primary element), the decks with the most due, and a
/// footer with the streak, a two-week heatmap, Sync and Start reviews.
/// Until AnkiConnect answers it walks the user through the one setup step
/// that's missing.
struct AnkiPanel: View {
    @ObservedObject var store: AnkiStore

    var body: some View {
        content
            .motion(Theme.Motion.content, value: store.state)
            .onAppear { store.panelDidAppear() }
            .onDisappear { store.panelDidDisappear() }
    }

    @ViewBuilder
    private var content: some View {
        if let summary = store.summary, store.state.keepsLastSummary {
            AnkiDeckView(store: store, summary: summary)
        } else if store.state == .checking {
            AnkiLoadingView()
        } else {
            AnkiSetupView(store: store)
        }
    }
}

private var accent: Color { AnkiModule.descriptor.accentColor }

/// Anki's own colors for the three queues, so the numbers read the same as
/// in Anki's deck list.
private enum Queue {
    static let new = accent
    static let learning = Theme.Palette.danger
    static let review = Theme.Palette.success
}

// MARK: - Connected

private struct AnkiDeckView: View {
    @ObservedObject var store: AnkiStore
    let summary: AnkiSummary
    @State private var showsAllDecks = false

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                if !showsAllDecks {
                    DueCard(summary: summary)
                        .frame(width: 240)
                        .transition(.motionRow(from: .leading))
                }
                DecksCard(store: store, decks: summary.topDecks, showsAll: $showsAllDecks)
            }
            .frame(maxHeight: .infinity)
            AnkiFooter(store: store, summary: summary)
        }
        .motion(Theme.Motion.content, value: showsAllDecks)
        // Reviewing or a refresh can leave too few decks for the toggle to
        // show; collapse then, or the ring would stay hidden with no way back.
        .onChange(of: summary.topDecks.count) { _, count in
            if count <= DecksCard.collapsedCount { showsAllDecks = false }
        }
    }
}

/// Cards due today inside a ring of reviewed versus due, with the
/// new / learning / review split beside it.
private struct DueCard: View {
    let summary: AnkiSummary

    private static let diameter: CGFloat = 92
    private static let lineWidth: CGFloat = 7

    var body: some View {
        Card {
            HStack(spacing: Theme.Spacing.m) {
                ring
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    QueueRow(title: "New", count: summary.newDue, color: Queue.new)
                    QueueRow(title: "Learning", count: summary.learnDue, color: Queue.learning)
                    QueueRow(title: "Review", count: summary.reviewDue, color: Queue.review)
                    Rectangle()
                        .fill(Theme.Palette.stroke)
                        .frame(height: 0.5)
                        .padding(.vertical, Theme.Spacing.xxs)
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("Done")
                            .foregroundStyle(Theme.Palette.tertiaryText)
                        Spacer(minLength: 0)
                        Text("\(summary.reviewedToday)")
                            .foregroundStyle(Theme.Palette.secondaryText)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .font(Theme.Typography.caption)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .help(AnkiFormat.progressHelp(summary))
        .motion(Theme.Motion.content, value: summary)
    }

    private var ring: some View {
        ProgressRing(progress: summary.completionFraction,
                     tint: summary.dueTotal == 0 ? Theme.Palette.success : accent,
                     track: accent.opacity(0.2), lineWidth: Self.lineWidth) {
            if summary.dueTotal == 0 {
                VStack(spacing: Theme.Spacing.xxs) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Palette.success)
                    Text("All done")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                }
            } else {
                VStack(spacing: 0) {
                    Text("\(summary.dueTotal)")
                        .font(Theme.Typography.metric)
                        .foregroundStyle(Theme.Palette.primaryText)
                        .contentTransition(.numericText(countsDown: true))
                    Text("due")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                }
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
    }
}

private struct QueueRow: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .foregroundStyle(Theme.Palette.secondaryText)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: Theme.Spacing.s)
            Text("\(count)")
                .foregroundStyle(count > 0 ? Theme.Palette.primaryText : Theme.Palette.tertiaryText)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(Theme.Typography.body)
    }
}

/// The decks with the most due. Collapsed it fits the top four beside the
/// ring; expanded it takes the full width and scrolls.
private struct DecksCard: View {
    @ObservedObject var store: AnkiStore
    let decks: [AnkiDeckStats]
    @Binding var showsAll: Bool

    static let collapsedCount = 4

    var body: some View {
        Card(padding: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.xs) {
                    if let problem = store.problem {
                        StaleNotice(problem: problem, updatedAt: store.updatedAt)
                    } else {
                        Text(showsAll ? "All decks with cards due" : "Top decks")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.tertiaryText)
                    }
                    Spacer(minLength: Theme.Spacing.s)
                    if decks.count > Self.collapsedCount {
                        ExpandButton(showsAll: $showsAll, total: decks.count)
                    }
                }
                .frame(height: 18)
                .padding(.horizontal, Theme.Spacing.xs)
                if decks.isEmpty {
                    AllCaughtUp()
                } else if showsAll {
                    ScrollView(.vertical) {
                        rows(decks)
                    }
                    .scrollIndicators(.never)
                } else {
                    rows(Array(decks.prefix(Self.collapsedCount)))
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func rows(_ decks: [AnkiDeckStats]) -> some View {
        VStack(spacing: Theme.Spacing.xxs) {
            ForEach(decks, id: \.deckID) { deck in
                DeckRow(deck: deck) { store.startReviews(deck: deck.name) }
            }
        }
    }
}

/// Why the numbers may be out of date: the refresh or the last action
/// failed. The suggestion is in the tooltip.
private struct StaleNotice: View {
    let problem: AnkiConnectError
    let updatedAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Palette.warning)
                Text(updatedAt.map { "\(problem.title) · \(AnkiFormat.age($0, now: context.date))" } ?? problem.title)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(Theme.Typography.caption.monospacedDigit())
        }
        .help(problem.suggestion)
    }
}

private struct ExpandButton: View {
    @Binding var showsAll: Bool
    let total: Int
    @State private var hovering = false

    var body: some View {
        Button {
            showsAll.toggle()
        } label: {
            HStack(spacing: Theme.Spacing.xxs) {
                Text(showsAll ? "Show less" : "All \(total)")
                Image(systemName: showsAll ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
            .padding(.horizontal, Theme.Spacing.s)
            .frame(height: 18)
            .background(Capsule().fill(hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(showsAll ? "Show the top decks beside today's total" : "Show every deck with cards due")
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// One deck: its name and the three queue counts, like Anki's deck list.
/// Clicking it starts reviewing that deck in Anki.
private struct DeckRow: View {
    let deck: AnkiDeckStats
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                Text(deck.name)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Theme.Spacing.xs)
                if hovering {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(accent)
                        .transition(.opacity)
                }
                count(deck.newCount, color: Queue.new)
                count(deck.learnCount, color: Queue.learning)
                count(deck.reviewCount, color: Queue.review)
            }
            .padding(.horizontal, Theme.Spacing.xs)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                    .fill(hovering ? Theme.Palette.surfaceHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Review \(deck.name) in Anki: \(deck.newCount) new, \(deck.learnCount) learning, \(deck.reviewCount) review")
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }

    private func count(_ value: Int, color: Color) -> some View {
        Text("\(value)")
            .font(Theme.Typography.caption.monospacedDigit())
            .foregroundStyle(value > 0 ? color : Theme.Palette.tertiaryText)
            .frame(width: 26, alignment: .trailing)
    }
}

private struct AllCaughtUp: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.Palette.success)
            Text("Every deck is caught up")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Streak, heatmap, and the two actions.
private struct AnkiFooter: View {
    @ObservedObject var store: AnkiStore
    let summary: AnkiSummary

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
                StreakBadge(streak: summary.streak, reviewedToday: summary.hasReviewedToday)
                ReviewHeatmap(history: summary.history)
                Spacer(minLength: Theme.Spacing.xs)
                SyncButton(isSyncing: store.isSyncing, action: store.sync)
                AnkiPrimaryButton(title: "Start reviews", symbol: "play.fill",
                                  help: startHelp, action: { store.startReviews() })
                    .disabled(summary.dueTotal == 0)
                    .opacity(summary.dueTotal == 0 ? 0.4 : 1)
        }
        .frame(height: 28)
    }

    private var startHelp: String {
        guard let deck = summary.topDecks.first else { return "Nothing due today" }
        return "Open \(deck.name) for review in Anki"
    }
}

private struct StreakBadge: View {
    let streak: Int
    let reviewedToday: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "flame.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(streak > 0 ? Theme.Palette.warning : Theme.Palette.tertiaryText)
            Text(AnkiFormat.streak(streak))
                .font(Theme.Typography.caption.monospacedDigit())
                .foregroundStyle(Theme.Palette.secondaryText)
                .fixedSize()
        }
        .help(streak > 0 && !reviewedToday
              ? "Review today to keep your \(streak)-day streak"
              : "Days in a row with at least one review")
    }
}

/// Two weeks of reviews, one cell per day, today last and outlined.
private struct ReviewHeatmap: View {
    let history: [AnkiDayCount]

    private static let cell: CGFloat = 12

    var body: some View {
        let levels = AnkiFormat.heatLevels(for: history)
        let today = history.last?.day
        HStack(spacing: 3) {
            ForEach(Array(history.enumerated()), id: \.offset) { index, entry in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(color(level: levels[index]))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .strokeBorder(Theme.Palette.primaryText.opacity(entry.day == today ? 0.7 : 0), lineWidth: 1)
                    )
                    .frame(width: Self.cell, height: Self.cell)
                    .help(today.map { AnkiFormat.dayHelp(entry, today: $0) } ?? "")
            }
        }
    }

    private func color(level: Int) -> Color {
        guard level > 0 else { return Theme.Palette.surface }
        return accent.opacity(0.25 + 0.75 * Double(level) / Double(AnkiFormat.heatLevels))
    }
}

/// The shared `IconButton`, its glyph spinning while a sync runs.
private struct SyncButton: View {
    let isSyncing: Bool
    let action: () -> Void

    var body: some View {
        IconButton(symbol: "arrow.triangle.2.circlepath", size: 28,
                   help: isSyncing ? "Syncing with AnkiWeb…" : "Sync with AnkiWeb", action: action)
            .spinning(isSyncing)
        .disabled(isSyncing)
    }
}

// MARK: - Loading and setup

private struct AnkiLoadingView: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Spinner(tint: accent)
            Text("Looking for Anki…")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One screen per setup step: what's wrong in a line, the steps to fix it,
/// and a button for the next action. The panel flips to the deck view on
/// its own a few seconds after the step is done.
private struct AnkiSetupView: View {
    @ObservedObject var store: AnkiStore

    var body: some View {
        let guide = AnkiSetupGuide(state: store.state)
        Card(padding: Theme.Spacing.l) {
            HStack(alignment: .center, spacing: Theme.Spacing.l) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous)
                        .fill(accent.opacity(0.16))
                    if store.state == .starting {
                        PawLoader(tint: accent, size: 20, label: "Starting Anki")
                    } else {
                        Image(systemName: guide.symbol)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(guide.title)
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.Palette.primaryText)
                        Text(guide.message)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !guide.steps.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                                SetupStep(number: index + 1, text: step)
                            }
                        }
                    }
                    actions(guide)
                        .padding(.top, Theme.Spacing.xs)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func actions(_ guide: AnkiSetupGuide) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            switch store.state {
            case .notInstalled:
                AnkiPrimaryButton(title: "Get Anki", symbol: "arrow.down.circle.fill",
                                  help: "Open apps.ankiweb.net in your browser", action: store.getAnki)
            case .notRunning:
                AnkiPrimaryButton(title: "Open Anki", symbol: "arrow.up.forward.app.fill",
                                  help: "Open Anki; this tab connects on its own", action: store.openAnki)
            case .addOnMissing:
                CopyCodeButton(code: AnkiConnectClient.addOnCode)
                restartButton
            case .needsPermission, .addOnOutdated:
                restartButton
            case .problem:
                AnkiPrimaryButton(title: "Try again", symbol: "arrow.clockwise",
                                  help: "Ask Anki again", action: store.refresh)
            case .starting, .checking, .ready:
                EmptyView()
            }
            if let hint = guide.hint {
                Text(hint)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var restartButton: some View {
        AnkiSecondaryButton(title: store.isRestarting ? "Restarting…" : "Restart Anki",
                            symbol: "arrow.clockwise",
                            help: "Quit Anki and open it again so it loads AnkiConnect",
                            action: store.restartAnki)
            .disabled(store.isRestarting)
    }
}

/// The words for each setup screen. Kept edition-neutral so any kit can
/// include the Anki tab.
private struct AnkiSetupGuide {
    var symbol: String
    var title: String
    var message: String
    var steps: [String] = []
    var hint: String?

    init(state: AnkiConnectionState) {
        switch state {
        case .notInstalled:
            symbol = "arrow.down.app"
            title = "Anki isn't installed"
            message = "Install the free Anki desktop app to see your due cards, decks and streak here."
            hint = "Using a copy outside Applications? Just open it."
        case .notRunning:
            symbol = "power"
            title = "Anki is closed"
            message = "Open Anki to see today's due cards. This tab connects as soon as it's running."
        case .starting:
            symbol = "hourglass"
            title = "Connecting to Anki…"
            message = "Waiting for Anki to finish loading its add-ons."
        case .addOnMissing:
            symbol = "puzzlepiece.extension"
            title = "Add AnkiConnect to Anki"
            message = "This tab reads your decks through the free AnkiConnect add-on."
            steps = [
                "In Anki, choose Tools › Add-ons › Get Add-ons…",
                "Paste the code \(AnkiConnectClient.addOnCode) and click OK",
                "Restart Anki to load it",
            ]
        case .needsPermission(.apiKeyRequired):
            symbol = "key"
            title = "AnkiConnect wants an API key"
            message = "Its config sets an API key, which this tab doesn't send."
            steps = [
                "In Anki, choose Tools › Add-ons, select AnkiConnect, click Config",
                "Set \"apiKey\" to null, then click OK",
                "Restart Anki",
            ]
        case .needsPermission:
            symbol = "hand.raised"
            title = "AnkiConnect blocked this app"
            message = "Its settings turned the connection away."
            steps = [
                "In Anki, choose Tools › Add-ons, select AnkiConnect, click Config",
                "Click Restore Defaults, then OK",
                "Restart Anki",
            ]
        case .addOnOutdated:
            symbol = "arrow.triangle.2.circlepath"
            title = "Update AnkiConnect"
            message = "The installed AnkiConnect is too old for this tab."
            steps = [
                "In Anki, choose Tools › Add-ons",
                "Select AnkiConnect and click Check for Updates",
                "Restart Anki",
            ]
        case .problem(let error):
            symbol = "exclamationmark.triangle"
            title = error.title
            message = error.suggestion
        case .checking, .ready:
            symbol = "rectangle.stack"
            title = "Looking for Anki…"
            message = ""
        }
    }
}

private struct SetupStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text("\(number)")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .frame(width: 16, height: 16)
                .background(Circle().fill(accent.opacity(0.16)))
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

/// Copies the AnkiConnect code, confirming with a checkmark for a moment.
private struct CopyCodeButton: View {
    let code: String
    @State private var copied = false

    var body: some View {
        AnkiPrimaryButton(title: copied ? "Copied" : "Copy code \(code)",
                          symbol: copied ? "checkmark" : "doc.on.doc.fill",
                          help: "Copy the AnkiConnect add-on code to paste into Anki") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
            withMotion(Theme.Motion.snappy) { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withMotion(Theme.Motion.snappy) { copied = false }
            }
        }
    }
}

// MARK: - Controls

/// A filled accent capsule for the panel's one primary action.
private struct AnkiPrimaryButton: View {
    let title: String
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(Theme.Typography.bodyEmphasis)
                    .monospacedDigit()
                    .contentTransition(.opacity)
            }
            .foregroundStyle(Theme.Palette.background)
            .padding(.horizontal, Theme.Spacing.m)
            .frame(height: 28)
            .background(Capsule().fill(accent.opacity(hovering ? 1 : 0.88)))
            .contentShape(Capsule())
        }
        .buttonStyle(.tactile(.pill))
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// A quiet surface capsule for a secondary action.
private struct AnkiSecondaryButton: View {
    let title: String
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .font(Theme.Typography.bodyEmphasis)
            }
            .foregroundStyle(Theme.Palette.primaryText)
            .padding(.horizontal, Theme.Spacing.m)
            .frame(height: 28)
            .background(Capsule().fill(hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface))
            .contentShape(Capsule())
        }
        .buttonStyle(.tactile(.pill))
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}
