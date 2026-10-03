import SwiftUI
import NotchKitCore

/// The live preview in the two wings beside the closed notch: an icon or
/// artwork on the leading side, short text or the equalizer on the trailing
/// side, crossfading as the ticker rotates.
struct NotchPreview: View {
    let item: TickerItem
    let notchWidth: CGFloat
    let content: NotchContent

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
        .id(item.kind)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(y: 6)),
            removal: .opacity.combined(with: .offset(y: -6))
        ))
        .help(NotchPreviewLayout.summary(for: item))
    }

    private var accent: Color { Theme.Palette.accent(for: item.module) }

    @ViewBuilder private var leading: some View {
        switch item {
        case .nowPlaying:
            content.nowPlayingLeading()
        case .pet(let pet):
            NotchPetWing(pet: pet)
        case .party(let party):
            NotchPartyPets(pets: party.pets)
        default:
            Image(systemName: NotchPreviewLayout.symbol(for: item))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: NotchPreviewLayout.iconSize, height: NotchPreviewLayout.iconSize)
        }
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
                Text(TickerFormat.meetingCountdown(meeting.timing))
                    .foregroundStyle(accent)
                    .fixedSize()
            }
            .previewText()
        case .focus(_, let remaining, let isRunning):
            Text(TickerFormat.focusClock(remaining))
                .foregroundStyle(isRunning ? accent : Theme.Palette.secondaryText)
                .previewText()
        case .tasks(let remaining):
            Text(TickerFormat.tasksLeft(remaining))
                .foregroundStyle(Theme.Palette.primaryText)
                .previewText()
        case .progress(let progress):
            Text(TickerFormat.progressLeft(progress))
                .foregroundStyle(Theme.Palette.primaryText)
                .previewText()
        case .claudeUsage(let window, let utilization):
            Text(TickerFormat.usage(window: window, utilization: utilization))
                .foregroundStyle(utilization >= 1 ? Theme.Palette.danger : accent)
                .previewText()
        case .pet(let pet):
            HStack(spacing: Theme.Spacing.xs) {
                Text(pet.profile.name)
                    .foregroundStyle(pet.mood == .asleep ? Theme.Palette.secondaryText : Theme.Palette.primaryText)
                    .truncationMode(.tail)
                if pet.mood == .asleep {
                    Text(TickerFormat.petSleeping)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                        .fixedSize()
                        .transition(.opacity)
                }
            }
            .previewText()
            .animation(Theme.Motion.content, value: pet.mood)
        case .party(let party):
            Text(TickerFormat.partySize(party.memberCount))
                .foregroundStyle(accent)
                .previewText()
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
