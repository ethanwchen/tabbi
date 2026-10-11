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
    @State private var showsAllDecks: Bool

    init(store: AnkiStore, summary: AnkiSummary) {
        self.store = store
        self.summary = summary
        _showsAllDecks = State(initialValue: store.previewsAllDecks)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            // On a narrow panel the ring card drops its queue names, so
            // the deck names beside it stay readable.
            ViewThatFits(in: .horizontal) {
                cards(compactRing: false)
                cards(compactRing: true)
            }
            .frame(maxHeight: .infinity)
            AnkiFooter(store: store, summary: summary)
        }
        .motion(Theme.Motion.content, value: showsAllDecks)
        // Reviewing or a refresh can leave too few decks for the toggle to
        // show; collapse then, or the ring would stay hidden with no way back.
        .onChange(of: summary.deckOutline.count) { _, count in
            if count <= DecksCard.collapsedCount { showsAllDecks = false }
        }
    }

    private func cards(compactRing: Bool) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            if !showsAllDecks {
                DueCard(summary: summary, isCompact: compactRing)
                    .frame(width: compactRing ? nil : 240)
                    .fixedSize(horizontal: compactRing, vertical: false)
                    .transition(.motionRow(from: .leading))
            }
            DecksCard(store: store, top: summary.topDecks, outline: summary.deckOutline, showsAll: $showsAllDecks)
                .frame(minWidth: compactRing ? 0 : DecksCard.minWidth, idealWidth: DecksCard.minWidth, maxWidth: .infinity)
        }
    }
}

/// Cards due today inside a ring of reviewed versus due, with the
/// new / learning / review split beside it.
struct DueCard: View {
    let summary: AnkiSummary
    /// Shows only each queue's dot and count (the names move to the
    /// tooltip), for a panel too narrow for the full split.
    var isCompact = false

    private static let diameter: CGFloat = 92
    private static let lineWidth: CGFloat = 7

