/*
 * Port of the inline half of ClaudeAskMarkdown.attributed: the prose between
 * code blocks, after `simplifyBlocks`, parsed as inline Markdown only (what
 * SwiftUI's `Text` renders with `inlineOnlyPreservingWhitespace`): bold,
 * italic, inline code and links, with every line break and space kept. The
 * panel turns the runs into styled spans; nothing here knows about React.
 */

/** One styled run of prose. A link keeps its text; the panel shows no URL. */
export interface InlineRun {
  readonly text: string;
  readonly bold: boolean;
  readonly italic: boolean;
  readonly code: boolean;
}

interface Style {
  bold: boolean;
  italic: boolean;
}

/** The runs of `prose`, adjacent runs of one style merged. */
export function inlineRuns(prose: string): InlineRun[] {
  const runs: InlineRun[] = [];
  const push = (text: string, style: Style, code = false) => {
    if (text.length === 0) return;
    const last = runs[runs.length - 1];
    if (last && last.bold === style.bold && last.italic === style.italic && last.code === code) {
      runs[runs.length - 1] = { ...last, text: last.text + text };
    } else {
      runs.push({ text, bold: style.bold, italic: style.italic, code });
    }
  };
  parse(prose, { bold: false, italic: false }, push);
  return runs;
}

type Push = (text: string, style: Style, code?: boolean) => void;

/** Whether the delimiter at `index` opens a span: not followed by a space (CommonMark's left-flanking rule, simplified). */
function opens(text: string, index: number, length: number): boolean {
  const next = text[index + length];
  return next !== undefined && !/\s/.test(next);
}

/**
 * The index of the closing delimiter `marker` after `from`: a run of exactly
 * the marker's length (so `**` inside `*...*` is a nested span, not the
 * end) with a non-space before it, or -1.
 */
function closing(text: string, marker: string, from: number): number {
  const char = marker[0];
  let index = text.indexOf(marker, from);
  while (index !== -1) {
    const before = text[index - 1];
    const after = text[index + marker.length];
    const exact = before !== char && after !== char;
    if (exact && before !== undefined && !/\s/.test(before)) return index;
    index = text.indexOf(marker, index + 1);
  }
  return -1;
}

function parse(text: string, style: Style, push: Push): void {
  let plain = "";
  let index = 0;
  const flush = () => {
    push(plain, style);
    plain = "";
  };
  while (index < text.length) {
    const char = text[index] ?? "";
    /* An escaped punctuation mark is itself. */
    if (char === "\\" && index + 1 < text.length && /[\\`*_[\]()]/.test(text[index + 1] ?? "")) {
      plain += text[index + 1];
      index += 2;
      continue;
    }
    if (char === "`") {
      /* A code span runs to the next matching run of backticks; an unmatched backtick is plain. */
      let ticks = 1;
      while (text[index + ticks] === "`") ticks += 1;
      const fence = "`".repeat(ticks);
      const end = text.indexOf(fence, index + ticks);
      if (end !== -1) {
        flush();
        const code = text.slice(index + ticks, end);
        push(code.startsWith(" ") && code.endsWith(" ") && code.trim().length > 0 ? code.slice(1, -1) : code, style, true);
        index = end + ticks;
        continue;
      }
      plain += fence;
      index += ticks;
      continue;
    }
    if (char === "*" || char === "_") {
      const double = text[index + 1] === char;
      const marker = double ? char + char : char;
      /* A single underscore inside a word (snake_case) is text, as CommonMark reads it. */
      const inWord = char === "_" && index > 0 && /\w/.test(text[index - 1] ?? "");
      if (!inWord && opens(text, index, marker.length)) {
        const end = closing(text, marker, index + marker.length);
        if (end !== -1) {
          flush();
          const inner = text.slice(index + marker.length, end);
          parse(inner, double ? { ...style, bold: true } : { ...style, italic: true }, push);
          index = end + marker.length;
          continue;
        }
      }
      plain += marker;
      index += marker.length;
      continue;
    }
    if (char === "[") {
      /* `[text](url)` shows its text; the URL is dropped, as the panel has nowhere to open it. */
      const close = text.indexOf("](", index);
      const end = close === -1 ? -1 : text.indexOf(")", close + 2);
      if (close !== -1 && end !== -1 && !text.slice(index + 1, close).includes("\n")) {
        flush();
        parse(text.slice(index + 1, close), style, push);
        index = end + 1;
        continue;
      }
    }
    plain += char;
    index += 1;
  }
  flush();
}
