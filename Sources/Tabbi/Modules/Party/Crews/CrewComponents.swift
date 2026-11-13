import AppKit
import SwiftUI
import TabbiKitCore
import TabbiKit

// The small building blocks of the Crews screens, measured from the Crews UI
// spec (runs/crews/ui-design/spec.md): Closet-style pills, crests, pixel
// medals and tallies, place chips, the pet groups, whole-row lists and the
// friendly states.

/// The Crews layout's fixed sizes, from the spec.
enum CrewLayout {
    /// Every list row.
    static let rowHeight: CGFloat = 32
    /// The pill row at the top of every Crews screen.
    static let headHeight: CGFloat = 22
    /// Between the pill row and the screen body.
    static let headGap: CGFloat = 6
    /// A featured tile's width at Regular and Large.
    static let tileWidth: CGFloat = 80
    /// The side column of My crew and a crew page.
    static let sideWidth: CGFloat = 168
    /// The crest editor's side column.
    static let editorSideWidth: CGFloat = 160
    /// The "+N more" caption under a list.
    static let moreHeight: CGFloat = 14
    /// The rank column of a row.
    static let rankWidth: CGFloat = 16
    /// A pet's column in a member row.
    static let petColumn: CGFloat = 26
}

/// The panel size the Crews screens adapt to: Compact folds the featured
/// tiles into the list.
private struct CrewCompactKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var crewIsCompact: Bool {
        get { self[CrewCompactKey.self] }
        set { self[CrewCompactKey.self] = newValue }
    }
}

// MARK: - Pixel art

/// A crew's crest at a whole number of device pixels per sprite pixel.
struct CrewCrestView: View {
    let crest: CrewCrest
    var laurel: CrewLaurel?
    var pips = 0
    /// Points per sprite pixel before the panel's content scale: 1 in rows
    /// (32 pt), 1.5 on the hero and the editor preview (48 pt).
    var pixelSize: CGFloat = CrewCrestArt.compactPixelSize

    static func side(_ pixelSize: CGFloat) -> CGFloat { CGFloat(CrewCrestArt.size) * pixelSize }

    var body: some View {
        CrewPixelImage(size: CGSize(width: CrewCrestArt.size, height: CrewCrestArt.size), pixelSize: pixelSize) { scale in
            CrewCrestArt.image(crest, laurel: laurel, pips: pips, scale: scale)
        }
    }
}

extension CrewCrestView {
    /// A crew's crest with its laurel; the hero size also shows its gold pips.
    init(crew: CrewSummary, hero: Bool = false) {
        self.init(crest: crew.crest, laurel: crew.laurel, pips: hero ? crew.pips : 0,
                  pixelSize: hero ? CrewCrestArt.regularPixelSize : CrewCrestArt.compactPixelSize)
    }
}

/// Pixel art drawn crisp: whole device pixels per sprite pixel, never
/// mirrored in right-to-left layouts.
struct CrewPixelImage: View {
    let size: CGSize
    let pixelSize: CGFloat
    let image: (Int) -> CGImage?
    @Environment(\.displayScale) private var displayScale
    @Environment(\.panelScale) private var panelScale

    var body: some View {
        let scale = max(1, Int((pixelSize * panelScale * displayScale).rounded()))
        let point = CGFloat(scale) / displayScale / panelScale
        Group {
            if let cgImage = image(scale) {
                Image(decorative: cgImage, scale: displayScale)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: size.width * point, height: size.height * point)
            }
        }
        .frame(width: size.width * pixelSize, height: size.height * pixelSize)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}

/// One pixel medal.
struct CrewMedalView: View {
    let metal: CrewLaurel
    var pixelSize: CGFloat = 1

    var body: some View {
        CrewPixelImage(size: CGSize(width: CrewMedalArt.width, height: CrewMedalArt.height), pixelSize: pixelSize) {
            CrewMedalArt.image(metal, scale: $0)
        }
    }
}

/// Gold, silver and bronze with their counts; a zero greys its medal and
/// number, so a crew with one medal reads at a glance.
struct CrewTally: View {
    let medals: CrewMedals
    var large = false

