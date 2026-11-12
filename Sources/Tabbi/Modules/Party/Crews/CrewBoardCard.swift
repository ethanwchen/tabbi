import SwiftUI
import TabbiKitCore
import TabbiKit

/// The weekly top 3 beside every Crew view: this week's live race with the
/// countdown to the freeze, or last week's winners with the laurels they
/// won. A crew opens its page on click.
struct CrewBoardCard: View {
    @ObservedObject var crews: CrewsStore

    private var state: CrewsState { crews.state }

    var body: some View {
        Card(padding: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                header
                    .padding(.horizontal, Theme.Spacing.xs)
                rows
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                footer
            }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            headerRow(showsTitle: true)
            headerRow(showsTitle: false)
        }
        .frame(height: 20)
    }

    private func headerRow(showsTitle: Bool) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            if showsTitle || state.showsLastWeek {
                Text(state.showsLastWeek ? String(localized: "Last week", bundle: .tabbi) : String(localized: "Top 3", bundle: .tabbi))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .fixedSize()
                Spacer(minLength: Theme.Spacing.xs)
            }
            if !state.showsLastWeek {
                Label {
                    Text(CrewFormat.countdown(state.week, now: crews.now))
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "clock")
                }
                .labelStyle(CrewCompactLabelStyle())
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
                .lineLimit(1)
                .fixedSize()
                .help(String(localized: "The week ends Sunday 23:59 UTC. Then the top 3 freeze and win their laurels for next week.", bundle: .tabbi))
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        let entries = state.boardEntries
        if state.board == nil {
            Color.clear
        } else if entries.isEmpty {
            Text(state.showsLastWeek ? String(localized: "Last week's winners show here once a week has ended.", bundle: .tabbi)
                 : String(localized: "No crew has studied yet this week. Yours could be first.", bundle: .tabbi))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 2) {
                ForEach(entries) { entry in
                    CrewBoardRow(crews: crews, entry: entry, isMine: entry.crew.id == state.mine?.id,
                                 isOpen: entry.crew.id == state.viewing?.id)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 2) {
            CrewBoardTab(title: String(localized: "This week", bundle: .tabbi), isSelected: !state.showsLastWeek,
                         help: String(localized: "This week's live top 3", bundle: .tabbi)) {
                crews.showLastWeek(false)
            }
            CrewBoardTab(title: String(localized: "Last week", bundle: .tabbi), isSelected: state.showsLastWeek,
                         isEnabled: state.board?.featured != nil,
                         help: state.board?.featured != nil ? String(localized: "Last week's winners and their laurels", bundle: .tabbi)
                            : String(localized: "Last week's winners show here once a week has ended.", bundle: .tabbi)) {
                crews.showLastWeek(true)
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.Palette.surface))
        .frame(maxWidth: .infinity)
    }
}

private struct CrewBoardTab: View {
    let title: String
    let isSelected: Bool
    var isEnabled = true
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(isSelected ? Theme.Palette.primaryText
                                 : hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .frame(height: 18)
                .background(Capsule().fill(isSelected ? Theme.Palette.surfaceHover : .clear))
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

private struct CrewBoardRow: View {
    @ObservedObject var crews: CrewsStore
    let entry: CrewBoardEntry
    let isMine: Bool
    let isOpen: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            CrewRankBadge(rank: entry.rank)
            CrewCrestView(crew: entry.crew, pixelSize: CrewCrestArt.compactPixelSize)
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.crew.name)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(1)
                Text(isMine ? String(localized: "\(CrewFormat.hours(minutes: entry.minutes)) · Your crew", bundle: .tabbi)
                     : CrewFormat.hours(minutes: entry.minutes))
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(isMine ? PartyStyle.accent : Theme.Palette.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.vertical, 1)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
            .fill(isOpen || hovering ? Theme.Palette.surfaceHover : .clear))
        .contentShape(Rectangle())
        .onTapGesture { crews.open(crew: entry.crew.id) }
        .onHover { hovering = $0 }
        .help(String(localized: "See \(entry.crew.name) and its members' pets", bundle: .tabbi))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - New crew and Edit

/// The form's fields: name, description, the icon row and the color dots.
struct CrewFormView: View {
    @ObservedObject var crews: CrewsStore
    var focus: FocusState<PartyField?>.Binding

