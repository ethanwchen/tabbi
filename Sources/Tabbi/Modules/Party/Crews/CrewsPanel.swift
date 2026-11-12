import SwiftUI
import TabbiKitCore
import TabbiKit

/// The Party tab's Crew section: the main card on the left (my crew, a crew
/// page, Find, the New crew form, or an invite to confirm) and the weekly
/// top 3 on the right, where the friends column is on the Party side, so
/// switching keeps the panel's shape. The form swaps the top 3 for a live
/// preview with Create.
struct CrewsPanel: View {
    @ObservedObject var crews: CrewsStore
    var focus: FocusState<PartyField?>.Binding

    private var state: CrewsState { crews.state }
    private var isForm: Bool { state.viewing == nil && state.invite == nil && (state.section == .create || state.editing) }

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Card {
                main
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Group {
                if isForm {
                    CrewPreviewCard(crews: crews)
                } else {
                    CrewBoardCard(crews: crews)
                }
            }
            .frame(width: PartyPanel.friendsWidth)
        }
        .motion(Theme.Motion.content, value: mainID)
        .motion(Theme.Motion.content, value: isForm)
    }

    /// Which main view shows, for its transition.
    private var mainID: String {
        if state.invite != nil { return "invite" }
        if let viewing = state.viewing { return "crew-" + viewing.id }
        if state.editing { return "edit" }
        return state.section.rawValue + (state.inCrew ? "-in" : "-out")
    }

    @ViewBuilder
    private var main: some View {
        if let invite = state.invite {
            CrewInviteView(crews: crews, code: invite)
                .transition(.opacity)
        } else if let viewing = state.viewing {
            CrewPageView(crews: crews, crew: viewing)
                .transition(.opacity)
        } else if isForm {
            CrewFormView(crews: crews, focus: focus)
                .transition(.opacity)
        } else if state.section == .find {
            CrewFindView(crews: crews, focus: focus)
                .transition(.opacity)
        } else if let mine = state.mine {
            CrewPageView(crews: crews, crew: mine)
                .transition(.opacity)
        } else if state.mineLoaded {
            CrewEmptyView(crews: crews, focus: focus)
                .transition(.opacity)
        } else {
            CrewLoadingView(crews: crews)
                .transition(.opacity)
        }
    }
}

/// The header row every main view starts with: the Party or Crew switch,
/// then the view's own title and actions.
struct CrewHeader<Trailing: View>: View {
    @ObservedObject var crews: CrewsStore
    var back: (() -> Void)?
    /// Forces the switch's titles on or off; nil picks whichever fits.
    var switchTitles: Bool?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            PartySectionSwitch(crews: crews, showsTitles: switchTitles)
            if let back {
                CrewIconButton(symbol: "chevron.backward", help: String(localized: "Back", bundle: .tabbi), action: back)
            }
            Spacer(minLength: Theme.Spacing.xs)
            trailing
        }
        .frame(height: 24)
    }
}

// MARK: - A crew page

/// My crew, or another crew opened from the top 3 or Find: its icon with
/// this week's laurel, name, trophies, hours and rank, and the members' pets.
struct CrewPageView: View {
    @ObservedObject var crews: CrewsStore
    let crew: CrewDetail

