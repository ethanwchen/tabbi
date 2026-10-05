import Foundation

/// How long each closed-notch preview item stays on screen before the next one.
public enum TickerInterval: Int, CaseIterable, Identifiable, Sendable {
    case short = 5
    case medium = 8
    case long = 12

    public var id: Int { rawValue }
    public var seconds: TimeInterval { TimeInterval(rawValue) }
    /// Picker label, e.g. "8 seconds".
    public var title: String { "\(rawValue) seconds" }
}

/// Preferences for the live preview beside the closed notch.
///
/// Stores the kinds the user turned *off*, so a kind added in a later
/// version starts enabled instead of silently hidden.
public struct NotchPreviewSettings: Equatable, Sendable {
    /// Master switch; when off the closed notch is always plain black.
    public var isEnabled: Bool
    public var disabledKinds: Set<TickerKind>
    public var interval: TickerInterval

    public static let `default` = NotchPreviewSettings()

    public init(isEnabled: Bool = true, disabledKinds: Set<TickerKind> = [], interval: TickerInterval = .medium) {
        self.isEnabled = isEnabled
        self.disabledKinds = disabledKinds
        self.interval = interval
    }

    /// Whether the ticker may show `kind`: false for every kind while the
    /// master switch is off.
    public func shows(_ kind: TickerKind) -> Bool {
        isEnabled && !disabledKinds.contains(kind)
    }

    public func isEnabled(_ kind: TickerKind) -> Bool {
        !disabledKinds.contains(kind)
    }

    public mutating func setEnabled(_ kind: TickerKind, _ enabled: Bool) {
        if enabled {
            disabledKinds.remove(kind)
        } else {
            disabledKinds.insert(kind)
        }
    }
}
