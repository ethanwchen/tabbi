import SwiftUI
import TabbiKitCore

/// The Founding Member badge: a small gold seal, in the gold of the
/// Founder's Pin, for people who signed in during Tabbi's first 100 days.
/// `.seal` is the bare icon that sits beside a name in the notch (Party's
/// roster and friends list); `.label` adds the words, for the Account row
/// in Settings. Both explain themselves on hover, to the user about
/// themselves (`isMe`) or about someone else.
public struct FoundingBadge: View {
    public enum Style: Sendable {
        case seal
        case label
    }

    /// `#F2C14E`, the pet palette's gold, so the badge matches the pin.
    public static let gold = Color(red: 0xF2 / 255, green: 0xC1 / 255, blue: 0x4E / 255)

    /// The badge's one line of copy, its tooltip and accessibility label.
    public static func explanation(isMe: Bool) -> String {
        isMe ? String(localized: "Founding Member: you joined Tabbi in its first 100 days.", bundle: .tabbi)
            : String(localized: "Founding Member: joined Tabbi in its first 100 days.", bundle: .tabbi)
    }

    private let style: Style
    private let isMe: Bool

    public init(_ style: Style = .seal, isMe: Bool) {
        self.style = style
        self.isMe = isMe
    }

    public var body: some View {
        Group {
            switch style {
            case .seal:
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Self.gold)
            case .label:
                // Not a Label: a Form spreads its icon and title apart.
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Self.gold)
                    Text("Founding Member", bundle: .tabbi).foregroundStyle(.secondary)
                }
                .font(.caption.weight(.semibold))
                .fixedSize()
            }
        }
        .help(Self.explanation(isMe: isMe))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.explanation(isMe: isMe))
    }
}
