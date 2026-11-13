import SwiftUI
import TabbiKitCore
import TabbiKit

/// The Party tab's Crews mode (the Crews UI spec): one card with a pill row
/// (the Party glyph, then My crew, This week, Hall of Fame and Find) and the
/// screen under it, or a pushed crew page or crest editor with a back pill.
struct CrewsPanel: View {
    @ObservedObject var crews: CrewsStore
    var focus: FocusState<PartyField?>.Binding
    @EnvironmentObject private var notch: NotchViewModel

    private var state: CrewsState { crews.state }

    var body: some View {
        Card(padding: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: CrewLayout.headGap) {
                screen
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .environment(\.crewIsCompact, notch.panelSize == .compact)
        .overlay(alignment: .topTrailing) { moreMenu }
        .motion(Theme.Motion.content, value: screenID)
    }

    /// Which screen shows, for the content crossfade.
    private var screenID: String {
        switch state.pushed {
        case .crew(let crew, _): "crew-" + crew.id
        case .editor(let editing, _): editing ? "edit" : "create"
        case nil: state.section.rawValue
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch state.pushed {
        case .crew(let crew, let from):
            CrewPageScreen(crews: crews, crew: crew, from: from)
                .transition(.opacity)
        case .editor(let editing, let from):
            CrewEditorScreen(crews: crews, editing: editing, from: from, focus: focus)
                .transition(.opacity)
        case nil:
            CrewPillRow(crews: crews)
            sectionBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var sectionBody: some View {
        if let error = state.loadError, error.isTransient, !hasContent {
            CrewStatus(symbol: "wifi.slash", title: String(localized: "Can't reach the party server", bundle: .tabbi),
                       detail: String(localized: "Check your internet connection. Crews show up once it's back.", bundle: .tabbi)) {
                CrewButton(title: String(localized: "Try again", bundle: .tabbi), height: 24,
                           help: String(localized: "Connect to the party server now", bundle: .tabbi)) { crews.retry() }
            }
        } else {
            switch state.section {
            case .mine: CrewMineScreen(crews: crews)
            case .week: CrewWeekScreen(crews: crews)
            case .hall: CrewHallScreen(crews: crews)
            case .find: CrewFindScreen(crews: crews, focus: focus)
            }
        }
    }

    /// Whether the open section has something to show despite an error.
    private var hasContent: Bool {
        switch state.section {
        case .mine: state.mineLoaded
        case .week: state.board != nil
        case .hall: state.hall != nil
        case .find: state.results != nil
        }
    }

    /// My crew's small in-panel menu, under its More button.
    @ViewBuilder
    private var moreMenu: some View {
        if crews.showsMoreMenu, state.pushed == nil, state.section == .mine, let mine = state.mine {
            VStack(alignment: .leading, spacing: 1) {
                if mine.owner {
                    CrewMenuItem(title: String(localized: "Edit crew", bundle: .tabbi), symbol: "pencil") {
                        crews.openEditor(editing: true)
                    }
                }
                if let me = mine.me {
                    CrewMenuItem(title: me.pet == nil ? String(localized: "Show My Pet on Crew Pages", bundle: .tabbi)
                                 : String(localized: "Hide My Pet on Crew Pages", bundle: .tabbi),
                                 symbol: me.pet == nil ? "eye" : "eye.slash") {
                        crews.showsMoreMenu = false
                        crews.setShowsPet(me.pet == nil)
                    }
                }
                CrewMenuItem(title: String(localized: "Leave crew", bundle: .tabbi), symbol: "xmark", isDanger: true) {
                    crews.leave()
                }
            }
            .padding(4)
            .frame(minWidth: 120)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).fill(Color(white: 0.12)))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).strokeBorder(Theme.Palette.stroke, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.45), radius: 12, y: 8)
            .padding(.top, 34)
            .padding(.trailing, 8)
            .fixedSize()
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
        }
    }
}

