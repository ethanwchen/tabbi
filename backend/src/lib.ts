// Shared constants, errors and validation helpers.
// Parts adapted from the anki-fly friends backend (MIT, same author): token/code generation,
// constant-time compare, ISO week keys and the strict body parser.
import catalog from "../shared/catalog.json";

/** An error that becomes a JSON reply `{ ok: false, error, message }` with the given HTTP status. */
export class HttpError extends Error {
  constructor(
    public status: number,
    public error: string,
    message: string,
    public headers: Record<string, string> = {},
  ) {
    super(message);
  }
}

export const SERVICE = "tabbi-friends";
export const CATALOG = catalog;
export const SPECIES = catalog.species as readonly string[];
export const STATUSES = catalog.statuses as readonly string[];
export const STUDY_METHODS = catalog.studyMethods as readonly string[];
export const COSTUMES = catalog.costumes as readonly string[];
export const ACCESSORIES = catalog.accessories as readonly string[];
export const BREEDS = catalog.breeds as Record<string, readonly string[]>;

export const MAX_NAME = catalog.limits.nameMaxLength;
export const MAX_PET_NAME = catalog.limits.petNameMaxLength;
export const MAX_COLORS = catalog.limits.maxColors;
export const MAX_ACCESSORIES = catalog.limits.maxAccessories;
export const MAX_FRIENDS = catalog.limits.maxFriends;
export const MAX_PARTY_MEMBERS = catalog.limits.maxPartyMembers;
export const PARTY_IDLE_EXPIRY_S = catalog.limits.partyIdleExpirySeconds;
/** Recommended heartbeat interval per status; statuses without one (offline) send no heartbeats. */
export const HEARTBEAT_SECONDS = catalog.heartbeatSeconds as Record<string, number | undefined>;

/** Requests per minute per token. */
export const RATE_LIMIT_PER_MIN = 60;
/** Registrations per minute per client IP (unauthenticated). */
export const REGISTER_PER_MIN = 10;
export const MAX_BODY_BYTES = 4096;

export const DEFAULT_NAME = "student";
export const DEFAULT_PET_NAME = "buddy";

const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no I, O, 0, 1: easy to read aloud
export const FRIEND_CODE_RE = /^[A-HJ-NP-Z2-9]{8}$/;
export const PARTY_CODE_RE = /^[A-HJ-NP-Z2-9]{6}$/;
export const TOKEN_RE = /^[0-9a-f]{64}$/;

export const nowS = (): number => Math.floor(Date.now() / 1000);

export function hex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

export async function sha256Hex(s: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return hex(new Uint8Array(digest));
}

/** 256-bit secret token, 64 hex chars. Only its SHA-256 is stored server side. */
export function newToken(): string {
  return hex(crypto.getRandomValues(new Uint8Array(32)));
}

/** Unbiased CSPRNG code from a 32-symbol alphabet (256 is a multiple of 32, so `b % 32` has no bias). */
export function newCode(length: number): string {
  const buf = crypto.getRandomValues(new Uint8Array(length));
  return Array.from(buf, (b) => CODE_ALPHABET[b % CODE_ALPHABET.length]).join("");
}

/** ISO-8601 week key (e.g. `2026-W40`) of a `YYYY-MM-DD` calendar day. Weeks start on Monday. */
export function isoWeekKeyOfDay(day: string): string {
  const [y, m, d] = day.split("-").map(Number);
  const t = new Date(Date.UTC(y, m - 1, d));
  const dayNum = t.getUTCDay() || 7; // Mon=1 .. Sun=7
  t.setUTCDate(t.getUTCDate() + 4 - dayNum); // the Thursday of this ISO week decides the year
  const yearStart = Date.UTC(t.getUTCFullYear(), 0, 1);
  const week = Math.ceil(((t.getTime() - yearStart) / 86400000 + 1) / 7);
  return `${t.getUTCFullYear()}-W${String(week).padStart(2, "0")}`;
}

export function utcDay(unixS: number): string {
  return new Date(unixS * 1000).toISOString().slice(0, 10);
}

/** The seven `YYYY-MM-DD` days (Monday to Sunday) of the ISO week that contains `day`. */
export function isoWeekDays(day: string): string[] {
  const start = Date.parse(day + "T00:00:00Z") / 1000;
  const weekday = new Date(start * 1000).getUTCDay() || 7; // Mon=1 .. Sun=7
  return Array.from({ length: 7 }, (_, i) => utcDay(start + (i + 1 - weekday) * 86_400));
}