    private var isEditing: Bool { crews.state.editing }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            CrewHeader(crews: crews) {
                Text(isEditing ? String(localized: "Edit crew", bundle: .tabbi) : String(localized: "New crew", bundle: .tabbi))
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .fixedSize()
            }
            CrewTextField(placeholder: String(localized: "Crew name", bundle: .tabbi), text: $crews.draft.name,
                          field: .crewName, focus: focus, limit: CrewCatalog.nameMaxLength,
                          help: String(localized: "Up to \(CrewCatalog.nameMaxLength) characters. Everyone in Party can see it on the board.", bundle: .tabbi))
            CrewTextField(placeholder: String(localized: "A short description (optional)", bundle: .tabbi), text: $crews.draft.description,
                          field: .crewDescription, focus: focus, limit: CrewCatalog.descriptionMaxLength,
                          help: String(localized: "One line about your crew, up to \(CrewCatalog.descriptionMaxLength) characters", bundle: .tabbi))
            crestRows
        }
    }

    /// The crest builder: frames, emblems and colors, and Shuffle. Its
    /// final layout follows the Crews UI spec (docs/design/crews.md).
    private var crestRows: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                choiceRow(CrewCatalog.frames) { frame in
                    CrewCrestChoice(crest: CrewCrest(frame: frame, emblem: crews.draft.crest.emblem, color: crews.draft.crest.color),
                                    title: CrewCatalog.frameTitle(frame), isSelected: crews.draft.crest.frame == frame) {
                        crews.draft.crest.frame = frame
                    }
                }
                CrewIconButton(symbol: "shuffle", help: String(localized: "Shuffle the crest", bundle: .tabbi)) {
                    var generator = SystemRandomNumberGenerator()
                    crews.draft.shuffle(using: &generator)
                }
            }
            choiceRow(CrewCatalog.emblems) { emblem in
                CrewCrestChoice(crest: CrewCrest(frame: crews.draft.crest.frame, emblem: emblem, color: crews.draft.crest.color),
                                title: CrewCatalog.emblemTitle(emblem), isSelected: crews.draft.crest.emblem == emblem) {
                    crews.draft.crest.emblem = emblem
                }
            }
            HStack(spacing: Theme.Spacing.s) {
                ForEach(CrewCatalog.colors) { color in
                    CrewColorChoice(color: color, isSelected: crews.draft.crest.color == color.id) {
                        crews.draft.crest.color = color.id
                    }
                }
            }
        }
    }

    private static let choiceRowHeight = CrewCrestView.side(CrewCrestArt.compactPixelSize) + 4

    private func choiceRow<Choice: View>(_ ids: [String], @ViewBuilder choice: @escaping (String) -> Choice) -> some View {
        let row = HStack(spacing: Theme.Spacing.xs) { ForEach(ids, id: \.self) { choice($0) } }.padding(2)
        return Group {
            if PartyStyle.isSnapshot {
                Color.clear.frame(height: Self.choiceRowHeight)
                    .overlay(alignment: .leading) { row }
                    .clipped()
            } else {
                ScrollView(.horizontal) { row }
                    .scrollIndicators(.never)
                    .frame(height: Self.choiceRowHeight)
            }
        }
        .crewTrailingFade()
    }
}

private struct CrewCrestChoice: View {
    let crest: CrewCrest
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            CrewCrestView(crest: crest, pixelSize: CrewCrestArt.compactPixelSize)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                    .fill(hovering ? Theme.Palette.surfaceHover : .clear))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                    .strokeBorder(isSelected ? PartyStyle.accent : .clear, lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hovering = $0 }
    }
}

private struct CrewColorChoice: View {
    let color: CrewCatalog.Color
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let fill = Color(red: Double(color.petColor.red) / 255, green: Double(color.petColor.green) / 255,
                         blue: Double(color.petColor.blue) / 255)
        Button(action: action) {
            Circle()
                .fill(fill)
                .frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(Color.white.opacity(isSelected ? 0.95 : 0), lineWidth: 1.5))
                .padding(3)
                .overlay(Circle().strokeBorder(isSelected ? fill : hovering ? Theme.Palette.stroke : .clear, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(color.title)
        .accessibilityLabel(color.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hovering = $0 }
    }
}

/// Beside the form: how the crew will look on the board, Public or
/// Private, the line saying every crew can be featured with its members'
/// pets, and Create (or Save).
struct CrewPreviewCard: View {
    @ObservedObject var crews: CrewsStore

    private var draft: CrewDraftForm { crews.draft }
    private var isEditing: Bool { crews.state.editing }

