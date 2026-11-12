import AppKit
import SwiftUI
import TabbiKitCore
import TabbiKit

/// A crew's crest (frame, emblem and color), with the laurel it wears this
/// week and its trophy pips, drawn at whole device pixels like the Goals badges.
struct CrewCrestView: View {
    let crest: CrewCrest
    var laurel: CrewLaurel?
    var pips = 0
    /// Points per sprite pixel before the panel's content scale.
    var pixelSize: CGFloat = CrewCrestArt.regularPixelSize
    @Environment(\.displayScale) private var displayScale
    @Environment(\.panelScale) private var panelScale

    /// The box the crest takes in the layout, so rows line up whatever scale
    /// the display rounds to.
    static func side(_ pixelSize: CGFloat) -> CGFloat { CGFloat(CrewCrestArt.size) * pixelSize }

    var body: some View {
        let scale = max(1, Int((pixelSize * panelScale * displayScale).rounded()))
        let drawn = CGFloat(CrewCrestArt.size) * CGFloat(scale) / displayScale / panelScale
        Group {
            if let image = CrewCrestArt.image(crest, laurel: laurel, pips: pips, scale: scale) {
                Image(decorative: image, scale: displayScale)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: drawn, height: drawn)
            }
        }
        .frame(width: Self.side(pixelSize), height: Self.side(pixelSize))
        .accessibilityHidden(true)
    }
}

extension CrewCrestView {
    init(crew: CrewSummary, pixelSize: CGFloat = CrewCrestArt.regularPixelSize) {
        self.init(crest: crew.crest, laurel: crew.laurel, pips: crew.pips, pixelSize: pixelSize)
    }
}

/// The two-way switch at the Party tab's top left: the party and friends,
/// or the Crew section. It shortens to icons when its column is narrow.
struct PartySectionSwitch: View {
    @ObservedObject var crews: CrewsStore
    /// Forces the titles on or off; nil picks whichever fits.
    var showsTitles: Bool?

