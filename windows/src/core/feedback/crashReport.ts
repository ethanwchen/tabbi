import { DiagnosticEnvironment } from "./diagnosticEnvironment";
import { SYSTEM_VERSION_FIELD } from "./systemVersionField";

/*
 * Port of CrashReport: a crash report as Tabbi would send it to
 * `POST /v1/crashes`, after the person agreed: the app version, system
 * version and edition, what kind of crash it was, its signal or exception
 * type, and the threads' names and stack frames. Never an exception's
 * reason, a file path inside a home folder, or anything else that could
 * name the person or quote what they typed. Construction cleans every value
 * to what the backend accepts (printable ASCII, its length caps, home
 * folders as `~`), so the disclosure shown in the prompt is exactly the
 * report that is sent.
 */

export const CRASH_KINDS = ["signal", "exception", "hang"] as const;
export type CrashKind = (typeof CRASH_KINDS)[number];

/** The request body's top-level keys, in the backend's order; the system version's name comes from `SYSTEM_VERSION_FIELD`. */
export const CRASH_BODY_FIELDS = ["version", SYSTEM_VERSION_FIELD, "edition", "kind", "name", "threads"] as const;
/** Each thread's keys. */
export const CRASH_THREAD_BODY_FIELDS = ["name", "crashed", "frames"] as const;

/* The backend's limits (backend/src/crashes.ts). */
export const CRASH_MAX_THREADS = 64;
export const CRASH_MAX_FRAMES = 128;
export const CRASH_MAX_FRAME_LENGTH = 512;
export const CRASH_MAX_THREAD_NAME_LENGTH = 64;
export const CRASH_MAX_NAME_LENGTH = 64;
/** The backend takes bodies up to 64 KB; a report is trimmed to fit under this. */
export const CRASH_MAX_ENCODED_BYTES = 60 * 1024;

/** Printable ASCII only (anything else becomes `?`), capped at `limit` characters. */
export function printableASCII(value: string, limit: number): string {
  return Array.from(value)
    .slice(0, limit)
    .map((char) => {
      const code = char.codePointAt(0) ?? 0;
      return code >= 0x20 && code <= 0x7e ? char : "?";
    })
    .join("");
}

/** Letters, digits, `_` and `.`, capped; "unknown" when nothing is left. */
export function cleanCrashName(value: string): string {
  const kept = Array.from(value)
    .filter((char) => /[A-Za-z0-9_.]/.test(char))
    .slice(0, CRASH_MAX_NAME_LENGTH)
    .join("");
  return kept === "" ? "unknown" : kept;
}

/*
 * A home folder: the Mac's `/Users/<name>` and `/home/<name>` (also under
 * `/Volumes/<disk>`), and Windows' `\Users\<name>` with either slash, after
 * any drive letter, a `\\?\` or `\\.\` prefix, or a UNC `\\server\share`,
 * any case. A name runs to the next slash when one follows (Windows names
 * can hold spaces), otherwise to the next space.
 */
const HOME_FOLDER =
  /(?:\/Volumes\/[^/]*|(?:\\\\[?.][\\/])?[A-Za-z]:|\\\\[^\\/\s]+[\\/][^\\/\s]+)?[\\/](?:Users|home|Documents and Settings)[\\/](?:[^\\/\r\n]*(?=[\\/])|[^\\/\s]*)/gi;

/** Replaces every home folder (and the person's name in it) with `~`. */
export function withoutHomeFolders(text: string): string {
  return text.replace(HOME_FOLDER, "~");
}

/**
 * A frame with home folders as `~`, runs of whitespace squeezed to one
 * space, other characters made printable ASCII, and capped; undefined when
 * nothing is left.
 */
export function cleanCrashFrame(frame: string): string | undefined {
  const text = withoutHomeFolders(frame.replace(/\s+/g, " ")).replace(/^[ \t]+|[ \t]+$/g, "");
  const cleaned = printableASCII(text, CRASH_MAX_FRAME_LENGTH);
  return cleaned === "" ? undefined : cleaned;
}

/** Port of CrashReport.Thread: one thread, cleaned on construction. */
export class CrashThread {
  /** The thread's name, or empty for an unnamed thread. */
  readonly name: string;
  readonly crashed: boolean;
  /** One line per frame, innermost first. */
  readonly frames: readonly string[];

  constructor(name: string, crashed: boolean, frames: readonly string[]) {
    this.name = printableASCII(name, CRASH_MAX_THREAD_NAME_LENGTH);
    this.crashed = crashed;
    this.frames = frames.slice(0, CRASH_MAX_FRAMES).flatMap((frame) => cleanCrashFrame(frame) ?? []);
  }

  equals(other: CrashThread): boolean {
    return (
      this.name === other.name &&
      this.crashed === other.crashed &&
      this.frames.length === other.frames.length &&
      this.frames.every((frame, index) => frame === other.frames[index])
    );
  }
}

type BodyValue = string | boolean | readonly BodyValue[] | { readonly [key: string]: BodyValue };

/* Keys sorted, slashes unescaped (JSON.stringify never escapes them), like the Mac's encoder. */
function compact(value: BodyValue): string {
  if (typeof value === "string" || typeof value === "boolean") return JSON.stringify(value);
  if (isList(value)) return `[${value.map(compact).join(",")}]`;
  const keys = Object.keys(value).sort();
  return `{${keys.map((key) => `${JSON.stringify(key)}:${compact(value[key] ?? "")}`).join(",")}}`;
}

