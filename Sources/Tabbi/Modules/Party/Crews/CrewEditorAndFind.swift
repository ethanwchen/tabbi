import SwiftUI
import TabbiKitCore
import TabbiKit

// MARK: - The crest editor

/// New crew and Edit crew: a live crest preview with the name under it as it
/// will wrap on a tile, Shuffle and the Public or Private toggle, the name and
/// description, and the frame, emblem and color pickers.
struct CrewEditorScreen: View {
    @ObservedObject var crews: CrewsStore
    let editing: Bool
    let from: CrewsState.Section
    var focus: FocusState<PartyField?>.Binding
    @Environment(\.crewIsCompact) private var isCompact

    private var draft: CrewDraftForm { crews.draft }

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            CrewBackPill(crews: crews, from: from)
            Text(editing ? String(localized: "Edit crew", bundle: .tabbi) : String(localized: "New crew", bundle: .tabbi))
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.primaryText)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.xs)
            CrewButton(title: editing ? String(localized: "Save", bundle: .tabbi) : String(localized: "Create", bundle: .tabbi),
                       style: .prominent, isEnabled: draft.problem == nil, isBusy: crews.pending == .save,
                       help: draft.problem?.message ?? (editing ? String(localized: "Save your changes", bundle: .tabbi)
                           : String(localized: "Create the crew with you as its owner", bundle: .tabbi))) {
                crews.saveDraft()
            }
        }
        .frame(height: CrewLayout.headHeight)
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            side.frame(width: isCompact ? 150 : CrewLayout.editorSideWidth)
            pickers
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Shuffle and the Public or Private toggle; glyphs only when a
    /// language's words do not fit beside the preview.
    private func crestButtons(iconOnly: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CrewButton(title: String(localized: "crew.shuffle", defaultValue: "Shuffle", bundle: .tabbi), symbol: "shuffle",
                       iconOnly: iconOnly, help: String(localized: "A random frame, emblem and color", bundle: .tabbi)) {
                withMotion(Theme.Motion.snappy) { crews.shuffleCrest() }
            }
            CrewButton(title: draft.visibility == .public ? String(localized: "Public", bundle: .tabbi)
                       : String(localized: "Private", bundle: .tabbi),
                       symbol: draft.visibility == .public ? "globe" : "lock.fill", iconOnly: iconOnly,
                       help: draft.visibility == .public
                           ? String(localized: "Anyone can find it and ask to join. Click to make it private.", bundle: .tabbi)
                           : String(localized: "Only people with the invite link can join. Click to make it public.", bundle: .tabbi)) {
                crews.draft.visibility = draft.visibility == .public ? .private : .public
            }
            .accessibilityAddTraits(.isToggle)
        }
    }

    /// The preview tile, Shuffle, Public and the fields; the name under the
    /// crest goes when a two-line name would push the fields out of the panel.
    private var side: some View {
        ViewThatFits(in: .vertical) {
            side(showsName: !isCompact)
            side(showsName: false)
        }
    }

    private func side(showsName: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                VStack(spacing: 2) {
                    CrewCrestView(crest: draft.crest, pixelSize: CrewCrestArt.regularPixelSize)
                    if showsName {
                        Text(draft.cleanName.isEmpty ? String(localized: "Crew name", bundle: .tabbi) : CrewHyphenation.hyphenated(draft.cleanName))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(draft.cleanName.isEmpty ? Theme.Palette.tertiaryText : Theme.Palette.primaryText)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: 64)
                    }
                }
                .frame(width: 64)
                ViewThatFits(in: .horizontal) {
                    crestButtons(iconOnly: false)
                    crestButtons(iconOnly: true)
                }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous).fill(Theme.Palette.surface))
            CrewTextField(placeholder: String(localized: "Crew name", bundle: .tabbi), text: $crews.draft.name, field: .crewName,
                          focus: focus, limit: CrewCatalog.nameMaxLength,
                          help: String(localized: "Up to \(CrewCatalog.nameMaxLength) characters. Everyone in Party can see it on the board.", bundle: .tabbi))
                .padding(.top, 2)
            CrewTextField(placeholder: String(localized: "What you study", bundle: .tabbi), text: $crews.draft.description,
                          field: .crewDescription, focus: focus, limit: CrewCatalog.descriptionMaxLength,
                          help: String(localized: "One line about your crew, up to \(CrewCatalog.descriptionMaxLength) characters", bundle: .tabbi))
        }
    }

    /// The editor's one line: the name filter's answer, or the reminder that
    /// every crew can be featured with its members' pets.
    private var noteText: String {
        if let problem = draft.problem, problem != .nameEmpty { return problem.message }
        return String(localized: "Every crew can appear on the weekly top 3 with its members' pets.", bundle: .tabbi)
    }

    private var labelWidth: CGFloat { isCompact ? 40 : 46 }

    private var pickers: some View {
        VStack(alignment: .leading, spacing: 6) {
            picker(String(localized: "Frame", bundle: .tabbi)) {
                HStack(spacing: isCompact ? 2 : 4) {
                    ForEach(CrewCatalog.frames, id: \.self) { frame in
                        CrewOption(isSelected: draft.crest.frame == frame, side: 32, help: CrewCatalog.frameTitle(frame)) {
                            crews.draft.crest.frame = frame
                        } content: {
                            CrewCrestView(crest: CrewCrest(frame: frame, emblem: draft.crest.emblem, color: draft.crest.color))
                        }
                    }
                }
            }
            picker(String(localized: "Emblem", bundle: .tabbi)) {
                // One row that scrolls by whole tiles, so the line under the
                // pickers always has room.
                CrewChoiceRow(count: CrewCatalog.emblems.count, side: 24, spacing: 4) { index in
                    let emblem = CrewCatalog.emblems[index]
                    CrewOption(isSelected: draft.crest.emblem == emblem, side: 24, help: CrewCatalog.emblemTitle(emblem)) {
                        crews.draft.crest.emblem = emblem
                    } content: {
                        CrewEmblemView(emblem: emblem, color: draft.crest.color)
                    }
                }
            }
            picker(String(localized: "Color", bundle: .tabbi)) {
                HStack(spacing: isCompact ? 1 : 2) {
                    ForEach(CrewCatalog.colors) { color in
                        CrewOption(isSelected: draft.crest.color == color.id, side: 20, isRound: true, help: color.title) {
                            crews.draft.crest.color = color.id
                        } content: {
                            Circle().fill(Color(hex: color.hex)).frame(width: 14, height: 14)
                                .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
                        }
                    }
                }
            }
            // The owner's promise in the create flow: any crew can be featured.
            Text(noteText)
                .font(Theme.Typography.caption)
                .foregroundStyle(draft.problem == nil || draft.problem == .nameEmpty ? Theme.Palette.tertiaryText : Theme.Palette.warning)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    private func picker<Options: View>(_ title: String, @ViewBuilder options: () -> Options) -> some View {
        HStack(alignment: .center, spacing: 4) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .frame(width: labelWidth, alignment: .leading)
            options()
        }
    }
}

