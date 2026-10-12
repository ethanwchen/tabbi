import AppKit
import XCTest
@testable import TabbiKitCore

/// Strings that sit in a slot of fixed width fit it in every language, so
/// none is cut off with an ellipsis. A slot's budget is in points, measured
/// with the font the slot uses; when a translation outgrows it, shorten the
/// translation (docs/localization.md) rather than raising the budget.
final class TightCopyTests: XCTestCase {
    /// A one-line title left of the hardware notch, where a takeover (setup,
    /// a Party invite) puts its name in place of the tab bar. "Invitation au
    /// groupe" (123 pt) was cut there at the Regular size; 116 pt still fit.
    private static let takeoverTitleBudget: CGFloat = 116

    private static let takeoverTitles = [
        "Party invite",
        "Pick a kit",
        "Your tabs",
        "A few extras",
    ]

    func testTakeoverTitlesFitBesideTheNotch() throws {
        let font = Self.roundedFont(size: 13, weight: .semibold)
        var overflows: [String] = []
        for language in L10n.languages {
            let strings = try XCTUnwrap(L10n.strings(for: language), "\(language).lproj is missing")
            for key in Self.takeoverTitles {
                let text = strings.localizedString(forKey: key, value: key, table: nil)
                let width = (text as NSString).size(withAttributes: [.font: font]).width
                if width > Self.takeoverTitleBudget {
                    overflows.append("\(language): \"\(text)\" is \(Int(width.rounded())) pt")
                }
            }
        }
        XCTAssertTrue(overflows.isEmpty, "Too wide for the title beside the notch (\(Int(Self.takeoverTitleBudget)) pt):\n"
            + overflows.joined(separator: "\n"))
    }

    /// `Theme.Typography`'s face: SF Pro Rounded at the given size.
    private static func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: weight)
        guard let rounded = system.fontDescriptor.withDesign(.rounded) else { return system }
        return NSFont(descriptor: rounded, size: size) ?? system
    }
}