/* Foundation's pretty printing: two-space indent and `"key" : value`. */
function pretty(value: BodyValue, indent: string): string {
  if (typeof value === "string" || typeof value === "boolean") return JSON.stringify(value);
  const inner = `${indent}  `;
  if (isList(value)) {
    if (value.length === 0) return "[]";
    return `[\n${value.map((item) => inner + pretty(item, inner)).join(",\n")}\n${indent}]`;
  }
  const keys = Object.keys(value).sort();
  if (keys.length === 0) return "{}";
  return `{\n${keys.map((key) => `${inner}${JSON.stringify(key)} : ${pretty(value[key] ?? "", inner)}`).join(",\n")}\n${indent}}`;
}

function isList(value: BodyValue): value is readonly BodyValue[] {
  return Array.isArray(value);
}

const utf8Length = (text: string) => new TextEncoder().encode(text).length;

export class CrashReport {
  private constructor(
    readonly environment: DiagnosticEnvironment,
    readonly kind: CrashKind,
    /** "SIGSEGV" or "EXCEPTION_ACCESS_VIOLATION"; "unknown" when nothing usable is left. */
    readonly name: string,
    readonly threads: readonly CrashThread[],
  ) {}

  /**
   * Cleans every value, keeps at most one crashed thread, and drops threads
   * (the last uncrashed ones first) and then frames until the encoded report
   * fits `CRASH_MAX_ENCODED_BYTES`. Undefined when no frame is left, since
   * the backend refuses a report without a stack.
   */
  static make(environment: DiagnosticEnvironment, kind: CrashKind, name: string, threads: readonly CrashThread[]): CrashReport | undefined {
    let sawCrashed = false;
    const kept = threads.slice(0, CRASH_MAX_THREADS).map((thread) => {
      const crashed = thread.crashed && !sawCrashed;
      sawCrashed = sawCrashed || crashed;
      return crashed === thread.crashed ? thread : new CrashThread(thread.name, false, thread.frames);
    });
    const cleanName = cleanCrashName(name);
    const fits = (list: readonly CrashThread[]) =>
      utf8Length(new CrashReport(environment, kind, cleanName, list).jsonText()) <= CRASH_MAX_ENCODED_BYTES;
    while (!fits(kept)) {
      let lastUncrashed = -1;
      kept.forEach((thread, index) => {
        if (!thread.crashed) lastUncrashed = index;
      });
      if (lastUncrashed >= 0 && kept.length > 1) {
        kept.splice(lastUncrashed, 1);
        continue;
      }
      let longest = -1;
      kept.forEach((thread, index) => {
        if (longest < 0 || thread.frames.length > (kept[longest]?.frames.length ?? 0)) longest = index;
      });
      const thread = kept[longest];
      if (thread === undefined || thread.frames.length <= 1) break;
      kept[longest] = new CrashThread(thread.name, thread.crashed, thread.frames.slice(0, Math.floor(thread.frames.length / 2)));
    }
    if (!kept.some((thread) => thread.frames.length > 0)) return undefined;
    return new CrashReport(environment, kind, cleanName, kept);
  }

  /** The body as a value: exactly the fields in `CRASH_BODY_FIELDS`. */
  private body(): BodyValue {
    return {
      version: this.environment.appVersion,
      [SYSTEM_VERSION_FIELD]: this.environment.systemVersion,
      edition: this.environment.edition,
      kind: this.kind,
      name: this.name,
      threads: this.threads.map((thread) => ({ name: thread.name, crashed: thread.crashed, frames: [...thread.frames] })),
    };
  }

  /** The request body, compact with sorted keys. */
  jsonText(): string {
    return compact(this.body());
  }

  /** The body as the prompt's disclosure shows it, word for word. */
  get disclosure(): string {
    return pretty(this.body(), "");
  }

  /**
   * Reads a saved body (`jsonText` or the disclosure) and cleans it again,
   * so a saved report can never skip the rules. Undefined when it is not a
   * report or has no frame left.
   */
  static fromJSON(raw: unknown): CrashReport | undefined {
    if (typeof raw !== "object" || raw === null || Array.isArray(raw)) return undefined;
    const object = raw as Record<string, unknown>;
    const { version, edition, kind, name, threads } = object;
    const system = object[SYSTEM_VERSION_FIELD];
    if (typeof version !== "string" || typeof system !== "string" || typeof edition !== "string") return undefined;
    if (typeof kind !== "string" || !(CRASH_KINDS as readonly string[]).includes(kind) || typeof name !== "string") return undefined;
    if (!Array.isArray(threads)) return undefined;
    const parsed: CrashThread[] = [];
    for (const thread of threads as unknown[]) {
      if (typeof thread !== "object" || thread === null) return undefined;
      const fields = thread as Record<string, unknown>;
      const frames = fields.frames;
      if (typeof fields.name !== "string" || typeof fields.crashed !== "boolean" || !Array.isArray(frames)) return undefined;
      if (!frames.every((frame): frame is string => typeof frame === "string")) return undefined;
      parsed.push(new CrashThread(fields.name, fields.crashed, frames));
    }
    return CrashReport.make(new DiagnosticEnvironment(version, system, edition), kind as CrashKind, name, parsed);
  }

  equals(other: CrashReport): boolean {
    return (
      this.environment.equals(other.environment) &&
      this.kind === other.kind &&
      this.name === other.name &&
      this.threads.length === other.threads.length &&
      this.threads.every((thread, index) => {
        const theirs = other.threads[index];
        return theirs !== undefined && thread.equals(theirs);
      })
    );
  }
}
