// Study Crews: the pure parts (catalog, the UTC week, request validation and how a session's minutes
// are split over crews and days). The SQL lives in crewService.ts. See docs/design/crews.md.
import crewsCatalog from "../shared/crews.json";
import { HttpError, Obj, cleanText, isoWeekKeyOfDay, oneOf, utcDay } from "./lib";
import { isNameAllowed } from "./names";

export const CREWS_CATALOG = crewsCatalog;
/**
 * A crew's crest is a frame, an emblem and a color. The ids are in picker order and only ever added once
 * shipped; an app draws an id it does not know as the first one, which is also the default.
 */
export const CREW_FRAMES = crewsCatalog.frames as readonly string[];
export const CREW_EMBLEMS = crewsCatalog.emblems as readonly string[];
export const CREW_COLORS = Object.keys(crewsCatalog.colors) as readonly string[];
export const CREW_VISIBILITIES = crewsCatalog.visibilities as readonly string[];
export const CREW_LAURELS = crewsCatalog.laurels as readonly string[];

const LIMITS = crewsCatalog.limits;
export const MAX_CREW_NAME = LIMITS.nameMaxLength;
export const MAX_CREW_DESCRIPTION = LIMITS.descriptionMaxLength;
export const MAX_CREW_MEMBERS = LIMITS.maxMembers;
export const CREW_SEARCH_PAGE = LIMITS.searchPageSize;
export const MAX_SESSIONS_PER_REPORT = LIMITS.maxSessionsPerReport;
export const MAX_SESSION_MINUTES = LIMITS.maxSessionMinutes;
export const DAILY_CAP_MINUTES = LIMITS.dailyCapMinutes;
export const WEEKLY_CAP_MINUTES = LIMITS.weeklyCapMinutes;

/** Crew ids, invite codes and member refs use the friend code alphabet. */
export const CREW_ID_LENGTH = 10;
export const INVITE_CODE_LENGTH = 7;
export const MEMBER_REF_LENGTH = 10;
export const CREW_ID_RE = /^[A-HJ-NP-Z2-9]{10}$/;
export const INVITE_CODE_RE = /^[A-HJ-NP-Z2-9]{7}$/;
export const MEMBER_REF_RE = CREW_ID_RE;

/** How far ahead of the server's clock a session may end (client clock skew). */
export const FUTURE_SLACK_S = 120;
/** Reported sessions and closed stints are kept this long: long enough for overlap checks in an open week. */
export const CREW_SESSION_RETENTION_S = 14 * 86_400;
/** Credited minutes and crew week totals are kept this long, so this week and last week are always there. */
export const CREW_WEEK_RETENTION_S = 35 * 86_400;

/** A join request to a public crew waits this long for the owner, then expires. */
export const JOIN_REQUEST_TTL_S = 7 * 86_400;
/** Pending join requests one crew can hold; more wait until the owner answers some. */
export const MAX_CREW_JOIN_REQUESTS = 50;
/** New join requests one user can send per UTC day. */
export const JOIN_REQUESTS_PER_DAY = 20;

/** Rate limits, per user, on top of the general per-token limit. */
export const CREW_SESSION_REPORTS_PER_MIN = 6;
export const CREW_SEARCHES_PER_MIN = 20;
export const CREW_CHANGES_PER_MIN = 10;
export const CREW_CREATES_PER_DAY = 3;

/** Flags for the maintainer: how many bad reports in one UTC day make a flag. */
export const OVERLAP_FLAG_PER_DAY = 5;
export const FUTURE_FLAG_PER_DAY = 3;
export const FLAG_KINDS = ["daily_cap", "weekly_cap", "overlaps", "future"] as const;
export type FlagKind = (typeof FLAG_KINDS)[number];

/** Why a crew or one of its members is reported. `cheating` exists only for crews. */
export const CREW_REPORT_REASONS = ["inappropriate_name", "harassment", "spam", "cheating", "other"] as const;
export const CREW_REPORT_FIELDS = ["crew", "member", "reason", "note"] as const;
export const CREW_BLOCK_FIELDS = ["crew", "member"] as const;
export const CREATE_FIELDS = ["name", "description", "frame", "emblem", "color", "visibility"] as const;
export const UPDATE_FIELDS = CREATE_FIELDS;
export const MEMBER_SETTINGS_FIELDS = ["showPet"] as const;
export const CREW_JOIN_FIELDS = ["code", "crew"] as const;
export const SESSIONS_FIELDS = ["sessions"] as const;
const SESSION_FIELDS = ["start", "end", "minutes"];

