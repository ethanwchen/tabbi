/*
 * Port of Sentences: joins whole sentences into one paragraph the way each
 * language writes it, a space after a sentence in English or German, none
 * after the full-width stops Japanese and Chinese end theirs with ("。"),
 * which carry their own spacing. Empty sentences are skipped.
 */

const FULL_WIDTH_STOPS = new Set(["。", "！", "？", "：", "）"]);

/* Swift's trimmingCharacters(in: .whitespaces): spaces and tabs, not line breaks. */
const trimWhitespace = (text: string) => text.replace(/^[\p{Zs}\t]+|[\p{Zs}\t]+$/gu, "");

export function joinSentences(sentences: readonly string[]): string {
  let text = "";
  for (const sentence of sentences.map(trimWhitespace)) {
    if (sentence === "") continue;
    const last = text.at(-1);
    if (last !== undefined && !FULL_WIDTH_STOPS.has(last)) text += " ";
    text += sentence;
  }
  return text;
}