/** Earliest and latest UTC offsets in use (UTC-12 to UTC+14), in seconds. */
const MIN_UTC_OFFSET_S = -12 * 3600;
const MAX_UTC_OFFSET_S = 14 * 3600;

/**
 * A client's local calendar day (`YYYY-MM-DD`). It must be a real date that is "today" somewhere on
 * Earth right now, which rejects bad clocks and backdating while allowing every time zone.
 */
export function parseDay(v: unknown, now: number): string {
  if (typeof v !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(v)) throw invalid("day");
  const start = Date.parse(v + "T00:00:00Z") / 1000;
  if (!Number.isFinite(start) || utcDay(start) !== v) throw invalid("day");
  if (start > now + MAX_UTC_OFFSET_S || start + 86_400 <= now + MIN_UTC_OFFSET_S) throw invalid("day");
  return v;
}

// ---------- validation ----------

export type Obj = Record<string, unknown>;

const invalid = (field: string) => new HttpError(400, "invalid_field", `invalid ${field}`);

/** Parses a JSON object body and rejects any key outside `allowed`. An empty body is `{}`. */
export function parseBodyObject(raw: string, allowed: readonly string[], maxBytes = MAX_BODY_BYTES): Obj {
  if (new TextEncoder().encode(raw).byteLength > maxBytes) throw new HttpError(413, "body_too_large", "body too large");
  let body: unknown;
  try {
    body = raw.trim() === "" ? {} : JSON.parse(raw);
  } catch {
    throw new HttpError(400, "invalid_json", "invalid JSON");
  }
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    throw new HttpError(400, "invalid_json", "body must be a JSON object");
  }
  for (const k of Object.keys(body)) {
    if (!allowed.includes(k)) throw new HttpError(400, "unknown_field", `unknown field: ${k}`);
  }
  return body as Obj;
}

export async function readBody(req: Request, allowed: readonly string[], maxBytes = MAX_BODY_BYTES): Promise<Obj> {
  const len = req.headers.get("content-length");
  if (len && Number(len) > maxBytes) throw new HttpError(413, "body_too_large", "body too large");
  return parseBodyObject(await req.text(), allowed, maxBytes);
}

/** Strips control and invisible characters, trims, caps the length. Empty becomes `undefined`. */
export function cleanText(v: unknown, field: string, max: number): string | undefined {
  if (v === undefined || v === null) return undefined;
  if (typeof v !== "string") throw invalid(field);
  // eslint-disable-next-line no-control-regex
  const s = v.replace(/[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2028\u2029\u2066-\u2069\ufeff]/g, "").trim();
  if ([...s].length > max) throw new HttpError(400, "invalid_field", `${field} must be at most ${max} characters`);
  return s === "" ? undefined : s;
}

export function oneOf(v: unknown, list: readonly string[], field: string): string {
  if (typeof v !== "string" || !list.includes(v)) throw invalid(field);
  return v;
}

export function int(v: unknown, field: string, min: number, max: number): number {
  if (typeof v !== "number" || !Number.isInteger(v) || v < min || v > max) throw invalid(field);
  return v;
}

/** Up to `MAX_COLORS` `#RRGGBB` strings, normalized to upper case. */
export function parseColors(v: unknown): string[] {
  if (!Array.isArray(v) || v.length > MAX_COLORS) throw invalid("colors");
  return v.map((c) => {
    if (typeof c !== "string" || !/^#[0-9a-fA-F]{6}$/.test(c)) throw invalid("colors");
    return c.toUpperCase();
  });
}

/** Up to `MAX_ACCESSORIES` distinct accessory ids from the catalog. */
export function parseAccessories(v: unknown): string[] {
  if (!Array.isArray(v) || v.length > MAX_ACCESSORIES) throw invalid("accessories");
  const out: string[] = [];
  for (const a of v) {
    const id = oneOf(a, ACCESSORIES, "accessories");
    if (out.includes(id)) throw invalid("accessories");
    out.push(id);
  }
  return out;
}

export function parseFriendCode(v: unknown): string {
  if (typeof v !== "string") throw invalid("code");
  const c = v.trim().toUpperCase();
  if (!FRIEND_CODE_RE.test(c)) throw invalid("code");
  return c;
}

export function parsePartyCode(v: unknown): string {
  if (typeof v !== "string") throw invalid("party code");
  const c = v.trim().toUpperCase();
  if (!PARTY_CODE_RE.test(c)) throw invalid("party code");
  return c;
}
