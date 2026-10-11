import Foundation

/// Joins whole sentences into one paragraph the way each language writes
/// it: a space after a sentence in English or German, none after the full
/// width stops Japanese and Chinese end theirs with ("。"), which already
/// carry their own spacing. Empty sentences are skipped.
public enum Sentences {
    public static func join(_ sentences: [String]) -> String {
        sentences.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .reduce(into: "") { text, sentence in
                if let last = text.last, !fullWidthStops.contains(last) { text += " " }
                text += sentence
            }
    }

    private static let fullWidthStops: Set<Character> = ["。", "！", "？", "：", "）"]
}