    var body: some View {
        HStack(spacing: 5) {
            item(.gold, medals.gold)
            item(.silver, medals.silver)
            item(.bronze, medals.bronze)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.label(medals))
        .help(String(localized: "Ranked by golds, then silvers, then bronzes, then whoever reached the tally first.", bundle: .tabbi))
    }

    private func item(_ metal: CrewLaurel, _ count: Int) -> some View {
        HStack(spacing: large ? 4 : 3) {
            CrewMedalView(metal: metal, pixelSize: large ? 1.5 : 1)
                .saturation(count == 0 ? 0 : 1)
                .opacity(count == 0 ? 0.35 : 1)
            Text(count.formatted())
                .font(.system(size: large ? 13 : 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(count == 0 ? Theme.Palette.tertiaryText : Theme.Palette.primaryText)
                .environment(\.layoutDirection, .leftToRight)
        }
    }

    nonisolated static func label(_ medals: CrewMedals) -> String {
        String(localized: "\(medals.gold) gold, \(medals.silver) silver, \(medals.bronze) bronze", bundle: .tabbi)
    }
}

/// The "1st", "2nd", "3rd" chip in the metal's tint.
struct CrewPlaceChip: View {
    let place: Int

    var body: some View {
        Text(CrewFormat.ordinal(place))
            .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(Self.metal(place))
            .padding(.horizontal, 5)
            .frame(height: 14)
            .background(Capsule().fill(Self.metal(place).opacity(0.22)))
            .fixedSize()
    }

    static func metal(_ place: Int) -> Color {
        switch place {
        case 1: Color(red: 0.95, green: 0.76, blue: 0.31)
        case 2: Color(red: 0.78, green: 0.82, blue: 0.87)
        case 3: Color(red: 0.85, green: 0.58, blue: 0.36)
        default: Theme.Palette.secondaryText
        }
    }
}

/// A member's pet, or a quiet paw when they hid it from crew pages.
struct CrewPetView: View {
    let pet: CrewPet?
    var name = ""
    var asleep = false
    var pixelSize: CGFloat = 1

    var body: some View {
        if let pet {
            PartyPet(profile: PartyProfile(code: "", name: name, petName: pet.petName, species: pet.species, breed: pet.breed,
                                           colors: pet.colors, costume: pet.costume, accessories: pet.accessories),
                     asleep: asleep, pixelSize: pixelSize)
                .environment(\.layoutDirection, .leftToRight)
                .help(pet.petName)
        } else {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 11 * pixelSize, weight: .semibold))
                .foregroundStyle(Theme.Palette.tertiaryText)
                .frame(width: 32 * pixelSize, height: 32 * pixelSize, alignment: .bottom)
                .padding(.bottom, 4 * pixelSize)
                .help(String(localized: "\(name) keeps their pet private on crew pages.", bundle: .tabbi))
        }
    }
}

/// A little group of pets standing on one baseline; their sprite frames
/// overlap so the pets stand close, as in the prototype.
struct CrewPetGroup: View {
    let pets: [CrewPet]
    var overlap: CGFloat = 12

    var body: some View {
        HStack(alignment: .bottom, spacing: -overlap) {
            ForEach(Array(pets.enumerated()), id: \.offset) { _, pet in
                CrewPetView(pet: pet)
            }
        }
        .fixedSize()
    }
}

// MARK: - Pills and buttons