/// One item of the in-panel menu.
private struct CrewMenuItem: View {
    let title: String
    let symbol: String
    var isDanger = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 9.5, weight: .bold)).frame(width: 12)
                Text(title).font(Theme.Typography.body).lineLimit(1).fixedSize()
                Spacer(minLength: 0)
            }
            .foregroundStyle(isDanger ? Theme.Palette.danger : Theme.Palette.primaryText)
            .padding(.horizontal, Theme.Spacing.s)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous).fill(hovering ? Theme.Palette.surfaceHover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Pill row

/// The section pills and the open section's trailing items. Titles show on
/// every pill while the row fits, then only on the open pill, then on none
/// (the Closet's rule); the trailing caption gives way last.
struct CrewPillRow: View {
    @ObservedObject var crews: CrewsStore

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(titles: .all, trailing: true)
            row(titles: .open, trailing: true)
            row(titles: .none, trailing: true)
            row(titles: .none, trailing: false)
        }
        .frame(height: CrewLayout.headHeight)
    }

    private enum Titles { case all, open, none }

    private func row(titles: Titles, trailing: Bool) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.xxs) {
                CrewPill(title: String(localized: "Party", bundle: .tabbi), symbol: "person.3.fill", showsTitle: false,
                         help: String(localized: "Back to your party and friends", bundle: .tabbi)) {
                    withMotion(Theme.Motion.content) { crews.setShowsCrews(false) }
                }
                Rectangle().fill(Theme.Palette.stroke).frame(width: 0.5, height: 14).padding(.horizontal, 4)
                ForEach(CrewsState.Section.allCases, id: \.self) { section in
                    let open = crews.state.section == section
                    CrewPill(title: section.title, symbol: section.symbol,
                             showsTitle: titles == .all || (titles == .open && open), isSelected: open, help: section.help) {
                        withMotion(Theme.Motion.content) { crews.show(section) }
                    }
                    .overlay(alignment: .topTrailing) {
                        if section == .mine && crews.waitingRequests > 0 && !open {
                            Circle().fill(PartyStyle.accent).frame(width: 5, height: 5).offset(x: -3, y: 3)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            .fixedSize()
            Spacer(minLength: Theme.Spacing.xs)
            if trailing { CrewPillRowTrailing(crews: crews) }
        }
    }
}

/// What the open section shows at the end of the pill row.
private struct CrewPillRowTrailing: View {
    @ObservedObject var crews: CrewsStore

    var body: some View {
        switch crews.state.section {
        case .week:
            Text(CrewFormat.countdown(crews.state.week, now: crews.now))
                .font(Theme.Typography.caption.monospacedDigit())
                .foregroundStyle(Theme.Palette.tertiaryText)
                .lineLimit(1).fixedSize()
                .help(String(localized: "The week runs Monday to Sunday (UTC). Ends \(CrewFormat.weekEnd(crews.state.week)). The top 3 wear a laurel next week.", bundle: .tabbi))
        case .hall:
            Text("Every Sunday's top 3 earn a medal", bundle: .tabbi)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.tertiaryText)
                .lineLimit(1).fixedSize()
                .help(String(localized: "Ranked by golds, then silvers, then bronzes, then whoever reached the tally first.", bundle: .tabbi))
        case .find:
            CrewButton(title: String(localized: "Create a crew", bundle: .tabbi), symbol: "plus",
                       isEnabled: !crews.state.inCrew,
                       help: crews.state.inCrew ? String(localized: "Leave your crew to start a new one", bundle: .tabbi)
                           : String(localized: "Make a crew and invite friends", bundle: .tabbi)) {
                crews.openEditor(editing: false)
            }
        case .mine:
            if let mine = crews.state.mine {
                HStack(spacing: 4) {
                    if let code = mine.inviteCode, let invite = CrewInvite(code: code) { CrewInviteButton(invite: invite) }
                    CrewIconButton(symbol: "ellipsis", help: String(localized: "More", bundle: .tabbi)) {
                        withMotion(Theme.Motion.snappy) { crews.showsMoreMenu.toggle() }
                    }
                }
                .fixedSize()
            }
        }
    }
}

extension CrewsState.Section {
    var title: String {
        switch self {
        case .mine: String(localized: "My crew", bundle: .tabbi)
        case .week: String(localized: "This week", bundle: .tabbi)
        case .hall: String(localized: "Hall of Fame", bundle: .tabbi)
        case .find: String(localized: "Find", bundle: .tabbi)
        }
    }

    var symbol: String {
        switch self {
        case .mine: "shield"
        case .week: "calendar"
        case .hall: "medal"
        case .find: "magnifyingglass"
        }
    }

    var help: String {
        switch self {
        case .mine: String(localized: "Your crew and its members", bundle: .tabbi)
        case .week: String(localized: "This week's leaderboard", bundle: .tabbi)
        case .hall: String(localized: "Medals from every week's top 3", bundle: .tabbi)
        case .find: String(localized: "Find crews", bundle: .tabbi)
        }
    }
}

/// The back pill of a pushed screen, naming the section it returns to.
struct CrewBackPill: View {
    @ObservedObject var crews: CrewsStore
    let from: CrewsState.Section
    @State private var hovering = false

    var body: some View {
        Button { withMotion(Theme.Motion.content) { crews.pop() } } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.backward").font(.system(size: 8, weight: .bold))
                Text(from == .find ? String(localized: "Find crews", bundle: .tabbi) : from.title).lineLimit(1).fixedSize()
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
            .padding(.horizontal, Theme.Spacing.s)
            .frame(height: CrewLayout.headHeight)
            .background(Capsule().fill(hovering ? Theme.Palette.surfaceHover : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(String(localized: "Back", bundle: .tabbi))
        .onHover { hovering = $0 }
        .fixedSize()
    }
}
