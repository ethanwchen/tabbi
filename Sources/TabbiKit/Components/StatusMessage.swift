import SwiftUI
import TabbiKitCore

/// A panel's empty, loading, unavailable or error state: a glyph (or a
/// spinner while something is on its way) in a soft accent badge, a title,
/// one line of guidance and at most a row of actions, centered in the room
/// it gets. Every module draws these states with it, so they read the same
/// from tab to tab.
///
/// When the app shares the user's pet through `statusPet`, the pet sits
/// in the badge's place with the glyph tucked at its paws, so "No music
/// app is open" reads like Tabbi rather than a system alert.
public struct StatusMessage<Actions: View>: View {
    /// Nil shows a spinner instead of a glyph.
    let symbol: String?
    let tint: Color
    let title: String
    let message: String
    let actions: Actions

    @Environment(\.statusPet) private var pet

    public static var badgeSize: CGFloat { 32 }

    public init(symbol: String?, tint: Color, title: String, message: String,
                @ViewBuilder actions: () -> Actions) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.message = message
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            if let symbol, let pet {
                StatusPet(profile: pet, symbol: symbol, tint: tint)
            } else {
                ZStack {
                    Circle().fill(tint.opacity(0.14))
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(tint)
                    } else {
                        Spinner(tint: tint, size: 14, lineWidth: 2)
                    }
                }
                .frame(width: Self.badgeSize, height: Self.badgeSize)
            }

            VStack(spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(1)
                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 360)

            if Actions.self != EmptyView.self {
                actions
                    .padding(.top, Theme.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension StatusMessage where Actions == EmptyView {
    /// A state with nothing to do but wait or read.
    public init(symbol: String?, tint: Color, title: String, message: String) {
        self.init(symbol: symbol, tint: tint, title: title, message: message) { EmptyView() }
    }
}

public extension EnvironmentValues {
    /// The user's pet, which `StatusMessage` shows in empty and error
    /// states; nil (no pet module on) keeps the plain glyph badge.
    @Entry var statusPet: PetProfile? = nil
}

/// The pet sitting in a `StatusMessage`, with the state's glyph in a small
/// accent badge at its side so the meaning still reads at a glance.
private struct StatusPet: View {
    let profile: PetProfile
    let symbol: String
    let tint: Color
    @StateObject private var player: PetPlayer

    /// Whole points per sprite pixel keep the art crisp on 2x displays.
    private static let pixelSize: CGFloat = 1
    private static let glyphBadge: CGFloat = 14

    init(profile: PetProfile, symbol: String, tint: Color) {
        self.profile = profile
        self.symbol = symbol
        self.tint = tint
        _player = StateObject(wrappedValue: PetPlayer(profile: profile))
    }

    var body: some View {
        PetView(player: player, pixelSize: Self.pixelSize)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: symbol)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: Self.glyphBadge, height: Self.glyphBadge)
                    .background(Circle().fill(tint.opacity(0.16)))
                    // The sitting pet's fur ends a few sprite pixels inside
                    // its frame, so this puts the badge beside its paws
                    // instead of over them.
                    .offset(x: Theme.Spacing.s, y: -Theme.Spacing.xxs)
            }
            .onChange(of: profile) { _, profile in player.update(profile: profile) }
    }
}