    private var isVisitor: Bool { !crew.mine }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            // The switch keeps its words longest; Invite shortens to its icon first.
            ViewThatFits(in: .horizontal) {
                header(switchTitles: true, inviteTitle: true)
                header(switchTitles: true, inviteTitle: false)
                header(switchTitles: false, inviteTitle: false)
            }
            identity
            members
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func header(switchTitles: Bool, inviteTitle: Bool) -> some View {
        CrewHeader(crews: crews, back: isVisitor ? { crews.closeCrewPage() } : nil, switchTitles: switchTitles) {
            actions(inviteTitle: inviteTitle)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func actions(inviteTitle: Bool) -> some View {
        if isVisitor {
            if crew.summary.visibility == .public && !crews.state.inCrew && !crew.summary.isFull {
                PartyPillButton(title: String(localized: "Join", bundle: .tabbi), isProminent: true,
                                isBusy: crews.pending == .join, height: 20,
                                help: String(localized: "Join \(crew.summary.name). Your focus minutes count for it from now on.", bundle: .tabbi)) {
                    crews.join(crew: crew.id)
                }
            }
            CrewIconButton(symbol: "flag", help: String(localized: "Report this crew", bundle: .tabbi)) {
                crews.beginReport(CrewReportTarget(crew: crew.summary, member: nil))
            }
        } else {
            if let code = crew.inviteCode, let invite = CrewInvite(code: code) {
                CrewInviteButton(invite: invite, showsTitle: inviteTitle)
            }
            CrewIconButton(symbol: "magnifyingglass", help: String(localized: "Find crews", bundle: .tabbi)) {
                crews.show(.find)
            }
            CrewMoreMenu {
                if crew.owner {
                    Button(String(localized: "Edit Crew…", bundle: .tabbi)) { crews.beginEdit() }
                }
                if let me = crew.me {
                    if me.pet == nil {
                        Button(String(localized: "Show My Pet on Crew Pages", bundle: .tabbi)) { crews.setShowsPet(true) }
                    } else {
                        Button(String(localized: "Hide My Pet on Crew Pages", bundle: .tabbi)) { crews.setShowsPet(false) }
                    }
                }
                Divider()
                Button(String(localized: "Leave Crew", bundle: .tabbi), role: .destructive) { crews.leave() }
            }
        }
    }

    private var identity: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            CrewCrestView(crew: crew.summary)
            VStack(alignment: .leading, spacing: 1) {
                Text(crew.summary.name)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(crew.summary.description.isEmpty ? crew.summary.name : crew.summary.description)
                HStack(spacing: Theme.Spacing.xs) {
                    Text(CrewFormat.hours(minutes: crew.summary.weekMinutes))
                        .font(Theme.Typography.bodyEmphasis.monospacedDigit())
                        .foregroundStyle(Theme.Palette.primaryText)
                    Text(rankText)
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                .lineLimit(1)
                .fixedSize()
                .help(String(localized: "Focus hours this week. The board freezes Sunday 23:59 UTC.", bundle: .tabbi))
                ViewThatFits(in: .horizontal) {
                    meta(words: true)
                    meta(words: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var rankText: String {
        guard let rank = crew.rank else { return String(localized: "this week", bundle: .tabbi) }
        return String(localized: "\(CrewFormat.rank(rank)) this week", bundle: .tabbi)
    }

    /// Visibility, members and trophies; `words` spells them out, otherwise
    /// icons and numbers carry them (the tooltips say the rest).
    private func meta(words: Bool) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Label {
                if words {
                    Text(crew.summary.visibility == .public ? String(localized: "Public", bundle: .tabbi)
                         : String(localized: "Private", bundle: .tabbi))
                }
            } icon: {
                Image(systemName: crew.summary.visibility == .public ? "globe" : "lock.fill")
            }
            .help(crew.summary.visibility == .public ? String(localized: "Public: anyone can find and join it.", bundle: .tabbi)
                  : String(localized: "Private: only people with the invite can join.", bundle: .tabbi))
            Label {
                Text(words ? CrewFormat.members(crew.summary.memberCount, of: crew.summary.maxMembers)
                     : "\(crew.summary.memberCount)/\(crew.summary.maxMembers)")
                    .monospacedDigit()
            } icon: {
                Image(systemName: "person.2.fill")
            }
            .help(String(localized: "Members", bundle: .tabbi))
            if crew.summary.trophies > 0 {
                Label {
                    Text(crew.summary.trophies.formatted()).monospacedDigit()
                } icon: {
                    Image(systemName: "trophy.fill").foregroundStyle(CrewRankBadge.color(1))
                }
                .help(String(localized: "Top 3 finishes: \(crew.medals.gold) gold, \(crew.medals.silver) silver, \(crew.medals.bronze) bronze", bundle: .tabbi))
            }
            if crew.hidden {
                Label {
                    if words { Text("Hidden", bundle: .tabbi) }
                } icon: {
                    Image(systemName: "eye.slash.fill")
                }
                .help(String(localized: "The Tabbi team hid this crew from the board and Find.", bundle: .tabbi))
            }
        }
        .labelStyle(CrewCompactLabelStyle())
        .font(Theme.Typography.caption)
        .foregroundStyle(Theme.Palette.secondaryText)
        .lineLimit(1)
        .fixedSize()
    }

    private var members: some View {
        CrewMembersStrip(crews: crews, crew: crew)
    }
}

/// The "..." menu of my crew's page. A snapshot draws the button alone,
/// since `ImageRenderer` cannot draw an AppKit menu button.
struct CrewMoreMenu<Items: View>: View {
    @ViewBuilder var items: Items

    var body: some View {
        if PartyStyle.isSnapshot {
            label
        } else {
            Menu { items } label: { label }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(String(localized: "More crew options", bundle: .tabbi))
        }
    }

    private var label: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(PartyStyle.accent)
            .frame(width: 20, height: 20)
            .background(Circle().fill(Theme.Palette.surface))
    }
}

/// An icon and its title close together, for dense meta lines.
struct CrewCompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 8.5, weight: .bold))
            configuration.title
        }
    }
}

