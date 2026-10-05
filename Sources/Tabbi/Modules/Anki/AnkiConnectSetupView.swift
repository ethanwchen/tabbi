import SwiftUI
import TabbiKitCore
import TabbiKit

/// Onboarding's Anki step: the Anki tab's own connection guide, so the one
/// setup step that is missing (install Anki, open it, add AnkiConnect) is
/// fixed right here. Once AnkiConnect answers it confirms the connection
/// with today's due cards as the tab will show them.
struct AnkiConnectSetupView: View {
    @ObservedObject var store: AnkiStore

    var body: some View {
        content
            .motion(Theme.Motion.content, value: store.state)
            // Visible like the panel, so it checks again while the user sets up.
            .onAppear { store.panelDidAppear() }
            .onDisappear { store.panelDidDisappear() }
    }

    @ViewBuilder
    private var content: some View {
        if let summary = store.summary, store.state.keepsLastSummary {
            HStack(spacing: Theme.Spacing.m) {
                DueCard(summary: summary)
                    .frame(width: 240)
                AnkiConnectedCard(summary: summary)
            }
        } else if store.state == .checking {
            AnkiLoadingView()
        } else {
            AnkiSetupView(store: store, isCompact: true)
        }
    }
}

private var accent: Color { AnkiModule.descriptor.accentColor }

/// What the connection gives: where the due cards show up from now on.
private struct AnkiConnectedCard: View {
    let summary: AnkiSummary

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accent)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(accent.opacity(0.16)))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Anki is connected")
                            .font(Theme.Typography.bodyEmphasis)
                            .foregroundStyle(Theme.Palette.primaryText)
                        Text(deckLine)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(accent)
                            .monospacedDigit()
                    }
                    .lineLimit(1)
                }
                Text("The Anki tab shows your due cards, top decks and streak, and Today counts your reviews toward the day.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Label("Read through AnkiConnect on this Mac", systemImage: "lock.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .labelStyle(AnkiSetupLabelStyle())
                    .lineLimit(1)
                    .help("\(Edition.current.name) talks to Anki only on this Mac and never uploads your decks")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var deckLine: String {
        switch summary.topDecks.count {
        case 0: "Nothing due today"
        case 1: "1 deck with cards due"
        case let decks: "\(decks) decks with cards due"
        }
    }
}

/// A compact label: the icon close to its text.
private struct AnkiSetupLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Spacing.xxs + 1) {
            configuration.icon.font(.system(size: 8.5, weight: .bold))
            configuration.title
        }
    }
}
