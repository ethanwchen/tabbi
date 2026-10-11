import SwiftUI
import TabbiKitCore

extension LayoutDirection {
    /// The direction of the language Tabbi shows its strings in
    /// (`L10n.isRightToLeft`): right to left in Arabic.
    public static var tabbi: LayoutDirection { L10n.isRightToLeft ? .rightToLeft : .leftToRight }
}

extension View {
    /// Lays this view out in Tabbi's language direction. Every root Tabbi
    /// hosts (the notch, Settings, the pet coach, snapshot renderers) applies
    /// it, since a hosting view or `ImageRenderer` otherwise follows AppKit,
    /// which reads the main bundle's languages and so stays left to right
    /// under `swift run`.
    public func tabbiLayoutDirection() -> some View {
        environment(\.layoutDirection, .tabbi)
    }

    /// Keeps this view left to right in a right-to-left language, for what
    /// has a direction of its own: time axes, progress, media controls and
    /// pixel art. Text inside still reads in its own direction.
    public func fixedLeftToRight() -> some View {
        environment(\.layoutDirection, .leftToRight)
    }
}