    var body: some View {
        if let showsTitles {
            segments(showsTitles: showsTitles)
        } else {
            ViewThatFits(in: .horizontal) {
                segments(showsTitles: true)
                segments(showsTitles: false)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func segments(showsTitles: Bool) -> some View {
        HStack(spacing: 2) {
            PartySectionSegment(title: String(localized: "Party", bundle: .tabbi), symbol: "person.3.fill",
                                showsTitle: showsTitles, isSelected: !crews.showsCrews,
                                help: String(localized: "Your party and friends", bundle: .tabbi)) {
                crews.setShowsCrews(false)
            }
            PartySectionSegment(title: String(localized: "Crew", bundle: .tabbi), symbol: "flag.fill",
                                showsTitle: showsTitles, isSelected: crews.showsCrews,
                                help: String(localized: "Your study crew and the weekly top 3", bundle: .tabbi)) {
                crews.setShowsCrews(true)
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.Palette.surface))
        .fixedSize()
    }
}

private struct PartySectionSegment: View {
    let title: String
    let symbol: String
    let showsTitle: Bool
    let isSelected: Bool
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                if !showsTitle {
                    Image(systemName: symbol).font(.system(size: 9.5, weight: .bold))
                } else {
                    Text(title).font(Theme.Typography.caption.weight(.semibold))
                }
            }
            .foregroundStyle(isSelected ? Theme.Palette.onAccent
                             : hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Theme.Spacing.s)
            .frame(height: 20)
            .background(Capsule().fill(isSelected ? PartyStyle.accent : hovering ? Theme.Palette.surfaceHover : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: isSelected)
    }
}

/// A small round icon button in the Party style, for Back, Find and Report.
struct CrewIconButton: View {
    let symbol: String
    let help: String
    var isBusy = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(hovering ? Theme.Palette.primaryText : PartyStyle.accent)
                .frame(width: 20, height: 20)
                .background(Circle().fill(hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface))
                .contentShape(Circle())
                .opacity(isBusy ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// Copies my crew's invite link and confirms with a check, like a code.
struct CrewInviteButton: View {
    let invite: CrewInvite
    var showsTitle = true
    @State private var copied = false
    @State private var hovering = false

    var body: some View {
        Button {
            PartyInvitePicker.copy(invite.webURL)
            copied = true
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: copied ? "checkmark" : "link")
                    .font(.system(size: 9, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                if showsTitle {
                    Text(copied ? String(localized: "Copied", bundle: .tabbi) : String(localized: "Invite", bundle: .tabbi))
                        .font(Theme.Typography.caption)
                        .contentTransition(.opacity)
                }
            }
            .foregroundStyle(copied ? Theme.Palette.success : PartyStyle.accent)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Theme.Spacing.s)
            .frame(height: 20)
            .background(Capsule().fill(hovering ? PartyStyle.accent.opacity(0.28) : PartyStyle.accent.opacity(0.16)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(copied ? String(localized: "Copied", bundle: .tabbi)
              : String(localized: "Copy the invite link. Friends who open it can join your crew.", bundle: .tabbi))
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: copied)
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

/// A one-line text field in the Party look. AppKit-backed fields draw
/// blank in snapshots, so a snapshot shows the text (or placeholder) as
/// plain text instead.
struct CrewTextField: View {
    let placeholder: String
    @Binding var text: String
    let field: PartyField
    var focus: FocusState<PartyField?>.Binding
    let limit: Int
    var symbol: String?
    let help: String
    var submit: () -> Void = {}
    @State private var hovering = false

    var body: some View {
        let isFocused = focus.wrappedValue == field
        HStack(spacing: Theme.Spacing.s) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isFocused ? PartyStyle.accent : Theme.Palette.tertiaryText)
                    .frame(width: 12)
            }
            ZStack(alignment: .leading) {
                Color.clear.frame(height: 1)
                if text.isEmpty || PartyStyle.isSnapshot {
                    Text(text.isEmpty ? placeholder : text)
                        .font(Theme.Typography.body)
                        .foregroundStyle(text.isEmpty ? Theme.Palette.tertiaryText : Theme.Palette.primaryText)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }
                if !PartyStyle.isSnapshot {
                    TextField("", text: $text)
                        .textFieldStyle(.plain)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.primaryText)
                        .focused(focus, equals: field)
                        .opacity(isFocused || !text.isEmpty ? 1 : 0)
                        .onSubmit(submit)
                        .onExitCommand {
                            if text.isEmpty { focus.wrappedValue = nil } else { text = "" }
                        }
                        .onChange(of: text) { _, new in
                            if new.count > limit { text = String(new.prefix(limit)) }
                        }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                .fill(hovering || isFocused ? Theme.Palette.surfaceHover : Theme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                .strokeBorder(isFocused ? PartyStyle.accent.opacity(0.5) : Theme.Palette.stroke,
                              lineWidth: isFocused ? 1 : 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = field }
        .onHover { hovering = $0 }
        .help(help)
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: isFocused)
    }
}

/// A member's pet, or a quiet silhouette when they hid it from crew pages.
struct CrewMemberPet: View {
    let member: CrewMember
    var pixelSize: CGFloat = 1

    var body: some View {
        if let profile = member.partyProfile {
            PartyPet(profile: profile, pixelSize: pixelSize)
        } else {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 14 * pixelSize, weight: .semibold))
                .foregroundStyle(Theme.Palette.tertiaryText)
                .frame(width: 40 * pixelSize, height: 40 * pixelSize)
                .background(Circle().fill(Theme.Palette.surface).frame(width: 30 * pixelSize, height: 30 * pixelSize))
                .help(String(localized: "\(member.name) keeps their pet private on crew pages.", bundle: .tabbi))
        }
    }
}

/// The medal-colored rank on the board: 1 gold, 2 silver, 3 bronze.
struct CrewRankBadge: View {
    let rank: Int

    var body: some View {
        Text(rank.formatted())
            .font(.system(size: 10.5, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(Color(white: 0.1))
            .frame(width: 18, height: 18)
            .background(Circle().fill(Self.color(rank)))
            .accessibilityLabel(CrewFormat.rank(rank))
    }

    static func color(_ rank: Int) -> Color {
        switch rank {
        case 1: Color(red: 0.95, green: 0.76, blue: 0.31)
        case 2: Color(red: 0.78, green: 0.82, blue: 0.87)
        case 3: Color(red: 0.85, green: 0.58, blue: 0.36)
        default: Color(white: 0.5)
        }
    }
}

extension View {
    /// Fades content out toward the trailing edge (the left in Arabic), for
    /// rows that scroll sideways, as `edgeFade` does for vertical lists.
    func crewTrailingFade(length: CGFloat = Theme.Spacing.m) -> some View {
        modifier(CrewTrailingFade(length: length))
    }
}

private struct CrewTrailingFade: ViewModifier {
    let length: CGFloat
    @Environment(\.layoutDirection) private var direction

    func body(content: Content) -> some View {
        let toEdge = direction == .rightToLeft
            ? LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
            : LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
        content.mask {
            HStack(spacing: 0) {
                Color.black
                toEdge.frame(width: length)
            }
        }
    }
}

/// Every frame with every emblem, every color, and every laurel with
/// pips, on the notch black, for reviewing the art (`--snapshot` writes it
/// as `crew-crests-1x.png` and `crew-crests-4x.png`).
struct CrewCrestSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(CrewCatalog.frames.enumerated()), id: \.offset) { row, frame in
                HStack(spacing: 4) {
                    ForEach(Array(CrewCatalog.emblems.enumerated()), id: \.offset) { column, emblem in
                        let color = CrewCatalog.colors[(row + column) % CrewCatalog.colors.count].id
                        CrewCrestView(crest: CrewCrest(frame: frame, emblem: emblem, color: color), pixelSize: 1)
                    }
                }
            }
            HStack(spacing: 4) {
                ForEach(Array(CrewCatalog.colors.enumerated()), id: \.offset) { index, color in
                    CrewCrestView(crest: CrewCrest(frame: CrewCatalog.frames[index % CrewCatalog.frames.count],
                                                   emblem: CrewCatalog.emblems[0], color: color.id), pixelSize: 1)
                }
                ForEach(Array(CrewLaurel.allCases.enumerated()), id: \.offset) { index, laurel in
                    CrewCrestView(crest: CrewCrest(frame: CrewCatalog.frames[index], emblem: CrewCatalog.emblems[index + 1],
                                                   color: CrewCatalog.colors[index + 4].id),
                                  laurel: laurel, pips: 3 - index, pixelSize: 1)
                }
            }
        }
        .padding(8)
        .background(Color.black)
    }
}
