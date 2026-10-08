import SwiftUI
import TabbiKitCore
import TabbiKit

/// "Great job, team!" across the top of the Party panel when a shared
/// session runs to its end: the members' pets hop, with the points earned
/// beside them. Under Reduce Motion the pets stay put and the banner fades.
struct PartyCelebrationBanner: View {
    let celebration: PartyTeamCelebration
    /// The party's pets, mine first; at most `maxPets` show.
    let pets: [PetProfile]
    let onDismiss: () -> Void
    @State private var hovering = false

    static let maxPets = 4

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            HStack(spacing: -Theme.Spacing.xs) {
                ForEach(Array(pets.prefix(Self.maxPets).enumerated()), id: \.offset) { index, pet in
                    PartyHoppingPet(pet: pet, delay: Double(index) * 0.15)
                }
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(celebration.title)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                Text(celebration.detail)
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(PartyStyle.accent)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(hovering ? Theme.Palette.secondaryText : Theme.Palette.tertiaryText)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
            .fill(Color(white: hovering ? 0.17 : 0.14)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
            .strokeBorder(PartyStyle.accent.opacity(0.4), lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .onHover { hovering = $0 }
        .help("The shared session is done. Click to dismiss.")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// A member's pet that hops once (the celebrate clip) shortly after it
/// appears, staggered so the row bounces like a wave.
private struct PartyHoppingPet: View {
    let pet: PetProfile
    let delay: TimeInterval
    @StateObject private var player: PetPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(pet: PetProfile, delay: TimeInterval) {
        self.pet = pet
        self.delay = delay
        _player = StateObject(wrappedValue: PetPlayer(profile: pet))
    }

    var body: some View {
        PetView(player: player, pixelSize: 1)
            .task {
                guard !reduceMotion else { return }
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                _ = player.send(.celebrate)
            }
    }
}
