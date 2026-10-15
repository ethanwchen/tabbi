import { base64, sortedJSON } from "../ai/aiWireFormat";
import { type ClaudeStreamEvent, parseClaudeStreamLine } from "./claudeStreamEvent";

/*
 * Port of ClaudeCLI's pure parts: the arguments Tabbi runs `claude -p` with,
 * the stream-json input line, where to look for the executable, and the
 * line-to-event mapping. Running the process is the host's job; it runs it
 * in a neutral temporary folder so no project CLAUDE.md or settings apply.
 */

/** The image type every screenshot is sent as. */
export const CLAUDE_IMAGE_MEDIA_TYPE = "image/png";

/**
 * The arguments for a prompt run. The prompt goes last, after `--`, so text
 * that starts with `-` or matches a subcommand is never read as CLI input.
 */
export function claudePromptArguments(prompt: string, extraArguments: readonly string[] = []): string[] {
  return ["-p", "--output-format", "stream-json", "--verbose", ...extraArguments, "--", prompt];
}

/**
 * The arguments for a run that reads one stream-json line from stdin (a
 * user message, which can carry images). The CLI answers and exits once
 * stdin closes.
 */
export function claudeInputArguments(extraArguments: readonly string[] = []): string[] {
  return ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", ...extraArguments];
}

/**
 * The question as one line of `--input-format stream-json` input: a user
 * message whose content is each image (base64 PNG) followed by the text,
 * keys sorted and ending in a newline, as the Mac writes it.
 */
export function claudeInputLine(prompt: string, images: readonly Uint8Array[] = []): string {
  const content = [
    ...images.map((image) => ({ type: "image", source: { type: "base64", media_type: CLAUDE_IMAGE_MEDIA_TYPE, data: base64(image) } })),
    { type: "text", text: prompt },
  ];
  return sortedJSON({ type: "user", message: { role: "user", content } }) + "\n";
}

/** Parses each line the CLI printed, in order. */
export function claudeEvents(lines: Iterable<string>): ClaudeStreamEvent[] {
  return Array.from(lines, parseClaudeStreamLine);
}

/**
 * Where to look for `claude.exe` on Windows, most specific first: the path
 * the user set, the native installer's `%USERPROFILE%\.local\bin`, then each
 * PATH folder. The host checks which exists; the core never reads the
 * environment, so the folders are passed in.
 */
export function claudeExecutableCandidates(options: { userPath?: string; home?: string; pathFolders?: readonly string[] }): string[] {
  const join = (folder: string, name: string) => `${folder.replace(/[\\/]+$/, "")}\\${name}`;
  const candidates: string[] = [];
  const userPath = options.userPath?.trim();
  if (userPath) candidates.push(userPath);
  if (options.home) candidates.push(join(join(join(options.home, ".local"), "bin"), "claude.exe"));
  for (const folder of options.pathFolders ?? []) {
    if (folder.trim().length === 0) continue;
    candidates.push(join(folder, "claude.exe"), join(folder, "claude.cmd"));
  }
  return [...new Set(candidates)];
}

/**
 * A command line tool that exited with a failure status, with what it
 * wrote to stderr. The host rejects a run with this shape.
 */
export class ProcessFailure extends Error {
  constructor(
    readonly status: number,
    readonly stderr: string,
  ) {
    super(`The process exited with status ${status}.`);
    this.name = "ProcessFailure";
  }
}