/// A Closet-style pill: accent tint when selected, a glyph and an optional title.
struct CrewPill: View {
    let title: String
    let symbol: String
    var showsTitle = true
    var isSelected = false
    var help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: symbol).font(.system(size: 9.5, weight: .bold))
                if showsTitle { Text(title).lineLimit(1).fixedSize() }
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(isSelected ? PartyStyle.accent : hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
            .padding(.horizontal, showsTitle ? Theme.Spacing.s : 7)
            .frame(height: CrewLayout.headHeight)
            .background(Capsule().fill(isSelected ? PartyStyle.accent.opacity(0.16) : hovering ? Theme.Palette.surfaceHover : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(showsTitle ? help : "\(title): \(help)")
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// The Party and Crews mode switch in the Party stage's header (Party mode).
/// `partyTitle` and `crewsTitle` step down the spec's fit ladder.
struct PartyModeSwitch: View {
    @ObservedObject var crews: CrewsStore
    var partyTitle = true
    var crewsTitle = true
    /// The last step of a header's ladder: only the way to the other mode,
    /// as a glyph, when even two glyphs would push the header past the card.
    var otherModeOnly = false

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            if !(otherModeOnly && !crews.showsCrews) {
                CrewPill(title: String(localized: "Party", bundle: .tabbi), symbol: "person.3.fill", showsTitle: partyTitle && !otherModeOnly,
                         isSelected: !crews.showsCrews, help: String(localized: "Back to your party and friends", bundle: .tabbi)) {
                    withMotion(Theme.Motion.content) { crews.setShowsCrews(false) }
                }
            }
            if !(otherModeOnly && crews.showsCrews) {
                CrewPill(title: String(localized: "Crews", bundle: .tabbi), symbol: "flag.fill", showsTitle: crewsTitle && !otherModeOnly,
                         isSelected: crews.showsCrews, help: String(localized: "Study crews: weekly board and Hall of Fame", bundle: .tabbi)) {
                    withMotion(Theme.Motion.content) { crews.setShowsCrews(true) }
                }
            }
        }
        .fixedSize()
    }
}

/// A capsule button: tint, prominent (filled) or quiet, 20 pt in rows and
/// headers and 24 pt in the friendly states.
struct CrewButton: View {
    enum Style { case tint, prominent, quiet }

    let title: String
    var symbol: String?
    var style = Style.tint
    var height: CGFloat = 20
    var isEnabled = true
    var isBusy = false
    /// Only the symbol, for a column too narrow for the title; the title
    /// stays the accessibility label and the tooltip keeps the help.
    var iconOnly = false
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                if let symbol { Image(systemName: symbol).font(.system(size: 9.5, weight: .bold)) }
                if !(iconOnly && symbol != nil) { Text(title).lineLimit(1).fixedSize() }
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(foreground)
            .padding(.horizontal, style == .quiet ? Theme.Spacing.s : 10)
            .frame(height: height)
            .background(Capsule().fill(background))
            .contentShape(Capsule())
            .opacity(isEnabled && !isBusy ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .disabled(!isEnabled || isBusy)
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }

    private var foreground: Color {
        switch style {
        case .tint: PartyStyle.accent
        case .prominent: Theme.Palette.onAccent
        case .quiet: hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText
        }
    }

    private var background: Color {
        switch style {
        case .tint: PartyStyle.accent.opacity(hovering ? 0.28 : 0.16)
        case .prominent: PartyStyle.accent.opacity(hovering ? 1 : 0.9)
        case .quiet: hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface
        }
    }
}

/// A small round icon button, 20 pt.
struct CrewIconButton: View {
    let symbol: String
    let help: String
    var filled = false
    var isBusy = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(filled ? Theme.Palette.onAccent : Theme.Palette.primaryText)
                .frame(width: 20, height: 20)
                .background(Circle().fill(filled ? PartyStyle.accent.opacity(hovering ? 1 : 0.9)
                                          : hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface))
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

/// A small tag: "Requested", "Your crew", "Private".
struct CrewTag: View {
    let title: String
    var symbol: String?
    var accent = false

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).font(.system(size: 8, weight: .bold)) }
            Text(title).lineLimit(1).fixedSize()
        }
        .font(Theme.Typography.caption)
        .foregroundStyle(accent ? PartyStyle.accent : Theme.Palette.secondaryText)
        .padding(.horizontal, 6)
        .frame(height: 16)
        .background(Capsule().fill(Theme.Palette.surface))
    }
}

/// Copies my crew's invite link and confirms with a check.
struct CrewInviteButton: View {
    let invite: CrewInvite
    var showsTitle = true
    @State private var copied = false

    var body: some View {
        CrewButton(title: copied ? String(localized: "Copied", bundle: .tabbi) : String(localized: "Invite link", bundle: .tabbi),
                   symbol: copied ? "checkmark" : "link",
                   help: String(localized: "Copy an invite link. A friend who opens it joins this crew in one click.", bundle: .tabbi)) {
            PartyInvitePicker.copy(invite.webURL)
            copied = true
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

/// A one-line text field in the Party code field's shape. AppKit-backed
/// fields draw blank in snapshots, so a snapshot shows the text as text.
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
                        .onExitCommand { if text.isEmpty { focus.wrappedValue = nil } else { text = "" } }
                        .onChange(of: text) { _, new in if new.count > limit { text = String(new.prefix(limit)) } }
                }
            }
        }
        .padding(.leading, Theme.Spacing.s)
        .padding(.trailing, Theme.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
            .fill(hovering || isFocused ? Theme.Palette.surfaceHover : Theme.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
            .strokeBorder(isFocused ? PartyStyle.accent.opacity(0.5) : Theme.Palette.stroke, lineWidth: isFocused ? 1 : 0.5))
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = field }
        .onHover { hovering = $0 }
        .help(help)
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: isFocused)
    }
}

