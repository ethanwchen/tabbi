/**
 * Crash reports: `POST /v1/crashes` takes a report the app sends after the person agreed to it (the
 * next-launch prompt, or "Always send"). The maintainer reads them through `GET /v1/admin/crashes`.
 *
 * A report carries only the app version, macOS version, edition, what kind of crash it was, and the
 * crashed process's threads (their names and stack frames). The app strips anything personal before
 * sending (`CrashReport` in TabbiKitCore); this route checks the shape again and rejects anything else,
 * including any field it does not know and any frame that still names a home folder.
 *
 * Like suggestions, the route needs no account, so it is guarded by per-IP limits, a global daily cap
 * that bounds storage, a size limit, and strict validation.
 */
import { APP_FACT_PATTERN } from "./suggestions";
import { HttpError, Obj, oneOf, readBody } from "./lib";

export const CRASH_FIELDS = ["version", "macos", "edition", "kind", "name", "threads"] as const;
export const CRASH_THREAD_FIELDS = ["name", "crashed", "frames"] as const;
/** A signal (SIGSEGV), an uncaught Objective-C exception, or the main thread not answering. */
export const CRASH_KINDS = ["signal", "exception", "hang"] as const;

/** The signal or exception type, as in "SIGSEGV" or "NSInvalidArgumentException"; never an exception's reason, which can quote user content. */
export const CRASH_NAME_PATTERN = /^[A-Za-z0-9_.]{1,64}$/;
/** A thread name such as "com.apple.main-thread": printable ASCII, possibly empty. */
export const CRASH_THREAD_NAME_PATTERN = /^[\x20-\x7e]{0,64}$/;
/** One stack frame as the app formats it (image, address, symbol and offset): printable ASCII. */
export const CRASH_FRAME_PATTERN = /^[\x20-\x7e]{1,512}$/;
/** A home folder path, which names the person; the app replaces it with `~` before sending. */
const HOME_PATH = /\/Users\/|\/home\//;

export const MAX_CRASH_THREADS = 64;
export const MAX_CRASH_FRAMES = 128;
/** A real report is a few kilobytes; this bounds what one post can store. */
export const MAX_CRASH_BODY_BYTES = 64 * 1024;

/** Reports per minute and per UTC day from one client IP. The app sends at most one per launch. */
export const CRASHES_PER_MIN = 2;
export const CRASHES_PER_DAY = 10;
/** Reports stored per rolling 24 hours from everyone; past it, posts are refused until the window moves. */
export const MAX_CRASHES_PER_DAY = 1000;
/** Reports are deleted this long after they arrive, if the maintainer has not deleted them already. */
export const CRASH_RETENTION_DAYS = 90;
/** Reports one GET /v1/admin/crashes returns, newest first. */
export const ADMIN_CRASHES_PAGE = 50;

export interface CrashThread {
  name: string;
  crashed: boolean;
  frames: string[];
}

export interface CrashReport {
  appVersion: string;
  macos: string;
  edition: string;
  kind: string;
  name: string;
  threads: CrashThread[];
}

const invalid = (field: string, message = `invalid ${field}`) => new HttpError(400, "invalid_field", message);

/** Reads a JSON crash report body, rejecting unknown fields and anything over the size limit. */
export function readCrashBody(req: Request): Promise<Obj> {
  return readBody(req, CRASH_FIELDS, MAX_CRASH_BODY_BYTES);
}

function appFact(v: unknown, field: string): string {
  if (typeof v !== "string" || !APP_FACT_PATTERN.test(v)) throw invalid(field);
  return v;
}

function parseThread(v: unknown): CrashThread {
  if (typeof v !== "object" || v === null || Array.isArray(v)) throw invalid("threads");
  for (const k of Object.keys(v)) {
    if (!(CRASH_THREAD_FIELDS as readonly string[]).includes(k)) throw new HttpError(400, "unknown_field", `unknown field: threads.${k}`);
  }
  const t = v as Obj;
  if (typeof t.name !== "string" || !CRASH_THREAD_NAME_PATTERN.test(t.name)) throw invalid("threads.name");
  if (typeof t.crashed !== "boolean") throw invalid("threads.crashed");
  if (!Array.isArray(t.frames) || t.frames.length > MAX_CRASH_FRAMES) throw invalid("threads.frames");
  for (const f of t.frames) {
    if (typeof f !== "string" || !CRASH_FRAME_PATTERN.test(f)) throw invalid("threads.frames");
    if (HOME_PATH.test(f)) throw invalid("threads.frames", "frames must not contain home folder paths");
  }
  return { name: t.name, crashed: t.crashed, frames: t.frames as string[] };
}

/** Validates a crash report: every field required, at most one crashed thread, and at least one frame somewhere. */
export function parseCrash(body: Obj): CrashReport {
  for (const field of CRASH_FIELDS) if (body[field] === undefined) throw invalid(field, `${field} is required`);
  if (typeof body.name !== "string" || !CRASH_NAME_PATTERN.test(body.name)) throw invalid("name");
  if (!Array.isArray(body.threads) || body.threads.length === 0 || body.threads.length > MAX_CRASH_THREADS) throw invalid("threads");
  const threads = body.threads.map(parseThread);
  if (threads.filter((t) => t.crashed).length > 1) throw invalid("threads", "at most one thread crashed");
  if (threads.every((t) => t.frames.length === 0)) throw invalid("threads", "a report needs at least one frame");
  return {
    appVersion: appFact(body.version, "version"),
    macos: appFact(body.macos, "macos"),
    edition: appFact(body.edition, "edition"),
    kind: oneOf(body.kind, CRASH_KINDS, "kind"),
    name: body.name,
    threads,
  };
}
