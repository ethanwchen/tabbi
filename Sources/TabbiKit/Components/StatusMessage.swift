import SwiftUI

/// A panel's empty, loading, unavailable or error state: a glyph (or a
/// spinner while something is on its way) in a soft accent badge, a title,
/// one line of guidance and at most a row of actions, centered in the room
/// it gets. Every module draws these states with it, so they read the same
/// from tab to tab.
public struct StatusMessage<Actions: View>: View {
    /// Nil shows a spinner instead of a glyph.
    let symbol: String?
    let tint: Color
    let title: String
    let message: String
    let actions: Actions

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
