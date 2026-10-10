import SwiftUI
import TabbiKitCore
import TabbiKit

/// Onboarding's pet step: cat or dog, a breed and a name, each one tap (or
/// a few keystrokes) on the shared pet, so the Closet, the coach and the
/// closed notch start with the pet picked here. Edits apply right away;
/// the footer's Continue just moves on.
struct ClosetSetupView: View {
    @ObservedObject var store: ClosetStore

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            ClosetSetupPetCard(store: store)
                .frame(width: 140)
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(PetSpecies.allCases, id: \.self) { species in
                            ClosetSetupSpeciesPill(species: species, isSelected: store.profile.species == species) {
                                withMotion(Theme.Motion.snappy) { store.setSpecies(species) }
                            }
                        }
                        Spacer(minLength: 0)
                        Text(store.profile.breed.displayName)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.secondaryText)
                            .lineLimit(1)
                            .contentTransition(.opacity)
                    }
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(PetBreed.breeds(of: store.profile.species), id: \.self) { breed in
                            ClosetSetupBreedTile(profile: preview(of: breed),
                                                 isSelected: store.profile.breed == breed) {
                                withMotion(Theme.Motion.snappy) { store.setBreed(breed) }
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                    HStack(spacing: Theme.Spacing.s - Theme.Spacing.xxs) {
                        Text("Fur")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.tertiaryText)
                            .frame(width: 28, alignment: .leading)
                        ClosetSwatch(color: nil, isSelected: store.closet.furTint == nil) {
                            store.tintFur(nil)
                        }
                        ForEach(PetCloset.furSwatches, id: \.self) { color in
                            ClosetSwatch(color: color, isSelected: store.closet.furTint == color) {
                                store.tintFur(color)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    /// The pet as it would look as `breed`, with its fur color and outfit.
    private func preview(of breed: PetBreed) -> PetProfile {
        var closet = store.closet
        closet.setBreed(breed)
        return closet.profile
    }
}

private var accent: Color { ClosetModule.descriptor.accentColor }

/// The pet, animated, above its name in a field-like button; a click
/// edits it in place, as in the Closet tab.
private struct ClosetSetupPetCard: View {
    @ObservedObject var store: ClosetStore
    @State private var isRenaming = false
    @State private var draft = ""
    @State private var hovering = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        Card(padding: Theme.Spacing.s) {
            VStack(spacing: Theme.Spacing.s) {
                PetView(player: store.preview, pixelSize: 2)
                    .frame(maxHeight: .infinity)
                nameField
                    .padding(.horizontal, Theme.Spacing.s)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                            .fill(hovering || isRenaming ? Theme.Palette.surfaceHover : Theme.Palette.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                            .strokeBorder(isRenaming ? accent.opacity(0.7) : Theme.Palette.stroke, lineWidth: 0.5)
                    )
                    .onHover { hovering = $0 }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Continue moves on without a Return, so keep what was typed.
        .onDisappear(perform: commit)
        .motion(Theme.Motion.snappy, value: hovering)
    }

    @ViewBuilder private var nameField: some View {
        if isRenaming {
            TextField("Name", text: $draft)
                .textFieldStyle(.plain)
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(Theme.Palette.primaryText)
                .multilineTextAlignment(.center)
                .focused($nameFocused)
                .onAppear { nameFocused = true }
                .onSubmit(commit)
                .onExitCommand { isRenaming = false }
                .onChange(of: nameFocused) { _, focused in if !focused { commit() } }
        } else {
            Button {
                draft = store.profile.name
                isRenaming = true
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(store.profile.name)
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(Theme.Palette.primaryText)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                    Image(systemName: "pencil")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(hovering ? Theme.Palette.secondaryText : Theme.Palette.tertiaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Name your pet")
        }
    }

    private func commit() {
        guard isRenaming else { return }
        store.rename(draft)
        isRenaming = false
    }
}

/// Cat or Dog, accent-tinted when picked.
private struct ClosetSetupSpeciesPill: View {
    let species: PetSpecies
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: species == .cat ? "cat.fill" : "dog.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(species.displayName).lineLimit(1)
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(isSelected ? accent : hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
            .padding(.horizontal, Theme.Spacing.m)
            .frame(height: 24)
            .background(Capsule().fill(isSelected ? accent.opacity(0.16) : hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface))
            .overlay(Capsule().strokeBorder(isSelected ? accent.opacity(0.7) : Theme.Palette.stroke, lineWidth: isSelected ? 1 : 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Pick a \(species.displayName.lowercased())")
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// One breed as a sitting sprite; a tap picks it.
private struct ClosetSetupBreedTile: View {
    let profile: PetProfile
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            // The sprite's canvas has transparent margins, so let the tile
            // shrink below it (and clip) rather than push the row past the
            // panel when a species has many breeds.
            PetSpriteView(profile: profile)
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                        .fill(isSelected ? accent.opacity(0.14) : hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                        .strokeBorder(isSelected ? accent.opacity(0.8) : Theme.Palette.stroke, lineWidth: isSelected ? 1 : 0.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(profile.breed.displayName)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}