// MARK: - Lists

/// A list that shows whole rows only: its viewport is a multiple of the row
/// height, it scrolls by rows, and when rows are left over a "+N more"
/// caption (or a hairline where 14 pt will not fit) says the list goes on.
/// A pinned row (my crew) sits under a hairline below it and replaces the
/// caption. Snapshots draw the first rows as they would show.
struct CrewRowList<Row: View, Pinned: View>: View {
    let count: Int
    @ViewBuilder var row: (Int) -> Row
    var pinned: Pinned?
    /// A one-line form of the pinned row, for a list so short that the full
    /// pinned row would leave fewer than `minimumRows` rows above it.
    var slimPinned: AnyView?
    /// The rows that must show above the pinned row (the top 3), when the
    /// list has that many.
    var minimumRows = 0
    /// Called when the last loaded rows come into view, to load another page.
    var nearEnd: () -> Void = {}

    private static var separatorHeight: CGFloat { 6 }

    var body: some View {
        GeometryReader { proxy in
            let fullPinned: CGFloat = pinned == nil ? 0 : CrewLayout.rowHeight + Self.separatorHeight
            let fits = { (pinnedHeight: CGFloat) in max(1, Int(max(0, proxy.size.height - pinnedHeight) / CrewLayout.rowHeight)) }
            let usesSlim = pinned != nil && slimPinned != nil && fits(fullPinned) < min(count, minimumRows)
            let pinnedHeight = usesSlim ? CrewLayout.moreHeight + Self.separatorHeight : fullPinned
            let available = max(0, proxy.size.height - pinnedHeight)
            let visible = fits(pinnedHeight)
            let extra = count - visible
            let leftOver = available - CGFloat(min(count, visible)) * CrewLayout.rowHeight
            VStack(alignment: .leading, spacing: 0) {
                rows(visible: visible)
                if extra > 0, pinned == nil {
                    if leftOver >= CrewLayout.moreHeight {
                        Text(String(localized: "\(extra) more", bundle: .tabbi))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.tertiaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: CrewLayout.moreHeight)
                    } else {
                        Rectangle().fill(Theme.Palette.stroke).frame(height: 0.5).padding(.horizontal, 4)
                    }
                }
                if let pinned {
                    Rectangle().fill(Theme.Palette.stroke).frame(height: 0.5)
                        .padding(.horizontal, 4).padding(.top, 3).padding(.bottom, 2.5)
                    if usesSlim, let slimPinned {
                        slimPinned.frame(height: CrewLayout.moreHeight)
                    } else {
                        pinned
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func rows(visible: Int) -> some View {
        let height = CGFloat(min(count, visible)) * CrewLayout.rowHeight
        if PartyStyle.isSnapshot || count <= visible {
            VStack(spacing: 0) {
                ForEach(0..<min(count, visible), id: \.self) { row($0) }
            }
            .frame(height: height, alignment: .top)
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        row(index)
                            .onAppear { if index == count - 1 { nearEnd() } }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.never)
            .frame(height: height)
        }
    }
}

extension CrewRowList where Pinned == EmptyView {
    init(count: Int, @ViewBuilder row: @escaping (Int) -> Row, nearEnd: @escaping () -> Void = {}) {
        self.count = count
        self.row = row
        self.pinned = nil
        self.nearEnd = nearEnd
    }
}

/// A 32 pt list row's surface: rounded, with a hover state, and for my crew
/// or me the accent tint with a 2 pt leading bar.
struct CrewRowSurface: ViewModifier {
    var isMine = false
    var action: (() -> Void)?
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 4)
            .frame(height: CrewLayout.rowHeight)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                    .fill(isMine ? PartyStyle.accent.opacity(0.09) : hovering && action != nil ? Theme.Palette.surface : .clear)
            }
            .overlay(alignment: .leading) {
                if isMine { Rectangle().fill(PartyStyle.accent).frame(width: 2) }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { action?() }
            .onHover { hovering = $0 }
            .motion(Theme.Motion.snappy, value: hovering)
    }
}

extension View {
    func crewRow(isMine: Bool = false, action: (() -> Void)? = nil) -> some View {
        modifier(CrewRowSurface(isMine: isMine, action: action))
    }
}

/// A name in a row: one line with its caption under it while it fits, else
/// two lines and no caption, so the name always wins (never an ellipsis).
struct CrewRowName: View {
    let name: String
    let caption: String?
    var captionIsAccent = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(Theme.Typography.bodyEmphasis).foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(1).fixedSize()
                if let caption {
                    Text(caption).font(Theme.Typography.caption)
                        .foregroundStyle(captionIsAccent ? PartyStyle.accent : Theme.Palette.tertiaryText)
                        .lineLimit(1)
                }
            }
            Text(CrewHyphenation.hyphenated(name)).font(Theme.Typography.bodyEmphasis).foregroundStyle(Theme.Palette.primaryText)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - States

/// A friendly whole-screen state: a pet (or a glyph in an accent badge), a
/// title, one line and up to two actions.
struct CrewStatus<Actions: View>: View {
    var pet: (CrewPet?, asleep: Bool)?
    var symbol: String?
    let title: String
    let detail: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            if let pet {
                CrewPetView(pet: pet.0, asleep: pet.asleep, pixelSize: 1.5)
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(PartyStyle.accent)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).fill(PartyStyle.accent.opacity(0.16)))
            }
            VStack(spacing: 2) {
                Text(title).font(Theme.Typography.title).foregroundStyle(Theme.Palette.primaryText)
                if let detail {
                    Text(detail).font(Theme.Typography.body).foregroundStyle(Theme.Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
            HStack(spacing: 6) { actions }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// My own pet as Crews shows it in the friendly states.
extension CrewsStore {
    var myPet: CrewPet {
        CrewPet(profile: party.pet)
    }
}

extension CrewPet {
    /// A local pet as a crew pet, through the Party appearance.
    init(profile: PetProfile) {
        let update = PartyPetAppearance.update(for: profile)
        self.init(petName: update.petName ?? profile.name, species: update.species ?? "cat", breed: update.breed ?? "tabby",
                  colors: update.colors ?? [], costume: update.costume ?? "none", accessories: update.accessories ?? [])
    }
}

// MARK: - Review sheet

/// Every frame with every emblem, every color, and every laurel with pips,
/// on the notch black, for reviewing the art (`--snapshot` writes it as
/// `crew-crests-1x.png` and `crew-crests-4x.png`).
struct CrewCrestSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(CrewCatalog.frames.enumerated()), id: \.offset) { row, frame in
                HStack(spacing: 4) {
                    ForEach(Array(CrewCatalog.emblems.enumerated()), id: \.offset) { column, emblem in
                        let color = CrewCatalog.colors[(row + column) % CrewCatalog.colors.count].id
                        CrewCrestView(crest: CrewCrest(frame: frame, emblem: emblem, color: color))
                    }
                }
            }
            HStack(spacing: 4) {
                ForEach(Array(CrewCatalog.colors.enumerated()), id: \.offset) { index, color in
                    CrewCrestView(crest: CrewCrest(frame: CrewCatalog.frames[index % CrewCatalog.frames.count],
                                                   emblem: CrewCatalog.emblems[0], color: color.id))
                }
                ForEach(Array(CrewLaurel.allCases.enumerated()), id: \.offset) { index, laurel in
                    CrewCrestView(crest: CrewCrest(frame: CrewCatalog.frames[index % CrewCatalog.frames.count],
                                                   emblem: CrewCatalog.emblems[(index + 1) % CrewCatalog.emblems.count],
                                                   color: CrewCatalog.colors[(index + 4) % CrewCatalog.colors.count].id),
                                  laurel: laurel, pips: 3 - index)
                }
                ForEach(CrewLaurel.allCases, id: \.self) { CrewMedalView(metal: $0, pixelSize: 1) }
            }
        }
        .padding(8)
        .background(Color.black)
    }
}
