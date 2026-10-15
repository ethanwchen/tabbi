/*
 * Port of ClaudeAskMarkdown's pure parts: splitting an answer into prose and
 * fenced code blocks, and rewriting block-level Markdown into inline-only
 * Markdown (bullets become dots, headings bold, fences drop) so line breaks
 * survive when the panel renders the prose.
 */

/** A run of an answer: prose, or a fenced code block the panel draws in its own box with a copy button. */
export type ClaudeAskBlock =
  | { kind: "text"; text: string }
  /** `language` is the fence's info word ("swift"), if any; `isClosed` is false while the closing fence hasn't streamed in. */
  | { kind: "code"; language?: string; code: string; isClosed: boolean };

function leadingSpaces(line: string): number {
  let count = 0;
  while (line[count] === " ") count += 1;
  return count;
}

/** Drops leading and trailing newlines, as `trimmingCharacters(in: .newlines)` does. */
function trimNewlines(text: string): string {
  return text.replace(/^[\n\r\v\f\x85\p{Zl}\p{Zp}]+|[\n\r\v\f\x85\p{Zl}\p{Zp}]+$/gu, "");
}

/**
 * Splits `markdown` into prose and fenced code blocks, in order. Blank lines
 * around a code block are dropped, an unclosed fence (an answer still
 * streaming) runs to the end, and a fence's indentation is removed from its
 * lines, as in a list item's code.
 */
export function markdownBlocks(markdown: string): ClaudeAskBlock[] {
  const blocks: ClaudeAskBlock[] = [];
  let prose: string[] = [];
  let code: string[] | undefined;
  let language: string | undefined;
  let fenceIndent = 0;

  const flushProse = () => {
    const text = trimNewlines(prose.join("\n"));
    if (text.length > 0) blocks.push({ kind: "text", text });
    prose = [];
  };
  const codeBlock = (lines: string[], isClosed: boolean): ClaudeAskBlock =>
    language === undefined ? { kind: "code", code: lines.join("\n"), isClosed } : { kind: "code", language, code: lines.join("\n"), isClosed };

  for (const line of markdown.split("\n")) {
    const indent = leadingSpaces(line);
    const trimmed = line.slice(indent);
    if (trimmed.startsWith("```")) {
      if (code) {
        blocks.push(codeBlock(code, true));
        code = undefined;
      } else {
        flushProse();
        const info = trimmed.slice(3).replace(/^[\p{Zs}\t]+|[\p{Zs}\t]+$/gu, "");
        language = info.split(" ").find((word) => word.length > 0);
        fenceIndent = indent;
        code = [];
      }
    } else if (code) {
      code.push(line.slice(Math.min(indent, fenceIndent)));
    } else {
      prose.push(line);
    }
  }
  if (code) blocks.push(codeBlock(code, false));
  flushProse();
  return blocks;
}

function headingText(line: string): string | undefined {
  let hashes = 0;
  while (line[hashes] === "#") hashes += 1;
  if (hashes < 1 || hashes > 6 || line[hashes] !== " ") return undefined;
  return line.slice(hashes + 1).replace(/^[\p{Zs}\t]+|[\p{Zs}\t]+$/gu, "");
}

/** Rewrites block-level Markdown into inline-only Markdown, line by line. */
export function simplifyBlocks(markdown: string): string {
  let inCodeBlock = false;
  const lines: string[] = [];
  for (const line of markdown.split("\n")) {
    const trimmed = line.replace(/^[\p{Zs}\t]+|[\p{Zs}\t]+$/gu, "");
    if (trimmed.startsWith("```")) {
      inCodeBlock = !inCodeBlock;
      continue;
    }
    if (inCodeBlock) {
      /* Inline code keeps the monospaced look without block syntax. */
      lines.push(trimmed.length === 0 ? "" : "`" + line.replaceAll("`", "'") + "`");
      continue;
    }
    const indent = line.slice(0, leadingSpaces(line));
    const bullet = ["- ", "* ", "+ "].find((marker) => trimmed.startsWith(marker));
    const heading = headingText(trimmed);
    if (bullet) lines.push(indent + "• " + trimmed.slice(bullet.length));
    else if (heading !== undefined) lines.push(`**${heading}**`);
    else lines.push(line);
  }
  return lines.join("\n");
}
