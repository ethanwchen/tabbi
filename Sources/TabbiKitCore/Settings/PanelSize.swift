import CoreGraphics

/// How big the open notch is. Every tab lays out inside the same canvas, so
/// one choice sizes them all: Compact keeps a small screen clear, Large gives
/// lists and charts more room.
public enum PanelSize: String, CaseIterable, Sendable {
    case compact
    case regular
    case large

    public static let `default`: PanelSize = .regular

    /// The open notch's canvas, header included. Regular is the size every
    /// panel was first designed for. Compact is only a little narrower, so
    /// five tabs still fit left of a 14" MacBook Pro notch at the 24pt
    /// minimum hit target; it saves its room in height and type instead.
    public var canvasSize: CGSize {
        switch self {
        case .compact: CGSize(width: 512, height: 224)
        case .regular: CGSize(width: 560, height: 236)
        case .large: CGSize(width: 640, height: 272)
        }
    }

    /// How much every panel's type, icons, controls and spacing grow at this
    /// size. Panels are designed once, at Regular, and the open notch lays
    /// them out in its canvas divided by this factor and draws them that
    /// much larger, so Large reads larger instead of looking empty while
    /// still leaving lists a little more room. Compact keeps Regular's type
    /// and adapts its layouts instead. 9/8 keeps the 4pt grid on whole
    /// pixels of a Retina screen (4pt becomes 9px).
    public var contentScale: CGFloat {
        switch self {
        case .compact, .regular: 1
        case .large: 9.0 / 8.0
        }
    }

    /// The name Settings shows.
    public var title: String {
        switch self {
        case .compact: "Compact"
        case .regular: "Regular"
        case .large: "Large"
        }
    }
}