/// A row of picker options that scrolls sideways by whole options and shows
/// only whole options, with the rest a scroll away.
private struct CrewChoiceRow<Option: View>: View {
    let count: Int
    let side: CGFloat
    let spacing: CGFloat
    @ViewBuilder var option: (Int) -> Option

    var body: some View {
        GeometryReader { proxy in
            let visible = max(1, Int((proxy.size.width + spacing) / (side + spacing)))
            let width = CGFloat(min(visible, count)) * (side + spacing) - spacing
            HStack(spacing: 0) {
                if PartyStyle.isSnapshot || count <= visible {
                    HStack(spacing: spacing) { ForEach(0..<min(count, visible), id: \.self) { option($0) } }
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: spacing) { ForEach(0..<count, id: \.self) { option($0) } }.scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .scrollIndicators(.never)
                    .frame(width: width)
                }
                if count > visible {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.Palette.tertiaryText)
                        .frame(width: 10)
                        .help(String(localized: "\(count - visible) more", bundle: .tabbi))
                }
            }
        }
        .frame(height: side)
    }
}

/// One option in the editor's pickers: accent tint and ring when chosen.
private struct CrewOption<Content: View>: View {
    let isSelected: Bool
    let side: CGFloat
    var isRound = false
    let help: String
    let action: () -> Void
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content
                .frame(width: side, height: side)
                .background(shape.fill(isSelected ? PartyStyle.accent.opacity(0.16) : hovering ? Theme.Palette.surfaceHover : .clear))
                .overlay(shape.strokeBorder(isSelected ? PartyStyle.accent : .clear, lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .onHover { hovering = $0 }
    }

    private var shape: AnyInsettableShape {
        isRound ? AnyInsettableShape(Circle()) : AnyInsettableShape(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous))
    }
}

/// A type-erased shape that can be stroked inside its frame.
private struct AnyInsettableShape: InsettableShape {
    private let path: @Sendable (CGRect) -> Path
    private let inset: CGFloat

    init<S: InsettableShape>(_ shape: S) {
        self.init(shape, inset: 0)
    }

    private init<S: InsettableShape>(_ shape: S, inset: CGFloat) {
        let inner = shape.inset(by: inset)
        path = { rect in inner.path(in: rect) }
        self.inset = inset
    }

    private init(path: @escaping @Sendable (CGRect) -> Path, inset: CGFloat) {
        self.path = path
        self.inset = inset
    }

    func path(in rect: CGRect) -> Path { path(rect.insetBy(dx: inset, dy: inset)) }

    func inset(by amount: CGFloat) -> AnyInsettableShape {
        AnyInsettableShape(path: path, inset: inset + amount)
    }
}