/** Every status a reported session can get back. */
export type SessionStatus = "credited" | "capped" | "duplicate" | "overlap" | "future" | "invalid" | "week_closed" | "no_crew";

// ---------- the week ----------

export const WEEK_S = 7 * 86_400;

export interface CrewWeek {
  id: string;
  startsAt: number;
  endsAt: number;
}

/** Monday 00:00 UTC of the week containing `t`. */
export function weekStart(t: number): number {
  const day = Math.floor(t / 86_400);
  const weekday = (new Date(day * 86_400_000).getUTCDay() + 6) % 7; // Mon=0 .. Sun=6
  return (day - weekday) * 86_400;
}

/** The crew week containing `t`: Monday 00:00 UTC up to (not including) the next Monday. */
export function weekOf(t: number): CrewWeek {
  const startsAt = weekStart(t);
  return { id: isoWeekKeyOfDay(utcDay(startsAt)), startsAt, endsAt: startsAt + WEEK_S };
}

/** The week before the one containing `t`. */
export function previousWeek(t: number): CrewWeek {
  return weekOf(weekStart(t) - 86_400);
}

// ---------- validation ----------

const invalid = (field: string) => new HttpError(400, "invalid_field", `invalid ${field}`);

/** A name key: case and width folded, so `Night Owls` and `night owls` are the same crew name. */
export function nameKey(name: string): string {
  return name.normalize("NFKC").toLocaleLowerCase("en-US");
}

export interface CrewFields {
  name?: string;
  description?: string;
  frame?: string;
  emblem?: string;
  color?: string;
  visibility?: string;
}

/**
 * The crew fields present in `body`, checked. `requireAll` (create) needs name, frame, emblem, color and
 * visibility; an edit sends any of them. A description sent empty or null clears it.
 */
export function parseCrewFields(body: Obj, requireAll: boolean): CrewFields {
  const out: CrewFields = {};
  if (body.name !== undefined || requireAll) {
    const name = cleanText(body.name, "name", MAX_CREW_NAME);
    if (name === undefined) throw new HttpError(400, "invalid_field", "name is required");
    if (!isNameAllowed(name)) throw new HttpError(400, "crew_name_not_allowed", "That crew name isn't allowed. Please pick another.");
    out.name = name;
  }
  if ("description" in body) {
    const description = cleanText(body.description, "description", MAX_CREW_DESCRIPTION) ?? "";
    if (description !== "" && !isNameAllowed(description)) {
      throw new HttpError(400, "description_not_allowed", "That description isn't allowed. Please change it.");
    }
    out.description = description;
  }
  if (body.frame !== undefined || requireAll) out.frame = oneOf(body.frame, CREW_FRAMES, "frame");
  if (body.emblem !== undefined || requireAll) out.emblem = oneOf(body.emblem, CREW_EMBLEMS, "emblem");
  if (body.color !== undefined || requireAll) out.color = oneOf(body.color, CREW_COLORS, "color");
  if (body.visibility !== undefined || requireAll) out.visibility = oneOf(body.visibility, CREW_VISIBILITIES, "visibility");
  return out;
}

export type CrewJoinTarget = { code: string } | { crew: string };

/** Exactly one of an invite `code` or a public crew's id `crew`, normalized. */
export function parseCrewJoin(body: Obj): CrewJoinTarget {
  if ((body.code === undefined) === (body.crew === undefined)) {
    throw new HttpError(400, "invalid_field", "send exactly one of code or crew");
  }
  if (body.code !== undefined) return { code: parseCode(body.code, INVITE_CODE_RE, "code") };
  return { crew: parseCode(body.crew, CREW_ID_RE, "crew") };
}

/** A code from the friend code alphabet: upper-cased, with spaces and dashes dropped. */
export function parseCode(v: unknown, re: RegExp, field: string): string {
  if (typeof v !== "string") throw invalid(field);
  const code = v.toUpperCase().replace(/[\s-]/g, "");
  if (!re.test(code)) throw invalid(field);
  return code;
}