    var body: some View {
        Card {
            HStack(spacing: Theme.Spacing.m) {
                ring
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    QueueRow(title: String(localized: "New", bundle: .tabbi), count: summary.newDue, color: Queue.new, showsTitle: !isCompact)
                    QueueRow(title: String(localized: "Learning", bundle: .tabbi), count: summary.learnDue, color: Queue.learning, showsTitle: !isCompact)
                    QueueRow(title: String(localized: "Review", bundle: .tabbi), count: summary.reviewDue, color: Queue.review, showsTitle: !isCompact)
                    Rectangle()
                        .fill(Theme.Palette.stroke)
                        .frame(height: 0.5)
                        .padding(.vertical, Theme.Spacing.xxs)
                    HStack(spacing: Theme.Spacing.xs) {
                        if isCompact {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.Palette.tertiaryText)
                        } else {
                            Text("Done", bundle: .tabbi)
                                .foregroundStyle(Theme.Palette.tertiaryText)
                        }
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
                    Text("All done", bundle: .tabbi)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                }
            } else {
                VStack(spacing: 0) {
                    Text("\(summary.dueTotal)")
                        .font(Theme.Typography.metric)
                        .foregroundStyle(Theme.Palette.primaryText)
                        .contentTransition(.numericText(countsDown: true))
                    Text("due", bundle: .tabbi)
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
    var showsTitle = true

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            if showsTitle {
                Text(title)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
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
/// ring; expanded it takes the full width, scrolls, and lists subdecks
/// under their parents so any exact deck is one click away.
private struct DecksCard: View {
    @ObservedObject var store: AnkiStore
    let top: [AnkiDeckStats]
    let outline: [AnkiDeckOutlineRow]
    @Binding var showsAll: Bool

    static let collapsedCount = 4
    /// The narrowest the card gets beside the full ring card before the
    /// ring card drops its queue names.
    static let minWidth: CGFloat = 240

    var body: some View {
        Card(padding: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                if top.isEmpty {
                    header(expandable: false)
                    AllCaughtUp()
                } else if showsAll {
                    header(expandable: true)
                    scrollingRows
                } else {
                    // A shorter panel (Compact) lists fewer decks instead of
                    // clipping the card, and offers All N for the rest.
                    RowsThatFit(top.prefix(Self.collapsedCount).map { AnkiDeckOutlineRow(deck: $0, depth: 0, title: $0.name) },
                                spacing: Theme.Spacing.xxs,
                                header: { shown in header(expandable: outline.count > shown) },
                                row: row)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func header(expandable: Bool) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let opening = store.opening, opening.phase == .launching {
                OpeningNotice(opening: opening)
            } else if let notice = store.openNotice {
                OpenNotice(outcome: notice)
            } else if let problem = store.problem {
                StaleNotice(problem: problem, updatedAt: store.updatedAt)
            } else {
                Text(showsAll ? String(localized: "All decks with cards due", bundle: .tabbi) : String(localized: "Top decks", bundle: .tabbi))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
            }
            Spacer(minLength: Theme.Spacing.s)
            if expandable {
                ExpandButton(showsAll: $showsAll, total: outline.count)
            }
        }
        .frame(height: 18)
        .padding(.horizontal, Theme.Spacing.xs)
    }

    /// `ImageRenderer` draws a `ScrollView` blank, so snapshots show the
    /// top of the outline clipped instead.
    @ViewBuilder
    private var scrollingRows: some View {
        if RunMode.current.isSnapshot {
            // Takes the space offered rather than the rows' full height.
            Color.clear
                .overlay(alignment: .top) { rows(outline) }
                .clipped()
        } else {
            ScrollView(.vertical) { rows(outline) }
                .scrollIndicators(.never)
        }
    }

    private func rows(_ rows: [AnkiDeckOutlineRow]) -> some View {
        VStack(spacing: Theme.Spacing.xxs) {
            ForEach(rows, content: row)
        }
    }

    private func row(_ row: AnkiDeckOutlineRow) -> some View {
        let deck = row.deck
        return DeckRow(row: row, isOpening: store.opening?.deck == deck.name,
                       isFavorite: store.favorite?.matches(deck) == true,
                       toggleFavorite: { store.toggleFavorite(deck) }) {
            store.startReviews(deck: deck.name)
        }
    }
}

/// Anki is starting after a click; the deck opens once it answers.
private struct OpeningNotice: View {
    let opening: AnkiOpening

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Spinner(tint: accent, size: 10, lineWidth: 1.5)
            Text("Opening Anki…", bundle: .tabbi)
                .foregroundStyle(Theme.Palette.secondaryText)
                .lineLimit(1)
        }
        .font(Theme.Typography.caption)
        .help(opening.deck.map { String(localized: "Waiting for Anki to start, then opening \($0)", bundle: .tabbi) } ?? String(localized: "Waiting for Anki to start", bundle: .tabbi))
    }
}

/// Why the last click didn't open its deck, with the next step in the tooltip.
private struct OpenNotice: View {
    let outcome: AnkiOpenOutcome

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: outcome == .addOnMissing ? "puzzlepiece.extension.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(outcome == .addOnMissing ? accent : Theme.Palette.warning)
            Text(outcome.title ?? "")
                .foregroundStyle(Theme.Palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(Theme.Typography.caption)
        .help(outcome.suggestion ?? "")
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
                Text(showsAll ? String(localized: "Show less", bundle: .tabbi) : String(localized: "All \(total)", bundle: .tabbi))
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
        .help(showsAll ? String(localized: "Show the top decks beside today's total", bundle: .tabbi) : String(localized: "Show every deck with cards due", bundle: .tabbi))
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// One deck: its name and the three queue counts, like Anki's deck list.
/// Clicking it starts reviewing that deck in Anki. The star, shown on
/// hover and always on the favorite, pins it as the Study button's deck.
private struct DeckRow: View {
    let row: AnkiDeckOutlineRow
    /// This deck's click is waiting for Anki to start.
    let isOpening: Bool
    let isFavorite: Bool
    let toggleFavorite: () -> Void
    let action: () -> Void
    @State private var hovering = false

    private var deck: AnkiDeckStats { row.deck }

    var body: some View {
        // A tap gesture rather than a Button, so the star inside stays its
        // own control.
        HStack(spacing: Theme.Spacing.s) {
            Text(row.title)
                .font(row.depth == 0 ? Theme.Typography.bodyEmphasis : Theme.Typography.body)
                .foregroundStyle(row.depth == 0 ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Theme.Spacing.xs)
            if hovering || isFavorite {
                FavoriteStar(isFavorite: isFavorite, deck: deck.name, action: toggleFavorite)
                    .transition(.opacity)
            }
            if isOpening {
                Spinner(tint: accent, size: 10, lineWidth: 1.5)
                    .transition(.opacity)
            } else if hovering {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(accent)
                    .transition(.opacity)
            }
            count(deck.newCount, color: Queue.new)
            count(deck.learnCount, color: Queue.learning)
            count(deck.reviewCount, color: Queue.review)
        }
        .padding(.leading, CGFloat(row.depth) * Theme.Spacing.m)
        .padding(.horizontal, Theme.Spacing.xs)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                .fill(hovering ? Theme.Palette.surfaceHover : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        // Combined, the bare counts read "Biology, 6, 2, 28"; say what they count.
        .accessibilityLabel(row.title)
        .accessibilityValue(String(localized: "\(deck.newCount) new, \(deck.learnCount) learning, \(deck.reviewCount) review", bundle: .tabbi))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: isFavorite ? String(localized: "Unpin favorite", bundle: .tabbi) : String(localized: "Pin as favorite", bundle: .tabbi), toggleFavorite)
        .help(String(localized: "Review \(deck.name) in Anki: \(deck.newCount) new, \(deck.learnCount) learning, \(deck.reviewCount) review", bundle: .tabbi))
        .contextMenu {
            Button(String(localized: "Review in Anki", bundle: .tabbi), action: action)
            Button(isFavorite ? String(localized: "Unpin Favorite Deck", bundle: .tabbi) : String(localized: "Pin as Favorite Deck", bundle: .tabbi), action: toggleFavorite)
        }
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: isFavorite)
    }

    private func count(_ value: Int, color: Color) -> some View {
        Text("\(value)")
            .font(Theme.Typography.caption.monospacedDigit())
            .foregroundStyle(value > 0 ? color : Theme.Palette.tertiaryText)
            .frame(width: 26, alignment: .trailing)
    }
}

/// Pins or unpins a deck as the favorite: filled in the accent when it is
/// the favorite, an outline on hover otherwise.
private struct FavoriteStar: View {
    let isFavorite: Bool
    let deck: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isFavorite || hovering ? "star.fill" : "star")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isFavorite ? accent : hovering ? Theme.Palette.primaryText : Theme.Palette.tertiaryText)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isFavorite ? String(localized: "Unpin \(deck) from the Study button", bundle: .tabbi) : String(localized: "Pin \(deck) to the Study button", bundle: .tabbi))
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

private struct AllCaughtUp: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.Palette.success)
            Text("Every deck is caught up", bundle: .tabbi)
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
                // The latest days that fit, so a long favorite deck name
                // keeps its button readable.
                ViewThatFits(in: .horizontal) {
                    ForEach([14, 10, 7], id: \.self) { days in
                        ReviewHeatmap(history: Array(summary.history.suffix(days)))
                    }
                    // On a narrow panel the streak alone stays.
                    Color.clear.frame(width: 0, height: 0)
                }
                Spacer(minLength: Theme.Spacing.xs)
                SyncButton(isSyncing: store.isSyncing, action: store.sync)
                if let favorite = store.favorite {
                    studyButton(favorite)
                } else {
                    AnkiPrimaryButton(title: String(localized: "Start reviews", bundle: .tabbi), symbol: "play.fill",
                                      help: startHelp, action: { store.startReviews() })
                        .disabled(summary.dueTotal == 0)
                        .opacity(summary.dueTotal == 0 ? 0.4 : 1)
                }
        }
        .frame(height: 28)
    }

    /// The favorite deck in one click, with what it has due. Stays enabled
    /// with nothing due: Anki then offers its own "Congratulations" screen
    /// and custom study.
    private func studyButton(_ favorite: AnkiFavoriteDeck) -> some View {
        let deck = store.favoriteDeck
        let name = deck?.name ?? favorite.name
        let due = deck?.dueTotal ?? 0
        let help = due > 0
            ? String(localized: "Review \(name) in Anki: \(due) due. Pin another deck with its star.", bundle: .tabbi)
            : String(localized: "Open \(name) in Anki. Nothing is due there today.", bundle: .tabbi)
        return AnkiPrimaryButton(title: String(localized: "Study \(AnkiDeckName.leaf(name))", bundle: .tabbi), symbol: "play.fill",
                                 badge: due > 0 ? due : nil, help: help, action: store.studyFavorite)
            .layoutPriority(1)
    }

    private var startHelp: String {
        guard let deck = summary.topDecks.first else { return String(localized: "Nothing due today", bundle: .tabbi) }
        return String(localized: "Open \(deck.name) for review in Anki", bundle: .tabbi)
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
              ? String(localized: "Review today to keep your \(streak)-day streak", bundle: .tabbi)
              : String(localized: "Days in a row with at least one review", bundle: .tabbi))
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
                   help: isSyncing ? String(localized: "Syncing with AnkiWeb…", bundle: .tabbi) : String(localized: "Sync with AnkiWeb", bundle: .tabbi), action: action)
            .spinning(isSyncing)
        .disabled(isSyncing)
    }
}