    var body: some View {
        Card(padding: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.s) {
                    CrewCrestView(crest: draft.crest, pixelSize: CrewCrestArt.compactPixelSize)
                    Text(draft.cleanName.isEmpty ? String(localized: "Your crew", bundle: .tabbi) : draft.cleanName)
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(draft.cleanName.isEmpty ? Theme.Palette.tertiaryText : Theme.Palette.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                visibility
                Text(draft.problem?.message ?? String(localized: "Every crew can appear on the weekly top 3 with its members' pets.", bundle: .tabbi))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(draft.problem == nil || draft.problem == .nameEmpty ? Theme.Palette.secondaryText : Theme.Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack(spacing: Theme.Spacing.s) {
                    PartyTextButton(title: String(localized: "Cancel", bundle: .tabbi), help: String(localized: "Close without saving", bundle: .tabbi)) {
                        crews.cancelEdit()
                    }
                    Spacer(minLength: 0)
                    PartyPillButton(title: isEditing ? String(localized: "Save", bundle: .tabbi) : String(localized: "Create", bundle: .tabbi),
                                    isProminent: true, isBusy: crews.pending == .save || draft.problem != nil, height: 20,
                                    help: draft.problem?.message ?? (isEditing ? String(localized: "Save your changes", bundle: .tabbi)
                                        : String(localized: "Create the crew with you as its owner", bundle: .tabbi))) {
                        crews.saveDraft()
                    }
                }
            }
        }
    }

    private var visibility: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack(spacing: 2) {
                CrewVisibilityChoice(title: String(localized: "Public", bundle: .tabbi), symbol: "globe",
                                     isSelected: draft.visibility == .public) { crews.draft.visibility = .public }
                CrewVisibilityChoice(title: String(localized: "Private", bundle: .tabbi), symbol: "lock.fill",
                                     isSelected: draft.visibility == .private) { crews.draft.visibility = .private }
            }
            .padding(2)
            .background(Capsule().fill(Theme.Palette.surface))
            Text(draft.visibility == .public ? String(localized: "Anyone can find and join it.", bundle: .tabbi)
                 : String(localized: "Only people with the invite can join.", bundle: .tabbi))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CrewVisibilityChoice: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(CrewCompactLabelStyle())
                .font(Theme.Typography.caption)
                .foregroundStyle(isSelected ? Theme.Palette.onAccent : hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .frame(height: 18)
                .background(Capsule().fill(isSelected ? PartyStyle.accent : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hovering = $0 }
    }
}

// MARK: - Reports

/// Reports a crew, or one of its members, to the Tabbi team: a reason, an
/// optional note, and for a member an offer to block them too.
struct CrewReportCard: View {
    let target: CrewReportTarget
    @ObservedObject var crews: CrewsStore
    var focus: FocusState<PartyField?>.Binding
    @State private var reason: CrewReportReason?
    @State private var note = ""
    @State private var alsoBlock = true

    private var isSending: Bool { crews.pending == .report }
    private var name: String { target.member?.name ?? target.crew.name }

    var body: some View {
        Card(padding: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.s) {
                    if let member = target.member {
                        CrewMemberPet(member: member)
                    } else {
                        CrewCrestView(crew: target.crew, pixelSize: CrewCrestArt.compactPixelSize)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Report \(name)", bundle: .tabbi)
                            .font(Theme.Typography.bodyEmphasis)
                            .foregroundStyle(Theme.Palette.primaryText)
                        Text("The Tabbi team reviews it. \(name) isn't told.", bundle: .tabbi)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                    .lineLimit(1)
                }
                ViewThatFits(in: .horizontal) {
                    reasons(spacing: Theme.Spacing.xs)
                    reasons(spacing: 2)
                }
                PartyNoteField(text: $note, focus: focus)
                Spacer(minLength: 0)
                HStack(spacing: Theme.Spacing.s) {
                    if target.member != nil {
                        PartyCheckbox(title: String(localized: "Also block \(name)", bundle: .tabbi), isOn: $alsoBlock,
                                      help: String(localized: "Hide each other everywhere in Party. You can unblock in Party options.", bundle: .tabbi))
                    }
                    Spacer(minLength: Theme.Spacing.s)
                    PartyTextButton(title: String(localized: "Cancel", bundle: .tabbi), isBusy: isSending,
                                    help: String(localized: "Close without reporting (Esc)", bundle: .tabbi)) {
                        crews.cancelReport()
                    }
                    PartyPillButton(title: String(localized: "Send Report", bundle: .tabbi), isProminent: true,
                                    isBusy: isSending || reason == nil, height: 20,
                                    help: reason == nil ? String(localized: "Pick a reason first", bundle: .tabbi)
                                        : String(localized: "Send this report to the Tabbi team", bundle: .tabbi)) {
                        guard let reason else { return }
                        crews.sendReport(reason: reason, note: note, alsoBlock: target.member != nil && alsoBlock)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).fill(Theme.Palette.background))
        .onExitCommand { crews.cancelReport() }
    }

    private func reasons(spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(CrewReportReason.allCases, id: \.self) { option in
                PartyChoiceChip(title: option.title, isSelected: reason == option,
                                help: String(localized: "Report \(name): \(option.title)", bundle: .tabbi)) {
                    reason = option
                }
            }
        }
    }
}