export function parseShowPet(body: Obj): boolean {
  if (typeof body.showPet !== "boolean") throw invalid("showPet");
  return body.showPet;
}

export interface SessionInput {
  start: number;
  end: number;
  minutes: number;
}

/** The sessions list: 1 to MAX_SESSIONS_PER_REPORT entries. Each entry is checked on its own (`checkSession`). */
export function parseSessionList(body: Obj): unknown[] {
  const list = body.sessions;
  if (!Array.isArray(list) || list.length === 0 || list.length > MAX_SESSIONS_PER_REPORT) throw invalid("sessions");
  return list;
}

/**
 * One reported session, or the status that refuses it before storage is consulted: `invalid` for a
 * malformed or impossible one, `future` for one that ends ahead of the server's clock.
 */
export function checkSession(v: unknown, now: number): SessionInput | "invalid" | "future" {
  if (typeof v !== "object" || v === null || Array.isArray(v)) return "invalid";
  const o = v as Obj;
  if (Object.keys(o).some((k) => !SESSION_FIELDS.includes(k))) return "invalid";
  const { start, end, minutes } = o;
  if (![start, end, minutes].every((n) => typeof n === "number" && Number.isSafeInteger(n))) return "invalid";
  const s = start as number, e = end as number, m = minutes as number;
  if (s <= 0 || e <= s || e - s > MAX_SESSION_MINUTES * 60) return "invalid";
  if (m < 1 || m > Math.ceil((e - s) / 60)) return "invalid";
  if (e > now + FUTURE_SLACK_S) return "future";
  return { start: s, end: e, minutes: m };
}

// ---------- splitting a session's minutes ----------

export interface Stint {
  crew: string;
  joinedAt: number;
  leftAt: number | null;
}

/** A piece of a session: the seconds of it spent in `crew` on UTC `day`. */
export interface Segment {
  crew: string;
  day: string;
  seconds: number;
}

/**
 * The parts of [start, end) at or after `from` (the open week's start) that the user spent in a crew,
 * split at UTC midnights. Stints never overlap (one crew at a time), so no second counts twice.
 */
export function sessionSegments(start: number, end: number, stints: Stint[], from: number): Segment[] {
  const out: Segment[] = [];
  for (const stint of stints) {
    let a = Math.max(start, from, stint.joinedAt);
    const b = Math.min(end, stint.leftAt ?? Number.POSITIVE_INFINITY);
    while (a < b) {
      const midnight = (Math.floor(a / 86_400) + 1) * 86_400;
      const to = Math.min(b, midnight);
      out.push({ crew: stint.crew, day: utcDay(a), seconds: to - a });
      a = to;
    }
  }
  return out;
}

/**
 * Spreads `minutes` evenly over a session of `totalSeconds` and gives each segment its share in whole
 * minutes (largest remainder), so the shares add up to the rounded share of the whole covered time.
 */
export function allocateMinutes(minutes: number, totalSeconds: number, segments: Segment[]): number[] {
  const exact = segments.map((s) => (minutes * s.seconds) / totalSeconds);
  const target = Math.min(minutes, Math.round(exact.reduce((a, b) => a + b, 0)));
  const shares = exact.map(Math.floor);
  let left = target - shares.reduce((a, b) => a + b, 0);
  const order = exact.map((x, i) => ({ i, frac: x - Math.floor(x) })).sort((p, q) => q.frac - p.frac || p.i - q.i);
  for (const { i } of order) {
    if (left <= 0) break;
    shares[i]++;
    left--;
  }
  return shares;
}

// ---------- the board ----------

/** How many places win a medal and a laurel each week. */
export const PLACES = 3;

const byId = (a: { id: string }, b: { id: string }) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);

/**
 * A week's places: standard competition ranking on minutes (equal minutes share a place and the next
 * place skips), so two crews tied first are both first and the next crew is third. Returns the crews
 * placed 1 to PLACES, most minutes first, then by id; a crew with no minutes never places.
 */
