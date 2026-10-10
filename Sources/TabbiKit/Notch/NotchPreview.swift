import SwiftUI
import TabbiKitCore

/// The live preview in the two wings beside the closed notch: an icon or
/// artwork on the leading side, short text or the equalizer on the trailing
/// side, crossfading as the ticker rotates.
struct NotchPreview: View {
    let item: TickerItem
    let notchWidth: CGFloat
    let content: NotchContent

    private var catalog: ModuleCatalog { content.catalog }

    var body: some View {
        let wing = NotchPreviewLayout.wingWidth(for: item)
        // Music keeps the centered artwork + equalizer pair it always had;
        // everything else hugs the outer edges like a Dynamic Island.
        let inset = item == .nowPlaying ? 0 : NotchPreviewLayout.outerInset
        let edge: (leading: Alignment, trailing: Alignment) =
            item == .nowPlaying ? (.center, .center) : (.leading, .trailing)
        HStack(spacing: 0) {
            leading
                .padding(.leading, inset)
                .frame(width: wing, alignment: edge.leading)
            Color.clear.frame(width: notchWidth)
            trailing
                .padding(.trailing, inset)
                .frame(width: wing, alignment: edge.trailing)
        }
        .background { MeetingNudgeGlow(isOn: isNudging, tint: accent) }
        .id(item.kind)
        .transition(AsymmetricTransition(
            insertion: .motionRow(from: .bottom),
            removal: .motionRow(from: .top)
        ))
        .help(NotchPreviewLayout.summary(for: item))
    }

    private var accent: Color { catalog.descriptor(for: item.module).accentColor }

    private var isNudging: Bool {
        if case .meeting(let meeting) = item { return meeting.isNudging }
        return false
    }

    private func color(for tone: TickerHighlight.Tone) -> Color {
        switch tone {
        case .accent: accent
        case .primary: Theme.Palette.primaryText
        case .secondary: Theme.Palette.secondaryText
        case .danger: Theme.Palette.danger
        }
    }

    @ViewBuilder private var leading: some View {
        switch item {
        case .nowPlaying:
            content.nowPlayingLeading()
        case .pet(let pet):
            NotchPetWing(pet: pet)
        case .party(let party):
            NotchPartyPets(pets: party.pets)
        case .meeting(let meeting):
            HStack(spacing: Theme.Spacing.xs) {
                icon
                Text(TickerFormat.meetingCountdown(meeting.timing))
                    .foregroundStyle(accent)
                    .previewText()
                    .fixedSize()
            }
        case .focus(let focus):
            if let progress = focus.progress {
                focusRing(focus, progress: progress)
            } else {
                icon
            }
        default:
            icon
        }
    }

    /// A thin ring around a smaller timer icon that fills as the phase
    /// passes; it dims with the clock while paused.
    private func focusRing(_ focus: TickerFocus, progress: Double) -> some View {
        let tint = focus.isRunning ? accent : Theme.Palette.secondaryText
        return ProgressRing(progress: progress, tint: tint, lineWidth: NotchPreviewLayout.focusRingWidth) {
            Image(systemName: NotchPreviewLayout.symbol(for: item, catalog: catalog))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(tint)
        }
        .padding(NotchPreviewLayout.focusRingWidth / 2 + 1)
        .frame(width: NotchPreviewLayout.iconSize, height: NotchPreviewLayout.iconSize)
    }

    private var icon: some View {
        Image(systemName: NotchPreviewLayout.symbol(for: item, catalog: catalog))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: NotchPreviewLayout.iconSize, height: NotchPreviewLayout.iconSize)
    }

    @ViewBuilder private var trailing: some View {
        switch item {
        case .nowPlaying:
            content.nowPlayingTrailing()
        case .meeting(let meeting):
            HStack(spacing: Theme.Spacing.xs) {
                Text(meeting.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .truncationMode(.tail)
                    .previewText()
                if meeting.offersJoin, let link = meeting.link {
                    NotchJoinButton(link: link, tint: accent)
                        .transition(.opacity)
                }
            }
            .motion(Theme.Motion.content, value: meeting.offersJoin)
        case .focus(let focus):
            Text(TickerFormat.focusClock(focus.time))
                .foregroundStyle(focus.isRunning ? accent : Theme.Palette.secondaryText)
                .previewText()
        case .tasks(let remaining):
            Text(TickerFormat.tasksLeft(remaining))
                .foregroundStyle(Theme.Palette.primaryText)
                .previewText()
        case .progress(let progress):
            Text(TickerFormat.progressLeft(progress))
                .foregroundStyle(Theme.Palette.primaryText)
                .previewText()
        case .highlight(let highlight):
            Text(highlight.text)
                .foregroundStyle(color(for: highlight.tone))
                .truncationMode(.tail)
                .previewText()
        case .pet(let pet) where pet.isSipping:
            HStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: NotchPreviewLayout.chargingSymbolSize, weight: .bold))
                Text(TickerFormat.charging)
                    .fixedSize()
            }
            .foregroundStyle(Theme.Palette.success)
            .previewText()
        case .pet(let pet):
            HStack(spacing: Theme.Spacing.xs) {
                if let name = TickerFormat.petLabel(pet) {
                    Text(name)
                        .foregroundStyle(pet.mood == .asleep ? Theme.Palette.secondaryText : Theme.Palette.primaryText)
                        .truncationMode(.tail)
                }
                if pet.mood == .asleep {
                    Text(TickerFormat.petSleeping)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                        .fixedSize()
                        .transition(.opacity)
                }
            }
            .previewText()
            .motion(Theme.Motion.content, value: pet.mood)
        case .party(let party):
            Text(TickerFormat.partySize(party.memberCount))
                .foregroundStyle(accent)
                .previewText()
        }
    }
}

