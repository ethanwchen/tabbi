import Foundation

/// Turns a Claude answer into styled text for the notch panel. `blocks(_:)`
/// splits out fenced code, which gets its own box, and `attributed(_:)`
/// styles the prose between.
///
/// SwiftUI's `Text` only renders inline markdown, and full markdown parsing
/// collapses line breaks, so block syntax is simplified line by line first
/// (bullets become "•", headings become bold, code fences disappear) and the
/// rest is parsed as inline markdown with whitespace preserved.
public enum ClaudeAskMarkdown {
    /// A run of an answer: prose, which renders through `attributed(_:)`,
    /// or a fenced code block, which the panel draws in its own box with a
    /// copy button.
    public enum Block: Equatable, Sendable {
        case text(String)
        /// `language` is the fence's info word ("swift"), if any. `isClosed`
        /// is false while the closing fence hasn't streamed in yet.
        case code(language: String?, code: String, isClosed: Bool)
    }

    /// Splits `markdown` into prose and fenced code blocks, in order.
    ///
    /// Blank lines around a code block are dropped, since the block's own
    /// spacing separates it. An unclosed fence (an answer still streaming)
    /// runs to the end, so the code appears as it arrives. A fence's
    /// indentation is removed from its lines, as in a list item's code.
    public static func blocks(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var prose: [Substring] = []
        var code: [Substring]?
        var language: String?
        var fenceIndent = 0

        func flushProse() {
            let text = prose.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !text.isEmpty { blocks.append(.text(text)) }
            prose = []
        }

        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let indent = line.prefix(while: { $0 == " " }).count
            let trimmed = line.dropFirst(indent)
            if trimmed.hasPrefix("```") {
                if let lines = code {
                    blocks.append(.code(language: language, code: lines.joined(separator: "\n"), isClosed: true))
                    code = nil
                } else {
                    flushProse()
                    let info = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    language = info.split(separator: " ").first.map(String.init)
                    fenceIndent = indent
                    code = []
                }
            } else if code != nil {
                code?.append(line.dropFirst(min(indent, fenceIndent)))
            } else {
                prose.append(line)
            }
        }
        if let lines = code {
            blocks.append(.code(language: language, code: lines.joined(separator: "\n"), isClosed: false))
        }
        flushProse()
        return blocks
    }

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