export function weekPlaces<T extends { id: string; minutes: number }>(crews: T[]): (T & { rank: number })[] {
  const sorted = crews.filter((c) => c.minutes > 0).sort((a, b) => b.minutes - a.minutes || byId(a, b));
  const out: (T & { rank: number })[] = [];
  sorted.forEach((c, i) => {
    const rank = i > 0 && c.minutes === sorted[i - 1].minutes ? out[i - 1].rank : i + 1;
    out.push({ ...c, rank });
  });
  return out.filter((c) => c.rank <= PLACES);
}

/** The crew week an ISO week key (`2026-W46`) names. */
export function weekFromId(id: string): CrewWeek {
  const m = /^(\d{4})-W(\d{2})$/.exec(id);
  if (!m) throw new Error(`not a week key: ${id}`);
  const jan4 = Date.UTC(Number(m[1]), 0, 4) / 1000;
  return weekOf(weekStart(jan4) + (Number(m[2]) - 1) * WEEK_S);
}

// ---------- the Hall of Fame ----------

/** Hall of Fame entries per page. */
export const HALL_PAGE = 20;

/** Where a crew stands in the Hall of Fame: its medals, and when it reached that tally. */
export interface HallKey {
  gold: number;
  silver: number;
  bronze: number;
  reachedAt: number;
  id: string;
}

/** An opaque cursor: base64url of a small JSON array. */
function encodeCursor(v: unknown[]): string {
  return btoa(JSON.stringify(v)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function decodeCursor(raw: string): unknown {
  if (!/^[A-Za-z0-9_-]{1,200}$/.test(raw)) throw new HttpError(400, "invalid_field", "invalid cursor");
  try {
    return JSON.parse(atob(raw.replace(/-/g, "+").replace(/_/g, "/")));
  } catch {
    throw new HttpError(400, "invalid_field", "invalid cursor");
  }
}

/** Weekly board rows (places 4 and down) per page. */
export const BOARD_PAGE = 20;

/** Where a crew stands on the weekly board: its minutes, then its id. */
export interface BoardKey {
  minutes: number;
  id: string;
}

export function encodeBoardCursor(k: BoardKey): string {
  return encodeCursor([k.minutes, k.id]);
}

/** Reads a cursor from `encodeBoardCursor`; anything else is `400 invalid_field`. */
export function decodeBoardCursor(raw: string): BoardKey {
  const v = decodeCursor(raw);
  if (!Array.isArray(v) || v.length !== 2 || !Number.isSafeInteger(v[0]) || v[0] < 0 || typeof v[1] !== "string" || !CREW_ID_RE.test(v[1])) {
    throw new HttpError(400, "invalid_field", "invalid cursor");
  }
  return { minutes: v[0], id: v[1] };
}

/** The opaque cursor after `k`: base64url of its sort key. */
export function encodeHallCursor(k: HallKey): string {
  return btoa(JSON.stringify([k.gold, k.silver, k.bronze, k.reachedAt, k.id])).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** Reads a cursor from `encodeHallCursor`; anything else is `400 invalid_field`. */
export function decodeHallCursor(raw: string): HallKey {
  const bad = () => new HttpError(400, "invalid_field", "invalid cursor");
  if (!/^[A-Za-z0-9_-]{1,200}$/.test(raw)) throw bad();
  let v: unknown;
  try {
    v = JSON.parse(atob(raw.replace(/-/g, "+").replace(/_/g, "/")));
  } catch {
    throw bad();
  }
  if (!Array.isArray(v) || v.length !== 5) throw bad();
  const [gold, silver, bronze, reachedAt, id] = v;
  if (![gold, silver, bronze, reachedAt].every((n) => Number.isSafeInteger(n) && (n as number) >= 0)) throw bad();
  if (typeof id !== "string" || !CREW_ID_RE.test(id)) throw bad();
  return { gold, silver, bronze, reachedAt, id };
}

/** The laurel a top 3 rank wins. */
export function laurelOfRank(rank: number): string | null {
  return CREW_LAURELS[rank - 1] ?? null;
}

/** The validated reason and note of a crew report. */
export function parseCrewReport(body: Obj): { reason: string; note: string | null } {
  return {
    reason: oneOf(body.reason, CREW_REPORT_REASONS, "reason"),
    note: cleanText(body.note, "note", 280) ?? null,
  };
}
