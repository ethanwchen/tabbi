import Foundation

/// Turns a Claude answer into styled text for the small notch panel.
///
/// SwiftUI's `Text` only renders inline markdown, and full markdown parsing
/// collapses line breaks, so block syntax is simplified line by line first
/// (bullets become "•", headings become bold, code fences disappear) and the
/// rest is parsed as inline markdown with whitespace preserved.
public enum ClaudeAskMarkdown {
    public static func attributed(_ markdown: String) -> AttributedString {
        let simplified = simplifyBlocks(markdown)
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: simplified, options: options)) ?? AttributedString(simplified)
    }

    /// Rewrites block-level markdown into inline-only markdown.
    public static func simplifyBlocks(_ markdown: String) -> String {
        var inCodeBlock = false
        var lines: [String] = []
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCodeBlock.toggle()
                continue
            }
            if inCodeBlock {
                // Inline code keeps the monospaced look without block syntax.
                lines.append(trimmed.isEmpty ? "" : "`\(line.replacingOccurrences(of: "`", with: "'"))`")
                continue
            }
            let indent = line.prefix(while: { $0 == " " })
            if let bullet = ["- ", "* ", "+ "].first(where: { trimmed.hasPrefix($0) }) {
                lines.append(indent + "• " + trimmed.dropFirst(bullet.count))
            } else if let heading = headingText(trimmed) {
                lines.append("**\(heading)**")
            } else {
                lines.append(String(line))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func headingText(_ line: String) -> String? {
        let hashes = line.prefix(while: { $0 == "#" })
        guard (1...6).contains(hashes.count), line.dropFirst(hashes.count).first == " " else { return nil }
        return line.dropFirst(hashes.count + 1).trimmingCharacters(in: .whitespaces)
    }
}
