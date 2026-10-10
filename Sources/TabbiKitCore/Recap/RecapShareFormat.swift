import Foundation

/// The shapes a weekly recap exports to: a square post and a 9:16 story,
/// both 1080 pixels wide so they look sharp on a phone.
public enum RecapShareFormat: String, CaseIterable, Hashable, Sendable, Identifiable {
    case square
    case story

    /// The brand line printed on every exported image.
    public static let brandName = "Tabbi"
    public static let website = "tabbinotch.com"

    /// Pixels per point the image is drawn at.
    public static let scale: Double = 3

    public var id: String { rawValue }

    /// Size of the exported PNG, in pixels.
    public var pixelSize: (width: Int, height: Int) {
        switch self {
        case .square: (1080, 1080)
        case .story: (1080, 1920)
        }
    }

    /// Size of the layout the image is drawn from, in points.
    public var pointSize: (width: Double, height: Double) {
        (Double(pixelSize.width) / Self.scale, Double(pixelSize.height) / Self.scale)
    }

    /// The menu item that exports this shape.
    public var title: String {
        switch self {
        case .square: "Square (1:1)"
        case .story: "Story (9:16)"
        }
    }

    /// A file name for `week`'s image in this shape, safe on every file
    /// system, for example "Tabbi week Oct 5 - 11 (square).png".
    public func fileName(for week: RecapWeek, calendar: Calendar = .current,
                         locale: Locale = .current) -> String {
        let title = week.title(calendar: calendar, locale: locale)
        let forbidden = CharacterSet(charactersIn: "/:\\")
        let safe = title.unicodeScalars.map { forbidden.contains($0) ? "-" : String($0) }.joined()
        return "\(Self.brandName) week \(safe) (\(rawValue)).png"
    }
}
