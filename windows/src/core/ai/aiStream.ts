import type { AIProviderID } from "./aiProviderID";
import type { AIStreamEvent } from "./aiRequest";
import { eventsFromLine } from "./aiWireFormat";

/**
 * Splits a streamed body into lines as text chunks arrive, the way
 * Foundation's `bytes.lines` does: a line ends at "\n", "\r\n" or "\r", a
 * chunk may end mid-line (or between "\r" and "\n"), and the last line
 * needs no newline. Pure: feed `push` each chunk and `finish` at the end.
 */
export class LineSplitter {
  private pending = "";
  private sawCarriageReturn = false;

  /** The complete lines in the text so far, without their line endings. */
  push(chunk: string): string[] {
    const lines: string[] = [];
    for (const char of chunk) {
      if (char === "\n" && this.sawCarriageReturn) {
        this.sawCarriageReturn = false;
        continue;
      }
      this.sawCarriageReturn = false;
      if (char === "\n" || char === "\r") {
        lines.push(this.pending);
        this.pending = "";
        this.sawCarriageReturn = char === "\r";
      } else {
        this.pending += char;
      }
    }
    return lines;
  }

  /** The unfinished last line, if the body ended without a newline. */
  finish(): string[] {
    const rest = this.pending;
    this.pending = "";
    this.sawCarriageReturn = false;
    return rest.length > 0 ? [rest] : [];
  }
}

/** Every line in `chunks`, for tests and one-shot bodies. */
export function splitLines(chunks: Iterable<string>): string[] {
  const splitter = new LineSplitter();
  const lines: string[] = [];
  for (const chunk of chunks) lines.push(...splitter.push(chunk));
  return [...lines, ...splitter.finish()];
}

/**
 * The SSE (Anthropic, OpenAI, Gemini) or NDJSON (Ollama) parser over text
 * chunks: push each chunk, get the events its finished lines hold. Throws
 * `AIProviderFailure` for an error the provider reports mid-stream.
 */
export class AIStreamParser {
  private readonly lines = new LineSplitter();

  constructor(readonly provider: AIProviderID) {}

  push(chunk: string): AIStreamEvent[] {
    return this.lines.push(chunk).flatMap((line) => eventsFromLine(line, this.provider));
  }

  finish(): AIStreamEvent[] {
    return this.lines.finish().flatMap((line) => eventsFromLine(line, this.provider));
  }
}

/** Every event in a whole streamed body, given as chunks. */
export function parseStream(provider: AIProviderID, chunks: Iterable<string>): AIStreamEvent[] {
  const parser = new AIStreamParser(provider);
  const events: AIStreamEvent[] = [];
  for (const chunk of chunks) events.push(...parser.push(chunk));
  return [...events, ...parser.finish()];
}