/// An emblem alone, in the crew color's outline.
/// An emblem option: as large as fits the 24 pt tile in half-point steps
/// (1.5 pt per sprite pixel for a 15 px emblem, whole device pixels on
/// Retina, as the hero crest), so a small emblem does not float in air.
struct CrewEmblemView: View {
    let emblem: String
    let color: String

    var body: some View {
        let shown = CrewCrestArt.art.emblem(emblem)
        CrewPixelImage(size: CGSize(width: shown.width, height: shown.height),
                       pixelSize: max(1, (48 / CGFloat(max(shown.width, shown.height))).rounded(.down) / 2)) {
            CrewCrestArt.emblemImage(emblem, color: color, scale: $0)
        }
    }
}

extension Color {
    /// A `#RRGGBB` color.
    init(hex: String) {
        let color = PetColor(hex: hex) ?? PetColor(red: 0, green: 0, blue: 0)
        self.init(red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255)
    }
}

// MARK: - Find

struct CrewFindScreen: View {
    @ObservedObject var crews: CrewsStore
    var focus: FocusState<PartyField?>.Binding

    private var query: Binding<String> {
        Binding(get: { crews.state.query }, set: { crews.search($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CrewTextField(placeholder: String(localized: "Search public crews", bundle: .tabbi), text: query, field: .crewSearch,
                          focus: focus, limit: CrewCatalog.nameMaxLength, symbol: "magnifyingglass",
                          help: String(localized: "Search public crews by name", bundle: .tabbi))
            if let results = crews.state.results {
                if results.isEmpty {
                    CrewStatus(symbol: "magnifyingglass", title: String(localized: "No crews match", bundle: .tabbi),
                               detail: String(localized: "Try another word, or create one.", bundle: .tabbi)) {
                        if !crews.state.inCrew {
                            CrewButton(title: String(localized: "Create a crew", bundle: .tabbi), height: 24,
                                       help: String(localized: "Make a crew and invite friends", bundle: .tabbi)) {
                                crews.openEditor(editing: false)
                            }
                        }
                    }
                } else {
                    CrewRowList(count: results.count, row: { index in
                        CrewFindRow(crews: crews, crew: results[index])
                    })
                }
            } else {
                CrewBoardSkeleton()
            }
        }
    }
}

private struct CrewFindRow: View {
    @ObservedObject var crews: CrewsStore
    let crew: CrewSummary

    private var isMine: Bool { crews.state.mine?.id == crew.id }

    var body: some View {
        HStack(spacing: 6) {
            CrewCrestView(crew: crew)
            CrewRowName(name: crew.name,
                        caption: String(localized: "\(CrewFormat.members(crew.memberCount, of: crew.maxMembers)) · \(CrewFormat.hours(minutes: crew.weekMinutes)) this week", bundle: .tabbi))
            trailing
        }
        .crewRow(isMine: isMine) { crews.open(crew: crew.id) }
        .help(crew.description.isEmpty ? crew.name : crew.description)
    }

    @ViewBuilder
    private var trailing: some View {
        if isMine {
            CrewTag(title: String(localized: "Your crew", bundle: .tabbi), accent: true)
        } else if crews.state.hasRequested(crew.id) {
            CrewTag(title: String(localized: "Requested", bundle: .tabbi), symbol: "checkmark")
        } else if crew.isFull {
            CrewTag(title: String(localized: "Full", bundle: .tabbi))
        } else if !crews.state.inCrew {
            CrewButton(title: String(localized: "Join", bundle: .tabbi), isBusy: crews.pending == .join,
                       help: String(localized: "Ask to join \(crew.name). Its owner lets you in.", bundle: .tabbi)) {
                crews.requestToJoin(crew)
            }
        }
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
                        CrewPetView(pet: member.pet, name: member.name)
                    } else {
                        CrewCrestView(crew: target.crew)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Report \(name)", bundle: .tabbi)
                            .font(Theme.Typography.bodyEmphasis)
                            .foregroundStyle(Theme.Palette.primaryText)
                        Text("The Tabbi team reviews it. \(name) isn't told.", bundle: .tabbi)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                // The reasons wrap to a second row before any is cut.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.xs) { reasonChips(CrewReportReason.allCases) }
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        HStack(spacing: Theme.Spacing.xs) { reasonChips(Array(CrewReportReason.allCases.prefix(3))) }
                        HStack(spacing: Theme.Spacing.xs) { reasonChips(Array(CrewReportReason.allCases.dropFirst(3))) }
                    }
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
                                    help: String(localized: "Close without reporting (Esc)", bundle: .tabbi)) { crews.cancelReport() }
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

    private func reasonChips(_ reasons: [CrewReportReason]) -> some View {
        ForEach(reasons, id: \.self) { option in
            PartyChoiceChip(title: option.title, isSelected: reason == option,
                            help: String(localized: "Report \(name): \(option.title)", bundle: .tabbi)) { reason = option }
        }
    }
}