// MARK: - Loading and setup

struct AnkiLoadingView: View {
    var body: some View {
        StatusMessage(symbol: nil, tint: accent, title: String(localized: "Looking for Anki…", bundle: .tabbi),
                      message: String(localized: "Your cards due today show up here.", bundle: .tabbi))
    }
}

/// One screen per setup step: what's wrong in a line, the steps to fix it,
/// and a button for the next action. The panel flips to the deck view on
/// its own a few seconds after the step is done.
struct AnkiSetupView: View {
    @ObservedObject var store: AnkiStore
    /// Fits onboarding's shorter body (under its footer): a step list
    /// replaces the message line and the rows sit closer.
    var isCompact = false

    var body: some View {
        let guide = AnkiSetupGuide(state: store.state, opening: store.opening, notice: store.openNotice)
        let showsMessage = !(isCompact && !guide.steps.isEmpty)
        Card(padding: isCompact ? Theme.Spacing.m : Theme.Spacing.l) {
            HStack(alignment: .center, spacing: Theme.Spacing.l) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous)
                        .fill(accent.opacity(0.16))
                    if store.opening != nil {
                        Spinner(tint: accent, size: 20)
                    } else if store.state == .starting {
                        PawLoader(tint: accent, size: 20, label: String(localized: "Starting Anki", bundle: .tabbi))
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
                        if showsMessage {
                            Text(guide.message)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Palette.secondaryText)
                                .lineLimit(2)
                        }
                    }
                    // In a short panel (Compact) the message gives up a line
                    // before the steps and buttons do; the tooltip keeps it whole.
                    .help(guide.message)
                    if !guide.steps.isEmpty {
                        VStack(alignment: .leading, spacing: isCompact ? Theme.Spacing.xxs : Theme.Spacing.xs) {
                            ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                                SetupStep(number: index + 1, text: step)
                            }
                        }
                        .layoutPriority(1)
                    }
                    actions(guide)
                        .padding(.top, isCompact ? 0 : Theme.Spacing.xs)
                        .layoutPriority(1)
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
            case _ where store.opening != nil:
                EmptyView()
            case .notRunning:
                if let favorite = store.favorite {
                    // Anki is closed, so the favorite opens by its stored
                    // name: one click launches Anki and opens that deck.
                    AnkiPrimaryButton(title: String(localized: "Study \(AnkiDeckName.leaf(favorite.name))", bundle: .tabbi), symbol: "play.fill",
                                      help: String(localized: "Open Anki straight into \(favorite.name)", bundle: .tabbi), action: store.studyFavorite)
                    AnkiSecondaryButton(title: String(localized: "Open Anki", bundle: .tabbi), symbol: "arrow.up.forward.app",
                                        help: String(localized: "Open Anki; this tab connects on its own", bundle: .tabbi), action: store.openAnki)
                } else {
                    AnkiPrimaryButton(title: String(localized: "Open Anki", bundle: .tabbi), symbol: "arrow.up.forward.app.fill",
                                      help: String(localized: "Open Anki; this tab connects on its own", bundle: .tabbi), action: store.openAnki)
                }
            case .notInstalled:
                AnkiPrimaryButton(title: String(localized: "Get Anki", bundle: .tabbi), symbol: "arrow.down.circle.fill",
                                  help: String(localized: "Open apps.ankiweb.net in your browser", bundle: .tabbi), action: store.getAnki)
            case .addOnMissing:
                CopyCodeButton(code: AnkiConnectClient.addOnCode)
                restartButton
            case .needsPermission, .addOnOutdated:
                restartButton
            case .problem:
                AnkiPrimaryButton(title: String(localized: "Try again", bundle: .tabbi), symbol: "arrow.clockwise",
                                  help: String(localized: "Ask Anki again", bundle: .tabbi), action: store.refresh)
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
        AnkiSecondaryButton(title: store.isRestarting ? String(localized: "Restarting…", bundle: .tabbi) : String(localized: "Restart Anki", bundle: .tabbi),
                            symbol: "arrow.clockwise",
                            help: String(localized: "Quit Anki and open it again so it loads AnkiConnect", bundle: .tabbi),
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

    init(state: AnkiConnectionState, opening: AnkiOpening?, notice: AnkiOpenOutcome? = nil) {
        if let opening {
            // A click is launching Anki to open a deck: say which, so the
            // wait reads as progress rather than a setup step.
            symbol = "rectangle.stack"
            title = opening.deck.map { String(localized: "Opening \(AnkiDeckName.leaf($0))…", bundle: .tabbi) } ?? String(localized: "Opening Anki…", bundle: .tabbi)
            message = opening.phase == .launching
                ? String(localized: "Anki is starting. The deck opens for review as soon as it's ready.", bundle: .tabbi)
                : String(localized: "Asking Anki to open the deck for review.", bundle: .tabbi)
            return
        }
        switch state {
        case .notInstalled:
            symbol = "arrow.down.app"
            title = String(localized: "Anki isn't installed", bundle: .tabbi)
            message = String(localized: "Install the free Anki desktop app to see your due cards, decks and streak here.", bundle: .tabbi)
            hint = String(localized: "Using a copy outside Applications? Just open it.", bundle: .tabbi)
        case .notRunning where notice == .launchFailed:
            // A click tried to launch Anki and macOS refused: say so, or
            // the screen would look as if the click did nothing.
            symbol = "exclamationmark.triangle"
            title = AnkiOpenOutcome.launchFailed.title ?? String(localized: "Anki wouldn't open", bundle: .tabbi)
            message = AnkiOpenOutcome.launchFailed.suggestion ?? ""
        case .notRunning:
            symbol = "power"
            title = String(localized: "Anki is closed", bundle: .tabbi)
            message = String(localized: "Open Anki to see today's due cards. This tab connects as soon as it's running.", bundle: .tabbi)
        case .starting:
            symbol = "hourglass"
            title = String(localized: "Connecting to Anki…", bundle: .tabbi)
            message = String(localized: "Waiting for Anki to finish loading its add-ons.", bundle: .tabbi)
        case .addOnMissing where notice == .addOnMissing:
            // A click opened Anki but couldn't open its deck: name the one
            // step left. The store already put the code on the clipboard.
            symbol = "puzzlepiece.extension"
            title = String(localized: "One step to open decks from here", bundle: .tabbi)
            message = String(localized: "Install the AnkiConnect add-on to open decks directly.", bundle: .tabbi)
            steps = [
                String(localized: "In Anki, choose Tools › Add-ons › Get Add-ons…", bundle: .tabbi),
                String(localized: "Paste the code \(AnkiConnectClient.addOnCode) (copied) and click OK", bundle: .tabbi),
                String(localized: "Restart Anki, then click the deck again", bundle: .tabbi),
            ]
        case .addOnMissing:
            symbol = "puzzlepiece.extension"
            title = String(localized: "Add AnkiConnect to Anki", bundle: .tabbi)
            message = String(localized: "This tab reads your decks through the free AnkiConnect add-on.", bundle: .tabbi)
            steps = [
                String(localized: "In Anki, choose Tools › Add-ons › Get Add-ons…", bundle: .tabbi),
                String(localized: "Paste the code \(AnkiConnectClient.addOnCode) and click OK", bundle: .tabbi),
                String(localized: "Restart Anki to load it", bundle: .tabbi),
            ]
        case .needsPermission(.apiKeyRequired):
            symbol = "key"
            title = String(localized: "AnkiConnect wants an API key", bundle: .tabbi)
            message = String(localized: "Its config sets an API key, which this tab doesn't send.", bundle: .tabbi)
            steps = [
                String(localized: "In Anki, choose Tools › Add-ons › AnkiConnect › Config", bundle: .tabbi),
                String(localized: "Set \"apiKey\" to null, then click OK", bundle: .tabbi),
                String(localized: "Restart Anki", bundle: .tabbi),
            ]
        case .needsPermission:
            symbol = "hand.raised"
            title = String(localized: "AnkiConnect blocked this app", bundle: .tabbi)
            message = String(localized: "Its settings turned the connection away.", bundle: .tabbi)
            steps = [
                String(localized: "In Anki, choose Tools › Add-ons › AnkiConnect › Config", bundle: .tabbi),
                String(localized: "Click Restore Defaults, then OK", bundle: .tabbi),
                String(localized: "Restart Anki", bundle: .tabbi),
            ]
        case .addOnOutdated:
            symbol = "arrow.triangle.2.circlepath"
            title = String(localized: "Update AnkiConnect", bundle: .tabbi)
            message = String(localized: "The installed AnkiConnect is too old for this tab.", bundle: .tabbi)
            steps = [
                String(localized: "In Anki, choose Tools › Add-ons", bundle: .tabbi),
                String(localized: "Select AnkiConnect and click Check for Updates", bundle: .tabbi),
                String(localized: "Restart Anki", bundle: .tabbi),
            ]
        case .problem(let error):
            symbol = "exclamationmark.triangle"
            title = error.title
            message = error.suggestion
        case .checking, .ready:
            symbol = "rectangle.stack"
            title = String(localized: "Looking for Anki…", bundle: .tabbi)
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
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .frame(width: 16, height: 16)
                .background(Circle().fill(accent.opacity(0.16)))
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(text)
        }
    }
}

/// Copies the AnkiConnect code, confirming with a checkmark for a moment.
private struct CopyCodeButton: View {
    let code: String
    @State private var copied = false

    var body: some View {
        AnkiPrimaryButton(title: copied ? String(localized: "Copied", bundle: .tabbi) : String(localized: "Copy code \(code)", bundle: .tabbi),
                          symbol: copied ? "checkmark" : "doc.on.doc.fill",
                          help: String(localized: "Copy the AnkiConnect add-on code to paste into Anki", bundle: .tabbi)) {
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
    /// A count shown after the title, such as the favorite deck's due cards.
    var badge: Int?
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
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.opacity)
                if let badge {
                    Text("\(badge)")
                        .font(Theme.Typography.caption.weight(.bold).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                        .padding(.horizontal, Theme.Spacing.xs)
                        .frame(height: 16)
                        .background(Capsule().fill(Theme.Palette.background.opacity(0.18)))
                        .fixedSize()
                }
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
