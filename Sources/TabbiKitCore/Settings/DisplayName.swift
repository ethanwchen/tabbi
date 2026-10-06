import Foundation

/// The user's name as Tabbi shows it: to friends in Party and in a
/// greeting. One rule for every place that uses it, so the name friends see
/// is the name the app greets you with.
public enum DisplayName {
    /// The friends server's name limit, which every use follows.
    public static let maxLength = 24

    /// `text` trimmed, with control and invisible characters removed and at
    /// most `maxLength` characters. Nil when nothing is left.
    public static func cleaned(_ text: String) -> String? {
        let kept = text.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar) && !invisibleScalars.contains(scalar.value)
        }
        let trimmed = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Zero-width and direction marks a name could hide behind.
    private static let invisibleScalars: Set<UInt32> = [
        0x00AD, 0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0x2060, 0xFEFF,
        0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069,
    ]
}