/// The members' pets side by side, owner first, with name and hours. It
/// scrolls sideways once they no longer fit.
struct CrewMembersStrip: View {
    @ObservedObject var crews: CrewsStore
    let crew: CrewDetail

    static let columnWidth: CGFloat = 60

    var body: some View {
        Group {
            if PartyStyle.isSnapshot {
                Color.clear
                    .frame(height: Self.height)
                    .overlay(alignment: .leading) { row }
                    .clipped()
            } else {
                ScrollView(.horizontal) { row }
                    .scrollIndicators(.never)
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: Self.height)
            }
        }
        .crewTrailingFade()
    }

    static let height: CGFloat = 66

    private var row: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.xs) {
            ForEach(crew.members) { member in
                CrewMemberColumn(crews: crews, crew: crew, member: member)
            }
        }
    }
}

private struct CrewMemberColumn: View {
    @ObservedObject var crews: CrewsStore
    let crew: CrewDetail
    let member: CrewMember
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 1) {
            CrewMemberPet(member: member)
            HStack(spacing: 2) {
                if member.owner {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(CrewRankBadge.color(1))
                        .help(String(localized: "Crew owner", bundle: .tabbi))
                }
                Text(member.me ? String(localized: "You", bundle: .tabbi) : member.name)
                    .font(Theme.Typography.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .help(member.name)
            HStack(spacing: 2) {
                Text(CrewFormat.hours(minutes: member.weekMinutes))
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .fixedSize()
                if let level = member.studyLevel {
                    Text(String(localized: "Lv \(level)", bundle: .tabbi))
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(Theme.Palette.tertiaryText)
                        .fixedSize()
                        .help(String(localized: "Study Level \(level)", bundle: .tabbi))
                }
            }
        }
        .frame(width: CrewMembersStrip.columnWidth)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
            .fill(hovering ? Theme.Palette.surfaceHover : .clear))
        .onHover { hovering = $0 }
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var menu: some View {
        if member.me {
            if member.pet == nil {
                Button(String(localized: "Show My Pet on Crew Pages", bundle: .tabbi)) { crews.setShowsPet(true) }
            } else {
                Button(String(localized: "Hide My Pet on Crew Pages", bundle: .tabbi)) { crews.setShowsPet(false) }
            }
        } else {
            if crew.owner && crew.mine {
                Button(String(localized: "Remove \(member.name) from Crew", bundle: .tabbi)) { crews.remove(member) }
                Divider()
            }
            Button(String(localized: "Report \(member.name)…", bundle: .tabbi)) {
                crews.beginReport(CrewReportTarget(crew: crew.summary, member: member))
            }
            Button(String(localized: "Block \(member.name)", bundle: .tabbi), role: .destructive) { crews.block(member, in: crew) }
        }
    }
}

// MARK: - No crew yet

struct CrewEmptyView: View {
    @ObservedObject var crews: CrewsStore
    var focus: FocusState<PartyField?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            CrewHeader(crews: crews) { EmptyView() }
            // The intro gives way first on a short panel: the icon, then the
            // line under the title, so the ways in always show whole.
            ViewThatFits(in: .vertical) {
                intro(showsIcon: true, showsLine: true)
                intro(showsIcon: false, showsLine: true)
                intro(showsIcon: false, showsLine: false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            ViewThatFits(in: .horizontal) {
                buttons(titles: true)
                buttons(titles: false)
            }
            PartyCodeField(placeholder: String(localized: "Invite code", bundle: .tabbi), symbol: "link",
                           length: CrewCode.inviteLength, field: .crewInvite, focus: focus,
                           help: String(localized: "Have an invite? Type the \(CrewCode.inviteLength)-character code and press Return to join", bundle: .tabbi)) {
                crews.join(invite: $0)
            }
        }
    }

    private func intro(showsIcon: Bool, showsLine: Bool) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            if showsIcon {
                CrewCrestView(crest: .default, laurel: .gold)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("Join a study crew", bundle: .tabbi)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if showsLine {
                    Text("Study with a crew and climb the weekly top 3.", bundle: .tabbi)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func buttons(titles: Bool) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            PartyPillButton(title: titles ? String(localized: "New crew", bundle: .tabbi) : nil, symbol: "plus",
                            isProminent: true, help: String(localized: "Make a crew and invite friends", bundle: .tabbi)) {
                crews.show(.create)
            }
            PartyPillButton(title: titles ? String(localized: "Find crews", bundle: .tabbi) : nil, symbol: "magnifyingglass",
                            help: String(localized: "Browse public crews to join", bundle: .tabbi)) {
                crews.show(.find)
            }
        }
    }
}

