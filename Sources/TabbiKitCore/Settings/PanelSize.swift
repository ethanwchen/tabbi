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

    /// The name Settings shows.
    public var title: String {
        switch self {
        case .compact: "Compact"
        case .regular: "Regular"
        case .large: "Large"
        }
    }
}