/// The closed notch's Join button for a meeting about to start: a small
/// accent pill that opens the call, so the user can go straight in.
private struct NotchJoinButton: View {
    let link: MeetingLink
    let tint: Color
    @State private var hovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(link.url)
        } label: {
            Text(NotchPreviewLayout.joinTitle)
                .font(Theme.Typography.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.background)
                .padding(.horizontal, NotchPreviewLayout.joinPadding)
                .frame(height: NotchPreviewLayout.joinHeight)
                .background(Capsule(style: .continuous).fill(tint.opacity(hovering ? 1 : 0.88)))
                .contentShape(Capsule(style: .continuous))
                .fixedSize()
        }
        .buttonStyle(.plain)
        .help("Join \(link.provider.displayName) call")
        .accessibilityLabel("Join \(link.provider.displayName) call")
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// The "leave now" glow: a soft accent light rising from the bottom edge of
/// the closed notch that breathes a few times while `isOn`, then fades.
/// Under Reduce Motion it holds still and only fades in and out; at the
/// Instant pace it holds still and simply appears.
private struct MeetingNudgeGlow: View {
    let isOn: Bool
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        LinearGradient(colors: [tint.opacity(0), tint.opacity(dimmed ? 0.18 : 0.5)],
                       startPoint: .top, endPoint: .bottom)
            .opacity(isOn ? 1 : 0)
            .allowsHitTesting(false)
            .animation(Motion.adapted(Theme.Motion.content, reduceMotion: reduceMotion), value: isOn)
            .onChange(of: isOn, initial: true) { _, on in
                guard on, Motion.pace.isAnimated(reduceMotion: reduceMotion) else { return dimmed = false }
                withAnimation(.easeInOut(duration: 0.8).repeatCount(4, autoreverses: true)) { dimmed = true }
            }
    }
}

/// The user's pet with the other party members' pets behind it, overlapping
/// slightly so up to four fit in one wing. Away members' pets doze.
private struct NotchPartyPets: View {
    let pets: [ProvidedPartyPet]

    var body: some View {
        HStack(spacing: NotchPreviewLayout.partyPetStep - side) {
            // The user's pet leads and is drawn on top.
            ForEach(Array(pets.enumerated()), id: \.element.id) { index, pet in
                NotchPartyPet(pet: pet)
                    .zIndex(Double(pets.count - index))
            }
        }
        .frame(height: side)
        // Paws sit at the bottom of the sprite frame, above headroom for
        // hops, so lift the row to center the pets optically.
        .offset(y: -Theme.Spacing.xxs)
    }

    private var side: CGFloat { CGFloat(PetComposer.frameSize) * NotchPreviewLayout.partyPetPixelSize }
}

private struct NotchPartyPet: View {
    let pet: ProvidedPartyPet
    @StateObject private var player: PetPlayer

    init(pet: ProvidedPartyPet) {
        self.pet = pet
        _player = StateObject(wrappedValue: PetPlayer(profile: pet.pet, asleep: pet.isAway))
    }

    var body: some View {
        PetView(player: player, pixelSize: NotchPreviewLayout.partyPetPixelSize)
            .onChange(of: pet.pet) { _, profile in player.update(profile: profile) }
            .onChange(of: pet.isAway) { _, away in player.send(away ? .sleep : .wake) }
    }
}

private extension View {
    func previewText() -> some View {
        font(Theme.Typography.caption)
            .monospacedDigit()
            .lineLimit(1)
            .contentTransition(.numericText())
    }
}