/// Before the first answer about my crew.
struct CrewLoadingView: View {
    @ObservedObject var crews: CrewsStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            CrewHeader(crews: crews) { EmptyView() }
            Spacer(minLength: 0)
            HStack(spacing: Theme.Spacing.s) {
                ProgressView().controlSize(.small)
                Text(crews.state.loadError.map(CrewErrorText.message) ?? String(localized: "Loading your crew…", bundle: .tabbi))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - An invite link

struct CrewInviteView: View {
    @ObservedObject var crews: CrewsStore
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            CrewHeader(crews: crews) { EmptyView() }
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("Join this crew?", bundle: .tabbi)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                Text(crews.state.inCrew
                     ? String(localized: "You're already in a crew. Leave it first to join another.", bundle: .tabbi)
                     : String(localized: "Someone invited you to a study crew. Your focus minutes count for it from now on.", bundle: .tabbi))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack(spacing: Theme.Spacing.s) {
                if !crews.state.inCrew {
                    PartyPillButton(title: String(localized: "Join Crew", bundle: .tabbi), symbol: "checkmark", isProminent: true,
                                    isBusy: crews.pending == .join,
                                    help: String(localized: "Join with invite code \(code)", bundle: .tabbi)) {
                        crews.join(invite: code)
                    }
                }
                PartyTextButton(title: String(localized: "Not Now", bundle: .tabbi),
                                help: String(localized: "Close without joining", bundle: .tabbi)) {
                    crews.dismissInvite()
                }
            }
        }
    }
}

// MARK: - Find

struct CrewFindView: View {
    @ObservedObject var crews: CrewsStore
    var focus: FocusState<PartyField?>.Binding

    private var query: Binding<String> {
        Binding(get: { crews.state.query }, set: { crews.search($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            CrewHeader(crews: crews, back: { crews.show(.mine) }) {
                Text("Find crews", bundle: .tabbi)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .fixedSize()
            }
            CrewTextField(placeholder: String(localized: "Search public crews", bundle: .tabbi), text: query,
                          field: .crewSearch, focus: focus, limit: CrewCatalog.nameMaxLength, symbol: "magnifyingglass",
                          help: String(localized: "Search public crews by name", bundle: .tabbi))
            list
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var list: some View {
        if let results = crews.state.results {
            if results.isEmpty {
                Text(crews.state.query.isEmpty ? String(localized: "No public crews yet. Make the first one.", bundle: .tabbi)
                     : String(localized: "No public crews match.", bundle: .tabbi))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if PartyStyle.isSnapshot {
                Color.clear
                    .overlay(alignment: .top) { rows(results) }
                    .clipped()
                    .edgeFade(.bottom, length: Theme.Spacing.m)
            } else {
                ScrollView(.vertical) { rows(results) }
                    .scrollIndicators(.automatic)
                    .scrollBounceBehavior(.basedOnSize)
                    .contentMargins(.bottom, Theme.Spacing.m, for: .scrollContent)
                    .edgeFade(.bottom, length: Theme.Spacing.m)
            }
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func rows(_ results: [CrewSummary]) -> some View {
        VStack(spacing: 0) {
            ForEach(results) { crew in
                CrewFindRow(crews: crews, crew: crew)
            }
        }
    }
}

private struct CrewFindRow: View {
    @ObservedObject var crews: CrewsStore
    let crew: CrewSummary
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            CrewCrestView(crew: crew, pixelSize: CrewCrestArt.compactPixelSize)
            VStack(alignment: .leading, spacing: 0) {
                Text(crew.name)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(1)
                    .help(crew.description.isEmpty ? crew.name : crew.description)
                Text(String(localized: "\(CrewFormat.members(crew.memberCount, of: crew.maxMembers)) · \(CrewFormat.hours(minutes: crew.weekMinutes)) this week", bundle: .tabbi))
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: Theme.Spacing.xs)
            if crew.isFull {
                Text("Full", bundle: .tabbi)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .fixedSize()
            } else if !crews.state.inCrew {
                PartyPillButton(title: String(localized: "Join", bundle: .tabbi), isBusy: crews.pending == .join, height: 20,
                                help: String(localized: "Join \(crew.name). Your focus minutes count for it from now on.", bundle: .tabbi)) {
                    crews.join(crew: crew.id)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.vertical, Theme.Spacing.xxs)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
            .fill(hovering ? Theme.Palette.surfaceHover : .clear))
        .contentShape(Rectangle())
        .onTapGesture { crews.open(crew: crew.id) }
        .onHover { hovering = $0 }
        .help(String(localized: "Open \(crew.name)", bundle: .tabbi))
    }
}
