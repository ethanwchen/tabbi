/**
 * Study Crews in the Hub: storage, routes, the anti-cheat credit path, the weekly rollup and the
 * maintainer's crew routes. The Hub owns SQLite and hands this class what it needs through `CrewsHost`,
 * so the Hub only wires routes and lifecycle hooks (account deletion, sign-in folds, bans, blocks).
 * The design and the wire contract are docs/design/crews.md and shared/schemas/crews.v1.schema.json.
 */
import { HttpError, cleanText, newCode, readBody, utcDay } from "./lib";
import { json } from "./http";
import {
  CREATE_FIELDS, CREW_BLOCK_FIELDS, CREW_CHANGES_PER_MIN, CREW_CREATES_PER_DAY, CREW_ID_LENGTH, CREW_ID_RE, CREW_JOIN_FIELDS,
  CREW_REPORT_FIELDS, CREW_SEARCHES_PER_MIN, CREW_SEARCH_PAGE, CREW_SESSION_REPORTS_PER_MIN, CREW_SESSION_RETENTION_S,
  CREW_WEEK_RETENTION_S, CrewFields, CrewWeek, DAILY_CAP_MINUTES, FUTURE_FLAG_PER_DAY, FlagKind, INVITE_CODE_LENGTH,
  BOARD_PAGE, BoardKey, HALL_PAGE, HallKey, decodeBoardCursor, encodeBoardCursor, JOIN_REQUESTS_PER_DAY, JOIN_REQUEST_TTL_S, MAX_CREW_JOIN_REQUESTS, MAX_CREW_MEMBERS, MEMBER_REF_LENGTH, MEMBER_REF_RE, MEMBER_SETTINGS_FIELDS, OVERLAP_FLAG_PER_DAY, PLACES,
  SESSIONS_FIELDS, SessionStatus, Stint, UPDATE_FIELDS, WEEKLY_CAP_MINUTES, allocateMinutes, checkSession, decodeHallCursor,
  encodeHallCursor, laurelOfRank, nameKey, weekFromId, weekPlaces,
  parseCode, parseCrewFields, parseCrewJoin, parseCrewReport, parseSessionList, parseShowPet, previousWeek, sessionSegments,
  weekOf,
} from "./crews";
import { MAX_REPORTS_PER_DAY, REPORTS_PER_MIN } from "./moderation";

/**
 * One migration step: only new tables, so it runs on the next deploy without touching Party data.
 * `crew_members` keeps a rowid on purpose: it breaks join order ties within one second.
 */
export const CREWS_SCHEMA = `
-- A crew; its crest is frame, emblem and color. name_key is the name with case folded, unique so no two crews share a name. gold,
-- silver and bronze count every weekly place ever (the trophy count and the Hall of Fame), and medals_at is the end of the week that
-- gave the crew its current tally; hidden is set by the maintainer (off the board, search, featured and the Hall of Fame).
CREATE TABLE crews (
  id          TEXT PRIMARY KEY,
  invite_code TEXT NOT NULL UNIQUE,
  name        TEXT NOT NULL,
  name_key    TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL,
  frame       TEXT NOT NULL,
  emblem      TEXT NOT NULL,
  color       TEXT NOT NULL,
  visibility  TEXT NOT NULL,
  owner       TEXT NOT NULL,
  hidden      INTEGER NOT NULL DEFAULT 0,
  gold        INTEGER NOT NULL DEFAULT 0,
  silver      INTEGER NOT NULL DEFAULT 0,
  bronze      INTEGER NOT NULL DEFAULT 0,
  medals_at   INTEGER,
  created_at  INTEGER NOT NULL
) WITHOUT ROWID;
-- The Hall of Fame order: most golds, silvers, bronzes, then whoever reached the tally first.
CREATE INDEX crews_by_medals ON crews (gold DESC, silver DESC, bronze DESC, medals_at, id);
-- Current membership, one crew per user. ref is the member's opaque id on crew pages (never the friend code).
CREATE TABLE crew_members (
  code      TEXT PRIMARY KEY,
  crew      TEXT NOT NULL,
  ref       TEXT NOT NULL UNIQUE,
  joined_at INTEGER NOT NULL,
  show_pet  INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX crew_members_by_crew ON crew_members (crew, joined_at);
-- Who belonged to which crew when, so a late session report credits the crew of the time. Closed stints
-- are kept CREW_SESSION_RETENTION_S after leaving.
CREATE TABLE crew_stints (
  code      TEXT NOT NULL,
  crew      TEXT NOT NULL,
  joined_at INTEGER NOT NULL,
  left_at   INTEGER,
  PRIMARY KEY (code, joined_at)
) WITHOUT ROWID;
CREATE INDEX crew_stints_by_left ON crew_stints (left_at);
-- Reported focus sessions that credited something, for overlap and retry checks; kept CREW_SESSION_RETENTION_S.
CREATE TABLE crew_sessions (
  code     TEXT NOT NULL,
  start    INTEGER NOT NULL,
  end      INTEGER NOT NULL,
  minutes  INTEGER NOT NULL,
  credited INTEGER NOT NULL,
  PRIMARY KEY (code, start)
) WITHOUT ROWID;
CREATE INDEX crew_sessions_by_end ON crew_sessions (end);
-- Minutes credited per user, crew and UTC day, with the day's crew week; kept CREW_WEEK_RETENTION_S.
CREATE TABLE crew_day_credits (
  code    TEXT NOT NULL,
  crew    TEXT NOT NULL,
  day     TEXT NOT NULL,
  week    TEXT NOT NULL,
  minutes INTEGER NOT NULL,
  PRIMARY KEY (code, crew, day)
) WITHOUT ROWID;
CREATE INDEX crew_day_credits_by_crew_week ON crew_day_credits (crew, week);
CREATE INDEX crew_day_credits_by_week ON crew_day_credits (week);
-- Each crew's total for a week (the board); kept CREW_WEEK_RETENTION_S.
CREATE TABLE crew_weeks (
  week    TEXT NOT NULL,
  crew    TEXT NOT NULL,
  minutes INTEGER NOT NULL,
  PRIMARY KEY (week, crew)
) WITHOUT ROWID;
-- A frozen week's places 1 to 3 (ties share one), with the crew's name and crest at the time. Kept forever (a few rows a week).
CREATE TABLE crew_awards (
  week    TEXT NOT NULL,
  rank    INTEGER NOT NULL,
  crew    TEXT NOT NULL,
  minutes INTEGER NOT NULL,
  name    TEXT NOT NULL,
  frame   TEXT NOT NULL,
  emblem  TEXT NOT NULL,
  color   TEXT NOT NULL,
  PRIMARY KEY (week, crew)
) WITHOUT ROWID;
CREATE INDEX crew_awards_by_crew ON crew_awards (crew);
-- Every crew's final place (null when hidden) and minutes in a frozen week, for its recent history; kept 5 weeks.
CREATE TABLE crew_results (
  week    TEXT NOT NULL,
  crew    TEXT NOT NULL,
  place   INTEGER,
  minutes INTEGER NOT NULL,
  PRIMARY KEY (crew, week)
) WITHOUT ROWID;
CREATE INDEX crew_results_by_week ON crew_results (week);
-- Weeks already frozen, so the rollup never runs twice for one week.
CREATE TABLE crew_rollups (
  week      TEXT PRIMARY KEY,
  rolled_at INTEGER NOT NULL
) WITHOUT ROWID;
-- A request to join a public crew, waiting for its owner: one per user at a time (a new one replaces it), with
-- an opaque ref the owner answers by. Expires after JOIN_REQUEST_TTL_S; dropped when the user joins any crew.
CREATE TABLE crew_join_requests (
  code       TEXT PRIMARY KEY,
  crew       TEXT NOT NULL,
  ref        TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL
) WITHOUT ROWID;
CREATE INDEX crew_join_requests_by_crew ON crew_join_requests (crew, created_at);
CREATE INDEX crew_join_requests_by_created ON crew_join_requests (created_at);
-- Members an owner removed; they cannot join that crew again.
CREATE TABLE crew_removals (
  crew       TEXT NOT NULL,
  code       TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (crew, code)
) WITHOUT ROWID;
-- Reports about a crew (member null) or one of its members, with the names as they were when reported.
CREATE TABLE crew_reports (
  id          INTEGER PRIMARY KEY,
  reporter    TEXT NOT NULL,
  crew        TEXT NOT NULL,
  member      TEXT,
  reason      TEXT NOT NULL,
  note        TEXT,
  crew_name   TEXT NOT NULL,
  member_name TEXT,
  created_at  INTEGER NOT NULL,
  resolved_at INTEGER,
  resolution  TEXT
);
CREATE INDEX crew_reports_by_reporter ON crew_reports (reporter, created_at);
CREATE INDEX crew_reports_by_crew ON crew_reports (crew);
-- Anti-cheat flags for the maintainer, at most one per user, week and kind.
CREATE TABLE crew_flags (
  id          INTEGER PRIMARY KEY,
  code        TEXT NOT NULL,
  crew        TEXT,
  week        TEXT NOT NULL,
  kind        TEXT NOT NULL,
  detail      TEXT,
  created_at  INTEGER NOT NULL,
  resolved_at INTEGER,
  resolution  TEXT,
  UNIQUE (code, week, kind)
);
-- Crew names a maintainer replaced; no crew can take them again.
CREATE TABLE crew_name_holds (
  name_key   TEXT PRIMARY KEY,
  created_at INTEGER NOT NULL
) WITHOUT ROWID;
`;

/** What the Hub lends the crews code. */
export interface CrewsHost {
  sql: Pick<SqlStorage, "exec">;
  transaction(fn: () => void): void;
  rateLimit(id: string, perWindow: number, now: number, windowS?: number): void;
  isBanned(code: string): boolean;
  hasBlocked(blocker: string, blocked: string): boolean;
  badgesByCode(codes: string[], now: number): Map<string, string[]>;
  /** Blocks `blocked` for `blocker` the way POST /v1/blocks does (crews included); false if already blocked. */
  block(blocker: string, blocked: string, now: number): boolean;
}

interface CrewRow extends Record<string, SqlStorageValue> {
  id: string;
  invite_code: string;
  name: string;
  name_key: string;
  description: string;
  frame: string;
  emblem: string;
  color: string;
  visibility: string;
  owner: string;
  hidden: number;
  gold: number;
  silver: number;
  bronze: number;
  medals_at: number | null;
  created_at: number;
}

interface MemberRow extends Record<string, SqlStorageValue> {
  code: string;
  crew: string;
  ref: string;
  joined_at: number;
  show_pet: number;
}

/** The ADMIN_REPORTS_PAGE of crew reports and flags. */
const ADMIN_PAGE = 100;

export class CrewService {
  /** The crew week whose rollup is known done, so routes skip the check within a week. */
  private rolledFor: string | null = null;
  /** Overlapping and future-dated reports per user and UTC day, for the flags (in memory, like rate limits). */
  private badReports = new Map<string, number>();
  /** The UTC day the crews retention sweep last ran on. */
  private sweptOn: string | null = null;

  constructor(private host: CrewsHost) {}

  private get sql() {
    return this.host.sql;
  }

  // ---------- routing ----------

  /** The crews routes for an authenticated caller; null when `path` is not one of them. */
  async route(req: Request, path: string, method: string, caller: string, now: number): Promise<Response | null> {
    if (!path.startsWith("/v1/crews")) return null;
    this.rollupIfDue(now);
    if (path === "/v1/crews" && method === "GET") return this.search(req, caller, now);
    if (path === "/v1/crews" && method === "POST") return await this.create(req, caller, now);
    if (path === "/v1/crews/mine" && method === "GET") {
      const crew = this.mineDetail(caller, now);
      return json({ ok: true, crew, week: weekOf(now), request: crew ? null : this.myRequest(caller, now) });
    }
    if (path === "/v1/crews/mine" && method === "PATCH") return await this.update(req, caller, now);
    if (path === "/v1/crews/mine/me" && method === "PATCH") return await this.memberSettings(req, caller, now);
    if (path === "/v1/crews/join" && method === "POST") return await this.join(req, caller, now);
    if (path === "/v1/crews/leave" && method === "POST") return await this.leaveRoute(req, caller, now);
    if (path === "/v1/crews/requests/cancel" && method === "POST") return await this.cancelRequest(req, caller, now);
    const answer = /^\/v1\/crews\/mine\/requests\/([^/]+)\/(approve|decline)$/.exec(path);
    if (answer && method === "POST") return answer[2] === "approve" ? this.approve(caller, answer[1], now) : this.decline(caller, answer[1], now);
    if (path === "/v1/crews/board" && method === "GET") return this.board(req, caller, now);
    if (path === "/v1/crews/hall" && method === "GET") return this.hall(req, caller, now);
    if (path === "/v1/crews/sessions" && method === "POST") return await this.reportSessions(req, caller, now);
    if (path === "/v1/crews/reports" && method === "POST") return await this.report(req, caller, now);
    if (path === "/v1/crews/block" && method === "POST") return await this.blockRoute(req, caller, now);
    const remove = /^\/v1\/crews\/mine\/members\/([^/]+)\/remove$/.exec(path);
    if (remove && method === "POST") return this.removeMember(caller, remove[1], now);
    const crew = /^\/v1\/crews\/([^/]+)$/.exec(path);
    if (crew && method === "GET") return this.view(caller, crew[1], now);
    throw new HttpError(404, "not_found", "not found");
  }

  /** The maintainer's crews routes under /v1/admin/crews; null when `path` is not one of them. */
  async adminRoute(req: Request, path: string, method: string, now: number): Promise<Response | null> {
    if (!path.startsWith("/v1/admin/crews")) return null;
    this.rollupIfDue(now);
    const status = () => {
      const s = new URL(req.url).searchParams.get("status") ?? "open";
      if (s !== "open" && s !== "all") throw new HttpError(400, "invalid_field", "status must be open or all");
      return s === "open";
    };
    if (path === "/v1/admin/crews/reports" && method === "GET") return this.adminReports(status());
    if (path === "/v1/admin/crews/flags" && method === "GET") return this.adminFlags(status());
    const dismissReport = /^\/v1\/admin\/crews\/reports\/(\d+)\/dismiss$/.exec(path);
    if (dismissReport && method === "POST") return this.resolveRow("crew_reports", Number(dismissReport[1]), "dismissed", now, "report");
    const flag = /^\/v1\/admin\/crews\/flags\/(\d+)\/(dismiss|void)$/.exec(path);
    if (flag && flag[2] === "dismiss" && method === "POST") return this.resolveRow("crew_flags", Number(flag[1]), "dismissed", now, "flag");
    if (flag && flag[2] === "void" && method === "POST") return this.voidFlag(Number(flag[1]), now);
    const crewAction = /^\/v1\/admin\/crews\/([^/]+)\/(rename|hide)$/.exec(path);
    if (crewAction && crewAction[2] === "rename" && method === "POST") return this.adminRename(crewAction[1], now);
    if (crewAction && crewAction[2] === "hide" && method === "POST") return this.adminHide(crewAction[1], true, now);
    if (crewAction && crewAction[2] === "hide" && method === "DELETE") return this.adminHide(crewAction[1], false, now);
    const crew = /^\/v1\/admin\/crews\/([^/]+)$/.exec(path);
    if (crew && method === "GET") return this.adminView(crew[1], now);
    if (crew && method === "DELETE") return this.adminDelete(crew[1], now);
    throw new HttpError(404, "not_found", "not found");
  }

  // ---------- lookups ----------

  private crewRow(id: string): CrewRow | undefined {
    return this.sql.exec<CrewRow>("SELECT * FROM crews WHERE id = ?", id).toArray()[0];
  }

  private memberRow(code: string): MemberRow | undefined {
    return this.sql.exec<MemberRow>("SELECT * FROM crew_members WHERE code = ?", code).toArray()[0];
  }

  private memberCount(crew: string): number {
    return this.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM crew_members WHERE crew = ?", crew).one().n;
  }

  private weekMinutes(crew: string, week: string): number {
    return this.sql.exec<{ minutes: number }>("SELECT minutes FROM crew_weeks WHERE week = ? AND crew = ?", week, crew)
      .toArray()[0]?.minutes ?? 0;
  }

  private blockedEitherWay(a: string, b: string): boolean {
    return this.host.hasBlocked(a, b) || this.host.hasBlocked(b, a);
  }

  /** My crew, which I must be in. */
  private myCrew(caller: string): { member: MemberRow; crew: CrewRow } {
    const member = this.memberRow(caller);
    const crew = member && this.crewRow(member.crew);
    if (!member || !crew) throw new HttpError(404, "not_in_crew", "you are not in a crew");
    return { member, crew };
  }

  private requireNotBanned(caller: string): void {
    if (this.host.isBanned(caller)) throw new HttpError(403, "banned", "this account can no longer use Party");
  }

  /** The laurel each crew wears this week: the tier it won last week. */
  private laurels(now: number): Map<string, string> {
    const rows = this.sql.exec<{ crew: string; rank: number }>(
      "SELECT crew, rank FROM crew_awards WHERE week = ?", previousWeek(now).id).toArray();
    return new Map(rows.flatMap((r) => {
      const laurel = laurelOfRank(r.rank);
      return laurel ? [[r.crew, laurel] as [string, string]] : [];
    }));
  }

  // ---------- views ----------

  private summary(c: CrewRow, now: number, laurels = this.laurels(now), minutes?: number, memberCount?: number) {
    return {
      id: c.id,
      name: c.name,
      description: c.description,
      frame: c.frame,
      emblem: c.emblem,
      color: c.color,
      visibility: c.visibility,
      laurel: laurels.get(c.id) ?? null,
      trophies: c.gold + c.silver + c.bronze,
      golds: c.gold,
      memberCount: memberCount ?? this.memberCount(c.id),
      maxMembers: MAX_CREW_MEMBERS,
      weekMinutes: minutes ?? this.weekMinutes(c.id, weekOf(now).id),
    };
  }

  /** This week's live rank among visible crews (ties share it), or null with no minutes. */
  private liveRank(crew: string, minutes: number, week: string): number | null {
    if (minutes <= 0) return null;
    const ahead = this.sql.exec<{ n: number }>(
      `SELECT COUNT(*) AS n FROM crew_weeks w JOIN crews c ON c.id = w.crew
       WHERE w.week = ? AND w.minutes > ? AND c.hidden = 0`, week, minutes).one().n;
    return ahead + 1;
  }

  /** A crew page as `viewer` sees it. */
  private detail(c: CrewRow, viewer: string, now: number) {
    const week = weekOf(now).id;
    const minutes = this.weekMinutes(c.id, week);
    const rows = this.sql.exec<MemberRow & {
      name: string; pet_name: string; species: string; breed: string; colors: string; costume: string; accessories: string;
    }>(
      `SELECT m.*, u.name, u.pet_name, u.species, u.breed, u.colors, u.costume, u.accessories
       FROM crew_members m JOIN users u ON u.code = m.code
       WHERE m.crew = ?1
         AND m.code NOT IN (SELECT blocked FROM blocks WHERE blocker = ?2)
         AND m.code NOT IN (SELECT blocker FROM blocks WHERE blocked = ?2)
         AND (m.code = ?2 OR m.code NOT IN (SELECT code FROM bans))
       ORDER BY m.code = ?3 DESC, m.joined_at, m.rowid`,
      c.id, viewer, c.owner,
    ).toArray();
    const credited = new Map(this.sql.exec<{ code: string; minutes: number }>(
      "SELECT code, SUM(minutes) AS minutes FROM crew_day_credits WHERE crew = ? AND week = ? GROUP BY code", c.id, week,
    ).toArray().map((r) => [r.code, r.minutes]));
    const badges = this.host.badgesByCode(rows.map((r) => r.code), now);
    const mine = this.memberRow(viewer)?.crew === c.id;
    return {
      ...this.summary(c, now, undefined, minutes),
      createdAt: c.created_at,
      medals: { gold: c.gold, silver: c.silver, bronze: c.bronze },
      rank: c.hidden ? null : this.liveRank(c.id, minutes, week),
      crewCount: this.crewCount(week),
      history: this.history(c, now),
      members: rows.map((r) => ({
        ref: r.ref,
        name: r.name,
        pet: r.show_pet === 1
          ? {
            petName: r.pet_name, species: r.species, breed: r.breed,
            colors: JSON.parse(r.colors) as string[], costume: r.costume, accessories: JSON.parse(r.accessories) as string[],
          }
          : null,
        badges: badges.get(r.code) ?? [],
        weekMinutes: credited.get(r.code) ?? 0,
        owner: r.code === c.owner,
        me: r.code === viewer,
      })).sort((a, b) => b.weekMinutes - a.weekMinutes || a.name.localeCompare(b.name) || (a.ref < b.ref ? -1 : 1)),
      mine,
      owner: c.owner === viewer,
      inviteCode: mine ? c.invite_code : null,
      hidden: mine ? c.hidden === 1 : false,
      ...(c.owner === viewer ? { requests: this.pendingRequests(c.id, viewer, now) } : {}),
    };
  }

  // ---------- join requests ----------

  /** The join requests waiting for crew `crew`, oldest first, as its owner `viewer` sees them. */
  private pendingRequests(crew: string, viewer: string, now: number) {
    const rows = this.sql.exec<{
      code: string; ref: string; created_at: number; name: string; pet_name: string; species: string; breed: string;
      colors: string; costume: string; accessories: string;
    }>(
      `SELECT r.code, r.ref, r.created_at, u.name, u.pet_name, u.species, u.breed, u.colors, u.costume, u.accessories
       FROM crew_join_requests r JOIN users u ON u.code = r.code
       WHERE r.crew = ?1 AND r.created_at > ?2
         AND r.code NOT IN (SELECT blocked FROM blocks WHERE blocker = ?3)
         AND r.code NOT IN (SELECT blocker FROM blocks WHERE blocked = ?3)
         AND r.code NOT IN (SELECT code FROM bans)
       ORDER BY r.created_at, r.ref`,
      crew, now - JOIN_REQUEST_TTL_S, viewer,
    ).toArray();
    const badges = this.host.badgesByCode(rows.map((r) => r.code), now);
    return rows.map((r) => ({
      ref: r.ref,
      name: r.name,
      pet: {
        petName: r.pet_name, species: r.species, breed: r.breed,
        colors: JSON.parse(r.colors) as string[], costume: r.costume, accessories: JSON.parse(r.accessories) as string[],
      },
      badges: badges.get(r.code) ?? [],
      requestedAt: r.created_at,
      expiresAt: r.created_at + JOIN_REQUEST_TTL_S,
    }));
  }

  /** My pending join request, if it is still live and its crew still visible. */
  private myRequestRow(code: string, now: number): { crew: CrewRow; created_at: number } | null {
    const r = this.sql.exec<{ crew: string; created_at: number }>(
      "SELECT crew, created_at FROM crew_join_requests WHERE code = ? AND created_at > ?", code, now - JOIN_REQUEST_TTL_S).toArray()[0];
    const crew = r && this.crewRow(r.crew);
    return r && crew && !crew.hidden ? { crew, created_at: r.created_at } : null;
  }

  private myRequest(code: string, now: number) {
    const r = this.myRequestRow(code, now);
    return r ? { crew: this.summary(r.crew, now), requestedAt: r.created_at, expiresAt: r.created_at + JOIN_REQUEST_TTL_S } : null;
  }

  /** How many live join requests wait for `crew`. */
  private pendingCount(crew: string, now: number): number {
    return this.sql.exec<{ n: number }>(
      "SELECT COUNT(*) AS n FROM crew_join_requests WHERE crew = ? AND created_at > ?", crew, now - JOIN_REQUEST_TTL_S).one().n;
  }

  /**
   * Asks to join public crew `crew` (from POST /v1/crews/join with `{ crew }`): one request per user, so a new
   * one replaces mine; asking the same crew again is a no-op success.
   */
  private requestToJoin(caller: string, crew: CrewRow, now: number): Response {
    const pending = this.myRequestRow(caller, now);
    if (pending?.crew.id !== crew.id) {
      if (this.pendingCount(crew.id, now) >= MAX_CREW_JOIN_REQUESTS) {
        throw new HttpError(409, "requests_full", "this crew has too many requests waiting; try again later");
      }
      try {
        this.host.rateLimit("crewrequestday:" + caller, JOIN_REQUESTS_PER_DAY, now, 86_400);
      } catch (e) {
        if (e instanceof HttpError && e.status === 429) {
          throw new HttpError(429, "request_limit", `at most ${JOIN_REQUESTS_PER_DAY} crew requests a day`, e.headers);
        }
        throw e;
      }
      const ref = this.newId(MEMBER_REF_LENGTH, "ref", "crew_join_requests");
      this.sql.exec("INSERT OR REPLACE INTO crew_join_requests (code, crew, ref, created_at) VALUES (?, ?, ?, ?)", caller, crew.id, ref, now);
    }
    return json({ ok: true, joined: false, requested: true, request: this.myRequest(caller, now), crew: this.detail(crew, caller, now) });
  }

  /** The live join request with `raw` ref waiting for my crew, which I must own. */
  private ownedRequest(caller: string, raw: string, now: number) {
    const ref = parseCode(raw, MEMBER_REF_RE, "request");
    this.host.rateLimit("crewchange:" + caller, CREW_CHANGES_PER_MIN, now);
    const { crew } = this.myCrew(caller);
    if (crew.owner !== caller) throw new HttpError(403, "not_owner", "only the crew's owner can answer requests");
    const request = this.sql.exec<{ code: string }>(
      "SELECT code FROM crew_join_requests WHERE ref = ? AND crew = ? AND created_at > ?", ref, crew.id, now - JOIN_REQUEST_TTL_S).toArray()[0];
    if (!request) throw new HttpError(404, "request_not_found", "no request for your crew has that id");
    return { crew, code: request.code };
  }

  /** POST /v1/crews/mine/requests/{ref}/approve: the requester joins my crew. */
  private approve(caller: string, raw: string, now: number): Response {
    const { crew, code } = this.ownedRequest(caller, raw, now);
    const drop = () => this.sql.exec("DELETE FROM crew_join_requests WHERE code = ?", code);
    if (this.host.isBanned(code) || this.blockedEitherWay(caller, code)) {
      drop();
      throw new HttpError(404, "request_not_found", "no request for your crew has that id");
    }
    if (this.memberRow(code)) {
      drop();
      throw new HttpError(409, "in_crew", "they joined another crew meanwhile");
    }
    if (this.memberCount(crew.id) >= MAX_CREW_MEMBERS) {
      throw new HttpError(409, "crew_full", `a crew has at most ${MAX_CREW_MEMBERS} members`);
    }
    this.host.transaction(() => this.addMember(code, crew.id, now));
    return json({ ok: true, crew: this.detail(this.crewRow(crew.id)!, caller, now) });
  }

  /** POST /v1/crews/mine/requests/{ref}/decline: the request goes away; the requester is never told. */
  private decline(caller: string, raw: string, now: number): Response {
    const { code } = this.ownedRequest(caller, raw, now);
    this.sql.exec("DELETE FROM crew_join_requests WHERE code = ?", code);
    return json({ ok: true, declined: true });
  }

  /** POST /v1/crews/requests/cancel: withdraws my pending join request. */
  private async cancelRequest(req: Request, caller: string, now: number): Promise<Response> {
    await readBody(req, []);
    this.host.rateLimit("crewchange:" + caller, CREW_CHANGES_PER_MIN, now);
    const cancelled = this.sql.exec("DELETE FROM crew_join_requests WHERE code = ?", caller).rowsWritten > 0;
    return json({ ok: true, cancelled });
  }

  /**
   * What the presence heartbeat reply carries about crews (two indexed lookups): my crew's id, and the join
   * requests waiting for it when I own it, so the app can badge the tab and notice an approval without polling.
   */
  heartbeatInfo(code: string, now: number): { requests: number; crew: string | null } {
    const member = this.memberRow(code);
    if (!member) return { requests: 0, crew: null };
    const owns = this.sql.exec("SELECT 1 FROM crews WHERE id = ? AND owner = ?", member.crew, code).toArray().length > 0;
    return { requests: owns ? this.pendingCount(member.crew, now) : 0, crew: member.crew };
  }

  private mineDetail(caller: string, now: number) {
    const member = this.memberRow(caller);
    const crew = member && this.crewRow(member.crew);
    return crew ? this.detail(crew, caller, now) : null;
  }

  /**
   * A week's places 1 to 3 among visible crews: every crew with at least the third-highest distinct place's
   * minutes, ranked by `weekPlaces` (ties share a place, so there can be more than three).
   */
  private placed(week: string) {
    const rows = this.sql.exec<CrewRow & { minutes: number; members: number }>(
      `SELECT c.*, w.minutes, (SELECT COUNT(*) FROM crew_members m WHERE m.crew = c.id) AS members
       FROM crew_weeks w JOIN crews c ON c.id = w.crew
       WHERE w.week = ?1 AND w.minutes > 0 AND c.hidden = 0 AND w.minutes >= COALESCE((
         SELECT w2.minutes FROM crew_weeks w2 JOIN crews c2 ON c2.id = w2.crew
         WHERE w2.week = ?1 AND w2.minutes > 0 AND c2.hidden = 0 ORDER BY w2.minutes DESC LIMIT 1 OFFSET ?2), 0)`,
      week, PLACES - 1,
    ).toArray();
    return weekPlaces(rows);
  }

  /**
   * This week's live places 1 to 3, most minutes first, then by crew id. With a `viewer` each entry also
   * carries `tiedWith` and the pets of the crew's most active members, as that viewer may see them.
   */
  private liveTop(now: number, viewer?: string) {
    const laurels = this.laurels(now);
    const week = weekOf(now).id;
    const placed = this.placed(week);
    return placed.map((r) => ({
      rank: r.rank,
      minutes: r.minutes,
      crew: this.summary(r, now, laurels, r.minutes, r.members),
      ...(viewer === undefined ? {} : {
        tiedWith: this.tiedWith(week, r.id, r.minutes),
        pets: this.activePets(r.id, week, viewer),
      }),
    }));
  }

  /** Visible crews with minutes this week: how many crews the board ranks. */
  private crewCount(week: string): number {
    return this.sql.exec<{ n: number }>(
      "SELECT COUNT(*) AS n FROM crew_weeks w JOIN crews c ON c.id = w.crew WHERE w.week = ? AND w.minutes > 0 AND c.hidden = 0", week,
    ).one().n;
  }

  /** The names of up to two other visible crews with exactly `minutes` this week (the same place). */
  private tiedWith(week: string, crew: string, minutes: number): string[] {
    return this.sql.exec<{ name: string }>(
      `SELECT c.name FROM crew_weeks w JOIN crews c ON c.id = w.crew
       WHERE w.week = ? AND w.minutes = ? AND w.crew != ? AND c.hidden = 0 ORDER BY c.id LIMIT 2`, week, minutes, crew,
    ).toArray().map((r) => r.name);
  }

  /**
   * The pets of a crew's three most active members in `week` (most credited minutes, then longest in the
   * crew), as `viewer` may see them: hidden pets, banned members and members blocked either way are skipped.
   */
  private activePets(crew: string, week: string, viewer: string) {
    return this.sql.exec<{ pet_name: string; species: string; breed: string; colors: string; costume: string; accessories: string }>(
      `SELECT u.pet_name, u.species, u.breed, u.colors, u.costume, u.accessories,
         (SELECT COALESCE(SUM(minutes), 0) FROM crew_day_credits d WHERE d.code = m.code AND d.crew = m.crew AND d.week = ?2) AS minutes
       FROM crew_members m JOIN users u ON u.code = m.code
       WHERE m.crew = ?1 AND m.show_pet = 1
         AND m.code NOT IN (SELECT blocked FROM blocks WHERE blocker = ?3)
         AND m.code NOT IN (SELECT blocker FROM blocks WHERE blocked = ?3)
         AND m.code NOT IN (SELECT code FROM bans)
       ORDER BY minutes DESC, m.joined_at, m.rowid LIMIT 3`,
      crew, week, viewer,
    ).toArray().map((r) => ({
      petName: r.pet_name, species: r.species, breed: r.breed,
      colors: JSON.parse(r.colors) as string[], costume: r.costume, accessories: JSON.parse(r.accessories) as string[],
    }));
  }

  /**
   * The crew's last three finished weeks, newest first: its final place and minutes, and the medal a place
   * 1 to 3 won. A week that ended before the crew existed is left out; a week it had no minutes in shows
   * no place and 0 minutes.
   */
  private history(c: CrewRow, now: number) {
    const out = [];
    let week = previousWeek(now);
    for (let i = 0; i < 3 && c.created_at < week.endsAt; i++) {
      const r = this.sql.exec<{ place: number | null; minutes: number }>(
        "SELECT place, minutes FROM crew_results WHERE crew = ? AND week = ?", c.id, week.id).toArray()[0];
      const place = r?.place ?? null;
      out.push({ week, place, minutes: r?.minutes ?? 0, medal: place === null ? null : laurelOfRank(place) });
      week = previousWeek(week.startsAt);
    }
    return out;
  }

  /**
   * The weekly board's rows: visible crews with minutes this week below the places 1 to 3, most minutes
   * first, then by id, BOARD_PAGE at a time after `after`, each with its shared place and `tiedWith`.
   */
  private boardRows(now: number, after: BoardKey | null) {
    const week = weekOf(now).id;
    const placed = this.placed(week);
    if (placed.length < 3) return { rows: [], next: null };
    const floor = Math.min(...placed.map((p) => p.minutes));
    const rows = this.sql.exec<CrewRow & { minutes: number; members: number }>(
      `SELECT c.*, w.minutes, (SELECT COUNT(*) FROM crew_members m WHERE m.crew = c.id) AS members
       FROM crew_weeks w JOIN crews c ON c.id = w.crew
       WHERE w.week = ?1 AND w.minutes > 0 AND w.minutes < ?2 AND c.hidden = 0
         AND (?3 = 0 OR w.minutes < ?4 OR (w.minutes = ?4 AND c.id > ?5))
       ORDER BY w.minutes DESC, c.id ASC LIMIT ?6`,
      week, floor, after ? 1 : 0, after?.minutes ?? 0, after?.id ?? "", BOARD_PAGE + 1,
    ).toArray();
    const page = rows.slice(0, BOARD_PAGE);
    const laurels = this.laurels(now);
    const last = page.at(-1);
    return {
      rows: page.map((r) => ({
        rank: this.liveRank(r.id, r.minutes, week) ?? 1,
        minutes: r.minutes,
        crew: this.summary(r, now, laurels, r.minutes, r.members),
        tiedWith: this.tiedWith(week, r.id, r.minutes),
      })),
      next: rows.length > BOARD_PAGE && last ? encodeBoardCursor({ minutes: last.minutes, id: last.id }) : null,
    };
  }

  /**
   * Last week's frozen places, the featured crews, leaving out crews since deleted or hidden. With a
   * `viewer` each entry also carries `tiedWith` (crews that shared its place) and the pets of the crew's
   * most active members that week.
   */
  private featured(now: number, viewer?: string) {
    const last = previousWeek(now);
    const rows = this.sql.exec<CrewRow & { rank: number; award_minutes: number }>(
      `SELECT c.*, a.rank, a.minutes AS award_minutes FROM crew_awards a JOIN crews c ON c.id = a.crew
       WHERE a.week = ? AND c.hidden = 0 ORDER BY a.minutes DESC, a.crew ASC`, last.id,
    ).toArray();
    if (rows.length === 0) return null;
    const won = new Map(rows.map((r) => [r.id, laurelOfRank(r.rank) ?? ""]));
    return {
      week: last,
      entries: rows.map((r) => ({
        rank: r.rank, minutes: r.award_minutes, crew: this.summary(r, now, won),
        ...(viewer === undefined ? {} : {
          tiedWith: rows.filter((o) => o.rank === r.rank && o.id !== r.id).slice(0, 2).map((o) => o.name),
          pets: this.activePets(r.id, last.id, viewer),
        }),
      })),
    };
  }

  /**
   * GET /v1/crews/hall?cursor=: every visible crew with a medal, in Olympic order (most golds, then
   * silvers, then bronzes, then whoever reached that tally first, then id), HALL_PAGE at a time. Ranks are
   * distinct: 1 plus the crew's position in that order. Paging is keyset on the order, so a page never
   * repeats or skips a crew that did not change in between.
   */
  private hall(req: Request, caller: string, now: number): Response {
    const raw = new URL(req.url).searchParams.get("cursor");
    const after: HallKey | null = raw === null || raw === "" ? null : decodeHallCursor(raw);
    const order = "c.gold DESC, c.silver DESC, c.bronze DESC, c.medals_at ASC, c.id ASC";
    const rows = this.sql.exec<CrewRow & { members: number }>(
      `SELECT c.*, (SELECT COUNT(*) FROM crew_members m WHERE m.crew = c.id) AS members FROM crews c
       WHERE c.hidden = 0 AND c.gold + c.silver + c.bronze > 0 AND (?1 = 0
         OR c.gold < ?2 OR (c.gold = ?2 AND (c.silver < ?3 OR (c.silver = ?3 AND (c.bronze < ?4 OR (c.bronze = ?4
           AND (c.medals_at > ?5 OR (c.medals_at = ?5 AND c.id > ?6))))))))
       ORDER BY ${order} LIMIT ?7`,
      after ? 1 : 0, after?.gold ?? 0, after?.silver ?? 0, after?.bronze ?? 0, after?.reachedAt ?? 0, after?.id ?? "", HALL_PAGE + 1,
    ).toArray();
    const page = rows.slice(0, HALL_PAGE);
    const laurels = this.laurels(now);
    const week = weekOf(now).id;
    const entries = page.map((r, i) => ({
      rank: this.hallRank(r),
      medals: { gold: r.gold, silver: r.silver, bronze: r.bronze },
      reachedAt: r.medals_at ?? 0,
      crew: this.summary(r, now, laurels, undefined, r.members),
      // The first page's top three are featured tiles, with the pets of their most active members this week.
      ...(after === null && i < 3 ? { pets: this.activePets(r.id, week, caller) } : {}),
    }));
    const last = page.at(-1);
    const next = rows.length > HALL_PAGE && last
      ? encodeHallCursor({ gold: last.gold, silver: last.silver, bronze: last.bronze, reachedAt: last.medals_at ?? 0, id: last.id })
      : null;
    if (after !== null) return json({ ok: true, entries, next });
    // On the first page, where my crew stands: no rank and a zero tally before its first medal.
    const member = this.memberRow(caller);
    const crew = member && this.crewRow(member.crew);
    const mine = crew ? {
      rank: crew.hidden || crew.gold + crew.silver + crew.bronze === 0 ? null : this.hallRank(crew),
      medals: { gold: crew.gold, silver: crew.silver, bronze: crew.bronze },
      reachedAt: crew.medals_at,
    } : null;
    return json({ ok: true, entries, next, mine });
  }

  /** 1 plus the number of visible medal crews ahead of `r` in the Hall of Fame's order. */
  private hallRank(r: CrewRow): number {
    return 1 + this.sql.exec<{ n: number }>(
      `SELECT COUNT(*) AS n FROM crews c WHERE c.hidden = 0 AND c.gold + c.silver + c.bronze > 0 AND (
         c.gold > ?1 OR (c.gold = ?1 AND (c.silver > ?2 OR (c.silver = ?2 AND (c.bronze > ?3
           OR (c.bronze = ?3 AND (c.medals_at < ?4 OR (c.medals_at = ?4 AND c.id < ?5))))))))`,
      r.gold, r.silver, r.bronze, r.medals_at ?? 0, r.id,
    ).one().n;
  }

  /**
   * GET /v1/crews/board[?cursor=]: the week's places 1 to 3 (`top`), last week's (`featured`), the first
   * page of the places below (`rows`, `next`), how many crews have minutes (`crewCount`) and where my crew
   * stands (`mine`). With a cursor it answers only the next page of rows (`week`, `rows`, `next`, `crewCount`).
   */
  private board(req: Request, caller: string, now: number): Response {
    const week = weekOf(now);
    const raw = new URL(req.url).searchParams.get("cursor");
    const crewCount = this.crewCount(week.id);
    if (raw !== null && raw !== "") {
      return json({ ok: true, week, ...this.boardRows(now, decodeBoardCursor(raw)), crewCount });
    }
    const member = this.memberRow(caller);
    const crew = member && this.crewRow(member.crew);
    const mine = crew ? (() => {
      const minutes = this.weekMinutes(crew.id, week.id);
      return { rank: crew.hidden ? null : this.liveRank(crew.id, minutes, week.id), minutes };
    })() : null;
    return json({
      ok: true, week, top: this.liveTop(now, caller), featured: this.featured(now, caller),
      ...this.boardRows(now, null), crewCount, mine,
    });
  }

  /**
   * Whether `viewer` may open crew `c`: their own, a public one, or one on the board (this week's live
   * top 3 or the featured crews). A hidden crew is only for its members; a crew whose owner and the viewer
   * blocked each other does not exist for the viewer.
   */
  private canView(c: CrewRow, viewer: string, now: number): boolean {
    if (this.memberRow(viewer)?.crew === c.id) return true;
    if (c.hidden || this.blockedEitherWay(viewer, c.owner)) return false;
    if (c.visibility === "public") return true;
    const onBoard = this.liveTop(now).some((e) => e.crew.id === c.id)
      || (this.featured(now)?.entries ?? []).some((e) => e.crew.id === c.id);
    return onBoard;
  }

  private viewable(raw: string, viewer: string, now: number): CrewRow {
    const id = parseCode(raw, CREW_ID_RE, "crew");
    const crew = this.crewRow(id);
    if (!crew || !this.canView(crew, viewer, now)) throw new HttpError(404, "crew_not_found", "no crew has that id");
    return crew;
  }

  private view(caller: string, raw: string, now: number): Response {
    return json({ ok: true, crew: this.detail(this.viewable(raw, caller, now), caller, now) });
  }

  /** GET /v1/crews?q=: public crews whose name contains q, most minutes this week first. */
  private search(req: Request, caller: string, now: number): Response {
    this.host.rateLimit("crewsearch:" + caller, CREW_SEARCHES_PER_MIN, now);
    const q = cleanText(new URL(req.url).searchParams.get("q") ?? undefined, "q", 64);
    const pattern = q === undefined ? "%" : "%" + nameKey(q).replace(/[\\%_]/g, (ch) => "\\" + ch) + "%";
    const week = weekOf(now);
    const rows = this.sql.exec<CrewRow & { minutes: number; members: number }>(
      `SELECT c.*, COALESCE(w.minutes, 0) AS minutes, (SELECT COUNT(*) FROM crew_members m WHERE m.crew = c.id) AS members
       FROM crews c LEFT JOIN crew_weeks w ON w.crew = c.id AND w.week = ?1
       WHERE c.visibility = 'public' AND c.hidden = 0 AND c.name_key LIKE ?2 ESCAPE '\\'
         AND c.owner NOT IN (SELECT blocked FROM blocks WHERE blocker = ?3)
         AND c.owner NOT IN (SELECT blocker FROM blocks WHERE blocked = ?3)
       ORDER BY minutes DESC, c.name_key ASC, c.id ASC LIMIT ?4`,
      week.id, pattern, caller, CREW_SEARCH_PAGE,
    ).toArray();
    const laurels = this.laurels(now);
    return json({ ok: true, crews: rows.map((r) => this.summary(r, now, laurels, r.minutes, r.members)), week });
  }

  // ---------- membership ----------

  private newId(length: number, column: string, table: string): string {
    for (let i = 0; i < 20; i++) {
      const id = newCode(length);
      if (this.sql.exec(`SELECT 1 FROM ${table} WHERE ${column} = ?`, id).toArray().length === 0) return id;
    }
    throw new HttpError(503, "unavailable", "could not allocate an id, retry");
  }

  /** The name is free: no other crew has it (ignoring case) and no maintainer took it away. */
  private checkName(name: string, except: string | null): string {
    const key = nameKey(name);
    if (this.sql.exec("SELECT 1 FROM crew_name_holds WHERE name_key = ?", key).toArray().length > 0) {
      throw new HttpError(400, "crew_name_not_allowed", "That crew name isn't allowed. Please pick another.");
    }
    const other = this.sql.exec<{ id: string }>("SELECT id FROM crews WHERE name_key = ?", key).toArray()[0];
    if (other && other.id !== except) throw new HttpError(409, "name_taken", "Another crew has that name.");
    return key;
  }

  /** Adds `code` to `crew` (call inside a transaction): a member row and an open stint. */
  private addMember(code: string, crew: string, now: number): void {
    const ref = this.newId(MEMBER_REF_LENGTH, "ref", "crew_members");
    this.sql.exec("INSERT INTO crew_members (code, crew, ref, joined_at) VALUES (?, ?, ?, ?)", code, crew, ref, now);
    this.sql.exec("DELETE FROM crew_join_requests WHERE code = ?", code);
    this.sql.exec("INSERT OR REPLACE INTO crew_stints (code, crew, joined_at, left_at) VALUES (?, ?, ?, NULL)", code, crew, now);
  }

  /** POST /v1/crews: a new crew with the caller as owner. */
  private async create(req: Request, caller: string, now: number): Promise<Response> {
    const fields = parseCrewFields(await readBody(req, CREATE_FIELDS), true) as Required<CrewFields>;
    this.requireNotBanned(caller);
    if (this.memberRow(caller)) throw new HttpError(409, "in_crew", "leave your crew first");
    const key = this.checkName(fields.name, null);
    try {
      this.host.rateLimit("crewcreate:" + caller, CREW_CREATES_PER_DAY, now, 86_400);
    } catch (e) {
      if (e instanceof HttpError && e.status === 429) {
        throw new HttpError(429, "crew_limit", `at most ${CREW_CREATES_PER_DAY} new crews a day`, e.headers);
      }
      throw e;
    }
    const id = this.newId(CREW_ID_LENGTH, "id", "crews");
    const invite = this.newId(INVITE_CODE_LENGTH, "invite_code", "crews");
    this.host.transaction(() => {
      this.sql.exec(
        `INSERT INTO crews (id, invite_code, name, name_key, description, frame, emblem, color, visibility, owner, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        id, invite, fields.name, key, fields.description ?? "", fields.frame, fields.emblem, fields.color, fields.visibility, caller, now,
      );
      this.addMember(caller, id, now);
    });
    return json({ ok: true, crew: this.detail(this.crewRow(id)!, caller, now) }, 201);
  }

  /** PATCH /v1/crews/mine: the owner edits the crew. */
  private async update(req: Request, caller: string, now: number): Promise<Response> {
    const fields = parseCrewFields(await readBody(req, UPDATE_FIELDS), false);
    this.host.rateLimit("crewchange:" + caller, CREW_CHANGES_PER_MIN, now);
    const { crew } = this.myCrew(caller);
    if (crew.owner !== caller) throw new HttpError(403, "not_owner", "only the crew's owner can change it");
    this.requireNotBanned(caller);
    const next = { ...crew };
    if (fields.name !== undefined && fields.name !== crew.name) {
      next.name_key = this.checkName(fields.name, crew.id);
      next.name = fields.name;
    }
    if (fields.description !== undefined) next.description = fields.description;
    if (fields.frame !== undefined) next.frame = fields.frame;
    if (fields.emblem !== undefined) next.emblem = fields.emblem;
    if (fields.color !== undefined) next.color = fields.color;
    if (fields.visibility !== undefined) next.visibility = fields.visibility;
    this.sql.exec(
      "UPDATE crews SET name = ?, name_key = ?, description = ?, frame = ?, emblem = ?, color = ?, visibility = ? WHERE id = ?",
      next.name, next.name_key, next.description, next.frame, next.emblem, next.color, next.visibility, crew.id,
    );
    return json({ ok: true, crew: this.detail(this.crewRow(crew.id)!, caller, now) });
  }

  /** PATCH /v1/crews/mine/me: whether my pet shows on crew pages. */
  private async memberSettings(req: Request, caller: string, now: number): Promise<Response> {
    const showPet = parseShowPet(await readBody(req, MEMBER_SETTINGS_FIELDS));
    const { crew } = this.myCrew(caller);
    this.sql.exec("UPDATE crew_members SET show_pet = ? WHERE code = ?", showPet ? 1 : 0, caller);
    return json({ ok: true, crew: this.detail(crew, caller, now) });
  }

  /** POST /v1/crews/join with an invite code, or a public crew's id. */
  private async join(req: Request, caller: string, now: number): Promise<Response> {
    const target = parseCrewJoin(await readBody(req, CREW_JOIN_FIELDS));
    this.host.rateLimit("crewchange:" + caller, CREW_CHANGES_PER_MIN, now);
    this.requireNotBanned(caller);
    const crew = "code" in target
      ? this.sql.exec<CrewRow>("SELECT * FROM crews WHERE invite_code = ?", target.code).toArray()[0]
      : this.sql.exec<CrewRow>("SELECT * FROM crews WHERE id = ? AND visibility = 'public'", target.crew).toArray()[0];
    const current = this.memberRow(caller);
    if (crew && current?.crew === crew.id) return json({ ok: true, joined: false, crew: this.detail(crew, caller, now) });
    if (!crew || crew.hidden || this.blockedEitherWay(caller, crew.owner)) {
      throw new HttpError(404, "crew_not_found", "no crew has that code");
    }
    if (this.sql.exec("SELECT 1 FROM crew_removals WHERE crew = ? AND code = ?", crew.id, caller).toArray().length > 0) {
      throw new HttpError(403, "removed_from_crew", "the crew's owner removed you from this crew");
    }
    if (current) throw new HttpError(409, "in_crew", "leave your crew first");
    // A public crew by id asks its owner; an invite code is the owner's consent and joins at once.
    if ("crew" in target) return this.requestToJoin(caller, crew, now);
    if (this.memberCount(crew.id) >= MAX_CREW_MEMBERS) {
      throw new HttpError(409, "crew_full", `a crew has at most ${MAX_CREW_MEMBERS} members`);
    }
    this.host.transaction(() => this.addMember(caller, crew.id, now));
    return json({ ok: true, joined: true, crew: this.detail(crew, caller, now) });
  }

  private async leaveRoute(req: Request, caller: string, now: number): Promise<Response> {
    await readBody(req, []);
    this.host.rateLimit("crewchange:" + caller, CREW_CHANGES_PER_MIN, now);
    let left = false;
    this.host.transaction(() => {
      left = this.leave(caller, now);
    });
    return json({ ok: true, left });
  }

  /**
   * Takes `code` out of their crew (call inside a transaction): the stint closes, a leaving owner hands
   * over to the longest-standing member (members blocked either way with the new owner leave too), and the
   * last member leaving deletes the crew. Minutes already credited stay with the crew. Returns whether
   * `code` was in a crew.
   */
  leave(code: string, now: number): boolean {
    const member = this.memberRow(code);
    if (!member) return false;
    this.sql.exec("DELETE FROM crew_members WHERE code = ?", code);
    this.sql.exec("UPDATE crew_stints SET left_at = ? WHERE code = ? AND left_at IS NULL", now, code);
    const crew = this.crewRow(member.crew);
    if (!crew) return true;
    const next = this.sql.exec<{ code: string }>(
      "SELECT code FROM crew_members WHERE crew = ? ORDER BY joined_at, rowid LIMIT 1", crew.id).toArray()[0];
    if (!next) {
      this.deleteCrew(crew.id, now);
    } else if (crew.owner === code) {
      this.sql.exec("UPDATE crews SET owner = ? WHERE id = ?", next.code, crew.id);
      const blocked = this.sql.exec<{ code: string }>(
        `SELECT code FROM crew_members WHERE crew = ?1 AND code IN (
           SELECT blocked FROM blocks WHERE blocker = ?2 UNION SELECT blocker FROM blocks WHERE blocked = ?2)`,
        crew.id, next.code).toArray();
      for (const b of blocked) this.leave(b.code, now);
    }
    return true;
  }

  /** Deletes a crew with no members left, or every member's membership (call inside a transaction). */
  private deleteCrew(id: string, now: number): void {
    this.sql.exec("UPDATE crew_stints SET left_at = ? WHERE crew = ? AND left_at IS NULL", now, id);
    this.sql.exec("DELETE FROM crew_members WHERE crew = ?", id);
    this.sql.exec("DELETE FROM crew_removals WHERE crew = ?", id);
    this.sql.exec("DELETE FROM crew_join_requests WHERE crew = ?", id);
    this.sql.exec("DELETE FROM crew_weeks WHERE crew = ?", id);
    this.sql.exec("DELETE FROM crew_results WHERE crew = ?", id);
    this.sql.exec("DELETE FROM crews WHERE id = ?", id);
  }

  /** POST /v1/crews/mine/members/{ref}/remove: the owner removes a member, who cannot join again. */
  private removeMember(caller: string, raw: string, now: number): Response {
    const ref = parseCode(raw, MEMBER_REF_RE, "member");
    this.host.rateLimit("crewchange:" + caller, CREW_CHANGES_PER_MIN, now);
    const { crew } = this.myCrew(caller);
    if (crew.owner !== caller) throw new HttpError(403, "not_owner", "only the crew's owner can remove members");
    const target = this.sql.exec<MemberRow>("SELECT * FROM crew_members WHERE ref = ? AND crew = ?", ref, crew.id).toArray()[0];
    if (!target) throw new HttpError(404, "member_not_found", "no member of your crew has that id");
    if (target.code === caller) throw new HttpError(400, "invalid_field", "leave the crew instead of removing yourself");
    this.host.transaction(() => {
      this.sql.exec("INSERT OR IGNORE INTO crew_removals (crew, code, created_at) VALUES (?, ?, ?)", crew.id, target.code, now);
      this.leave(target.code, now);
    });
    return json({ ok: true, removed: true, crew: this.detail(this.crewRow(crew.id)!, caller, now) });
  }

  // ---------- sessions and credit ----------

  private stintsOf(code: string, from: number, to: number): Stint[] {
    return this.sql.exec<{ crew: string; joined_at: number; left_at: number | null }>(
      "SELECT crew, joined_at, left_at FROM crew_stints WHERE code = ? AND joined_at < ? AND (left_at IS NULL OR left_at > ?) ORDER BY joined_at",
      code, to, from,
    ).toArray().map((r) => ({ crew: r.crew, joinedAt: r.joined_at, leftAt: r.left_at }));
  }

  private creditedOn(code: string, day: string): number {
    return this.sql.exec<{ n: number }>("SELECT COALESCE(SUM(minutes), 0) AS n FROM crew_day_credits WHERE code = ? AND day = ?", code, day).one().n;
  }

  private creditedInWeek(code: string, week: string): number {
    return this.sql.exec<{ n: number }>("SELECT COALESCE(SUM(minutes), 0) AS n FROM crew_day_credits WHERE code = ? AND week = ?", code, week).one().n;
  }

  /** Records one flag for the maintainer; a second of the same kind for the user and week is ignored. */
  private flag(code: string, crew: string | null, week: string, kind: FlagKind, detail: string, now: number): void {
    this.sql.exec(
      "INSERT OR IGNORE INTO crew_flags (code, crew, week, kind, detail, created_at) VALUES (?, ?, ?, ?, ?, ?)",
      code, crew, week, kind, detail, now,
    );
  }

  /** Counts an overlapping or future report toward the day's flag threshold. */
  private countBadReport(code: string, kind: "overlaps" | "future", now: number): void {
    const key = `${kind}:${code}:${utcDay(now)}`;
    const n = (this.badReports.get(key) ?? 0) + 1;
    this.badReports.set(key, n);
    if (this.badReports.size > 10_000) this.badReports.clear();
    const limit = kind === "overlaps" ? OVERLAP_FLAG_PER_DAY : FUTURE_FLAG_PER_DAY;
    if (n === limit) {
      this.flag(code, this.memberRow(code)?.crew ?? null, weekOf(now).id, kind, `${n} ${kind === "overlaps" ? "overlapping" : "future"} sessions on ${utcDay(now)}`, now);
    }
  }

  /** POST /v1/crews/sessions: credits each finished focus session to the crews of its time. */
  private async reportSessions(req: Request, caller: string, now: number): Promise<Response> {
    const list = parseSessionList(await readBody(req, SESSIONS_FIELDS, 8192));
    this.host.rateLimit("crewsessions:" + caller, CREW_SESSION_REPORTS_PER_MIN, now);
    const week = weekOf(now);
    const results: { status: SessionStatus; credited: number }[] = [];
    this.host.transaction(() => {
      for (const raw of list) results.push(this.creditSession(caller, raw, week, now));
    });
    const crew = this.memberRow(caller)?.crew ?? null;
    return json({
      ok: true, results, week,
      crewMinutes: crew ? this.weekMinutes(crew, week.id) : null,
      myMinutes: this.creditedInWeek(caller, week.id),
    });
  }

  private creditSession(code: string, raw: unknown, week: CrewWeek, now: number): { status: SessionStatus; credited: number } {
    const session = checkSession(raw, now);
    if (session === "invalid") return { status: "invalid", credited: 0 };
    if (session === "future") {
      this.countBadReport(code, "future", now);
      return { status: "future", credited: 0 };
    }
    const { start, end, minutes } = session;
    if (end <= week.startsAt) return { status: "week_closed", credited: 0 };
    const clash = this.sql.exec<{ start: number; end: number }>(
      "SELECT start, end FROM crew_sessions WHERE code = ? AND start < ? AND end > ?", code, end, start).toArray();
    if (clash.some((c) => c.start === start && c.end === end)) return { status: "duplicate", credited: 0 };
    if (clash.length > 0) {
      this.countBadReport(code, "overlaps", now);
      return { status: "overlap", credited: 0 };
    }
    const segments = sessionSegments(start, end, this.stintsOf(code, start, end), week.startsAt);
    if (segments.length === 0) {
      // In a crew for some of it, but only before the week opened: nothing left to credit.
      const before = this.stintsOf(code, start, end).length > 0;
      return { status: before ? "week_closed" : "no_crew", credited: 0 };
    }
    const shares = allocateMinutes(minutes, end - start, segments);
    let weekLeft = WEEKLY_CAP_MINUTES - this.creditedInWeek(code, week.id);
    const dayLeft = new Map<string, number>();
    let capped = false;
    let credited = 0;
    segments.forEach((seg, i) => {
      const left = dayLeft.get(seg.day) ?? DAILY_CAP_MINUTES - this.creditedOn(code, seg.day);
      let share = shares[i];
      if (share > left) {
        share = Math.max(0, left);
        capped = true;
        this.flag(code, seg.crew, week.id, "daily_cap", `daily cap reached on ${seg.day}`, now);
      }
      if (share > weekLeft) {
        share = Math.max(0, weekLeft);
        capped = true;
        this.flag(code, seg.crew, week.id, "weekly_cap", "weekly cap reached", now);
      }
      dayLeft.set(seg.day, left - share);
      weekLeft -= share;
      if (share <= 0) return;
      credited += share;
      this.sql.exec(
        `INSERT INTO crew_day_credits (code, crew, day, week, minutes) VALUES (?, ?, ?, ?, ?)
         ON CONFLICT (code, crew, day) DO UPDATE SET minutes = minutes + excluded.minutes`,
        code, seg.crew, seg.day, week.id, share,
      );
      this.sql.exec(
        `INSERT INTO crew_weeks (week, crew, minutes) VALUES (?, ?, ?)
         ON CONFLICT (week, crew) DO UPDATE SET minutes = minutes + excluded.minutes`,
        week.id, seg.crew, share,
      );
    });
    this.sql.exec("INSERT INTO crew_sessions (code, start, end, minutes, credited) VALUES (?, ?, ?, ?, ?)", code, start, end, minutes, credited);
    return { status: capped ? "capped" : "credited", credited };
  }

  /** Removes a user's credited minutes for an open week from every crew they gave them to. */
  private voidCredits(code: string, week: string): number {
    const rows = this.sql.exec<{ crew: string; minutes: number }>(
      "SELECT crew, SUM(minutes) AS minutes FROM crew_day_credits WHERE code = ? AND week = ? GROUP BY crew", code, week).toArray();
    let total = 0;
    for (const r of rows) {
      this.sql.exec("UPDATE crew_weeks SET minutes = MAX(0, minutes - ?) WHERE week = ? AND crew = ?", r.minutes, week, r.crew);
      total += r.minutes;
    }
    this.sql.exec("DELETE FROM crew_day_credits WHERE code = ? AND week = ?", code, week);
    return total;
  }

  // ---------- the weekly rollup ----------

  /**
   * Freezes every finished week that has not been frozen yet, oldest first: each crew placed 1 to 3
   * (`weekPlaces`, ties share a place) gets that place's medal and the award row. Idempotent
   * (crew_rollups), catches up several missed weeks, and is cheap once the current week is known done.
   */
  rollupIfDue(now: number): void {
    const current = weekOf(now).id;
    if (this.rolledFor === current) return;
    const last = previousWeek(now).id;
    const pending = this.sql.exec<{ week: string }>(
      `SELECT DISTINCT week FROM crew_weeks WHERE week < ? AND week NOT IN (SELECT week FROM crew_rollups) ORDER BY week`,
      current,
    ).toArray().map((r) => r.week);
    const known = this.sql.exec("SELECT 1 FROM crew_rollups WHERE week = ?", last).toArray().length > 0;
    if (!known && !pending.includes(last)) pending.push(last);
    this.host.transaction(() => {
      for (const week of pending) this.freeze(week, now);
    });
    this.rolledFor = current;
  }

  private freeze(week: string, now: number): void {
    if (this.sql.exec("SELECT 1 FROM crew_rollups WHERE week = ?", week).toArray().length > 0) return;
    const endsAt = weekFromId(week).endsAt;
    const places = new Map(this.placed(week).map((p) => [p.id, p.rank]));
    // Every crew's final standing, for its history: competition ranks over the visible crews, none for hidden ones.
    const all = this.sql.exec<{ crew: string; minutes: number; hidden: number }>(
      "SELECT w.crew, w.minutes, c.hidden FROM crew_weeks w JOIN crews c ON c.id = w.crew WHERE w.week = ? AND w.minutes > 0", week,
    ).toArray();
    const visible = all.filter((r) => !r.hidden).map((r) => r.minutes);
    for (const r of all) {
      const place = r.hidden ? null : places.get(r.crew) ?? 1 + visible.filter((m) => m > r.minutes).length;
      this.sql.exec("INSERT OR REPLACE INTO crew_results (week, crew, place, minutes) VALUES (?, ?, ?, ?)", week, r.crew, place, r.minutes);
    }
    for (const r of this.placed(week)) {
      this.sql.exec(
        "INSERT INTO crew_awards (week, rank, crew, minutes, name, frame, emblem, color) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        week, r.rank, r.id, r.minutes, r.name, r.frame, r.emblem, r.color,
      );
      const medal = laurelOfRank(r.rank)!;
      this.sql.exec(`UPDATE crews SET ${medal} = ${medal} + 1, medals_at = MAX(COALESCE(medals_at, 0), ?) WHERE id = ?`, endsAt, r.id);
    }
    this.sql.exec("INSERT INTO crew_rollups (week, rolled_at) VALUES (?, ?)", week, now);
  }

  /** Drops crews data past its retention (sessions and closed stints, old credits and totals). Once a UTC day. */
  sweep(now: number): void {
    const today = utcDay(now);
    if (this.sweptOn === today) return;
    const oldWeek = weekOf(now - CREW_WEEK_RETENTION_S).id;
    this.host.transaction(() => {
      this.sql.exec("DELETE FROM crew_sessions WHERE end < ?", now - CREW_SESSION_RETENTION_S);
      this.sql.exec("DELETE FROM crew_join_requests WHERE created_at <= ?", now - JOIN_REQUEST_TTL_S);
      this.sql.exec("DELETE FROM crew_stints WHERE left_at IS NOT NULL AND left_at < ?", now - CREW_SESSION_RETENTION_S);
      this.sql.exec("DELETE FROM crew_day_credits WHERE week < ?", oldWeek);
      this.sql.exec("DELETE FROM crew_weeks WHERE week < ?", oldWeek);
      this.sql.exec("DELETE FROM crew_results WHERE week < ?", oldWeek);
    });
    this.sweptOn = today;
    this.badReports.clear();
  }

  // ---------- reports and blocks ----------

  /** The member of a crew the caller may see, by ref. */
  private visibleMember(crew: CrewRow, raw: unknown): MemberRow & { name: string } {
    const ref = parseCode(raw, MEMBER_REF_RE, "member");
    const row = this.sql.exec<MemberRow & { name: string }>(
      "SELECT m.*, u.name FROM crew_members m JOIN users u ON u.code = m.code WHERE m.ref = ? AND m.crew = ?", ref, crew.id,
    ).toArray()[0];
    if (!row) throw new HttpError(404, "member_not_found", "no member of that crew has that id");
    return row;
  }

  /** POST /v1/crews/reports: a report about a crew, or one of its members, for the maintainer. */
  private async report(req: Request, caller: string, now: number): Promise<Response> {
    const body = await readBody(req, CREW_REPORT_FIELDS);
    const { reason, note } = parseCrewReport(body);
    const crew = this.viewable(String(body.crew ?? ""), caller, now);
    const member = body.member === undefined || body.member === null ? null : this.visibleMember(crew, body.member);
    if (member?.code === caller) throw new HttpError(400, "self_report", "you cannot report yourself");
    this.host.rateLimit("report:" + caller, REPORTS_PER_MIN, now);
    const open = this.sql.exec<{ id: number }>(
      "SELECT id FROM crew_reports WHERE reporter = ? AND crew = ? AND member IS ? AND resolved_at IS NULL",
      caller, crew.id, member?.code ?? null).toArray()[0];
    if (open) {
      this.sql.exec("UPDATE crew_reports SET reason = ?, note = ?, crew_name = ?, member_name = ?, created_at = ? WHERE id = ?",
        reason, note, crew.name, member?.name ?? null, now, open.id);
      return json({ ok: true, created: false });
    }
    const today = this.sql.exec<{ n: number }>(
      "SELECT COUNT(*) AS n FROM crew_reports WHERE reporter = ? AND created_at > ?", caller, now - 86_400).one().n;
    if (today >= MAX_REPORTS_PER_DAY) throw new HttpError(429, "report_limit", `at most ${MAX_REPORTS_PER_DAY} reports a day`);
    this.sql.exec(
      `INSERT INTO crew_reports (reporter, crew, member, reason, note, crew_name, member_name, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      caller, crew.id, member?.code ?? null, reason, note, crew.name, member?.name ?? null, now,
    );
    return json({ ok: true, created: true }, 201);
  }

  /** POST /v1/crews/block: blocks a member of a crew, by ref, as POST /v1/blocks would. */
  private async blockRoute(req: Request, caller: string, now: number): Promise<Response> {
    const body = await readBody(req, CREW_BLOCK_FIELDS);
    const crew = this.viewable(String(body.crew ?? ""), caller, now);
    // The owner can also block someone asking to join, by the request's ref.
    const ref = parseCode(body.member, MEMBER_REF_RE, "member");
    const requester = crew.owner === caller
      ? this.sql.exec<{ code: string }>("SELECT code FROM crew_join_requests WHERE ref = ? AND crew = ?", ref, crew.id).toArray()[0]?.code
      : undefined;
    const code = requester ?? this.visibleMember(crew, ref).code;
    if (code === caller) throw new HttpError(400, "self_block", "you cannot block yourself");
    return json({ ok: true, blocked: this.host.block(caller, code, now) });
  }

  /**
   * A new block (call inside the block's transaction): the owner blocking a member removes them for good;
   * a member blocking the owner leaves. Other blocks only hide the two from each other on crew pages.
   */
  onBlock(blocker: string, blocked: string, now: number): void {
    this.sql.exec(
      `DELETE FROM crew_join_requests WHERE (code = ?1 AND crew IN (SELECT id FROM crews WHERE owner = ?2))
         OR (code = ?2 AND crew IN (SELECT id FROM crews WHERE owner = ?1))`, blocker, blocked);
    const a = this.memberRow(blocker);
    const b = this.memberRow(blocked);
    if (!a || !b || a.crew !== b.crew) return;
    const crew = this.crewRow(a.crew);
    if (!crew) return;
    if (crew.owner === blocker) {
      this.sql.exec("INSERT OR IGNORE INTO crew_removals (crew, code, created_at) VALUES (?, ?, ?)", crew.id, blocked, now);
      this.leave(blocked, now);
    } else if (crew.owner === blocked) {
      this.leave(blocker, now);
    }
  }

  // ---------- account lifecycle ----------

  /** A ban (call inside its transaction): the user leaves their crew and loses the open week's minutes. */
  onBan(code: string, now: number): void {
    this.sql.exec("DELETE FROM crew_join_requests WHERE code = ?", code);
    this.voidCredits(code, weekOf(now).id);
    this.leave(code, now);
  }

  /** Account deletion (call inside its transaction): every crews row about the user goes. */
  purgeUser(code: string, now: number): void {
    this.leave(code, now);
    this.sql.exec("DELETE FROM crew_join_requests WHERE code = ?", code);
    this.sql.exec("DELETE FROM crew_stints WHERE code = ?", code);
    this.sql.exec("DELETE FROM crew_sessions WHERE code = ?", code);
    this.sql.exec("DELETE FROM crew_day_credits WHERE code = ?", code);
    this.sql.exec("DELETE FROM crew_removals WHERE code = ?", code);
    this.sql.exec("DELETE FROM crew_reports WHERE reporter = ? OR member = ?", code, code);
    this.sql.exec("DELETE FROM crew_flags WHERE code = ?", code);
  }

  /**
   * Signing in folds an anonymous user into an account (call inside its transaction, before `from` is
   * purged): the crew membership moves when the account has none, and sessions, credits, removals,
   * reports and flags follow, so a sign-in never changes a crew's minutes.
   */
  foldInto(from: string, to: string, now: number): void {
    const fromMember = this.memberRow(from);
    if (fromMember && !this.memberRow(to)) {
      this.sql.exec("UPDATE crew_members SET code = ? WHERE code = ?", to, from);
      this.sql.exec("UPDATE crews SET owner = ? WHERE owner = ?", to, from);
    } else if (fromMember) {
      this.leave(from, now);
    }
    this.sql.exec("INSERT OR IGNORE INTO crew_stints (code, crew, joined_at, left_at) SELECT ?, crew, joined_at, left_at FROM crew_stints WHERE code = ?", to, from);
    this.sql.exec("INSERT OR IGNORE INTO crew_sessions (code, start, end, minutes, credited) SELECT ?, start, end, minutes, credited FROM crew_sessions WHERE code = ?", to, from);
    this.sql.exec(
      `INSERT INTO crew_day_credits (code, crew, day, week, minutes) SELECT ?, crew, day, week, minutes FROM crew_day_credits WHERE code = ? AND true
       ON CONFLICT (code, crew, day) DO UPDATE SET minutes = minutes + excluded.minutes`, to, from);
    this.sql.exec("INSERT OR IGNORE INTO crew_removals (crew, code, created_at) SELECT crew, ?, created_at FROM crew_removals WHERE code = ?", to, from);
    if (!this.memberRow(to)) this.sql.exec("UPDATE OR IGNORE crew_join_requests SET code = ? WHERE code = ?", to, from);
    this.sql.exec("DELETE FROM crew_join_requests WHERE code = ?", from);
    this.sql.exec("UPDATE crew_reports SET reporter = ? WHERE reporter = ?", to, from);
    this.sql.exec("UPDATE crew_reports SET member = ? WHERE member = ?", to, from);
    this.sql.exec("UPDATE OR IGNORE crew_flags SET code = ? WHERE code = ?", to, from);
    // What the fold could not move goes with `from` when the Hub purges it.
    this.sql.exec("DELETE FROM crew_stints WHERE code = ?", from);
    this.sql.exec("DELETE FROM crew_sessions WHERE code = ?", from);
    this.sql.exec("DELETE FROM crew_day_credits WHERE code = ?", from);
  }

  // ---------- the maintainer ----------

  /** Counts for GET /v1/admin/stats. */
  stats(now: number) {
    const count = (q: string, ...a: SqlStorageValue[]) => this.sql.exec<{ n: number }>(q, ...a).one().n;
    return {
      total: count("SELECT COUNT(*) AS n FROM crews"),
      public: count("SELECT COUNT(*) AS n FROM crews WHERE visibility = 'public'"),
      hidden: count("SELECT COUNT(*) AS n FROM crews WHERE hidden = 1"),
      members: count("SELECT COUNT(*) AS n FROM crew_members"),
      activeThisWeek: count("SELECT COUNT(*) AS n FROM crew_weeks WHERE week = ? AND minutes > 0", weekOf(now).id),
      openReports: count("SELECT COUNT(*) AS n FROM crew_reports WHERE resolved_at IS NULL"),
      openFlags: count("SELECT COUNT(*) AS n FROM crew_flags WHERE resolved_at IS NULL"),
    };
  }

  private adminTarget(raw: string): CrewRow {
    const id = parseCode(raw, CREW_ID_RE, "crew");
    const crew = this.crewRow(id);
    if (!crew) throw new HttpError(404, "crew_not_found", "no crew has that id");
    return crew;
  }

  private adminReports(openOnly: boolean): Response {
    const rows = this.sql.exec<{
      id: number; reporter: string; crew: string; member: string | null; reason: string; note: string | null;
      crew_name: string; member_name: string | null; created_at: number; resolved_at: number | null; resolution: string | null;
      current_name: string | null; current_member_name: string | null;
    }>(
      `SELECT r.*, c.name AS current_name, u.name AS current_member_name FROM crew_reports r
       LEFT JOIN crews c ON c.id = r.crew LEFT JOIN users u ON u.code = r.member
       WHERE ? = 0 OR r.resolved_at IS NULL ORDER BY r.created_at DESC, r.id DESC LIMIT ?`,
      openOnly ? 1 : 0, ADMIN_PAGE,
    ).toArray();
    return json({
      ok: true,
      reports: rows.map((r) => ({
        id: r.id, createdAt: r.created_at, reason: r.reason, note: r.note, resolvedAt: r.resolved_at, resolution: r.resolution,
        reporter: r.reporter,
        crew: { id: r.crew, name: r.crew_name, currentName: r.current_name },
        member: r.member === null ? null : { code: r.member, name: r.member_name, currentName: r.current_member_name },
      })),
    });
  }

  private adminFlags(openOnly: boolean): Response {
    const rows = this.sql.exec<{
      id: number; code: string; crew: string | null; week: string; kind: string; detail: string | null;
      created_at: number; resolved_at: number | null; resolution: string | null; name: string | null; crew_name: string | null;
    }>(
      `SELECT f.*, u.name, c.name AS crew_name FROM crew_flags f LEFT JOIN users u ON u.code = f.code LEFT JOIN crews c ON c.id = f.crew
       WHERE ? = 0 OR f.resolved_at IS NULL ORDER BY f.created_at DESC, f.id DESC LIMIT ?`,
      openOnly ? 1 : 0, ADMIN_PAGE,
    ).toArray();
    return json({
      ok: true,
      flags: rows.map((r) => ({
        id: r.id, createdAt: r.created_at, week: r.week, kind: r.kind, detail: r.detail, resolvedAt: r.resolved_at,
        resolution: r.resolution, user: { code: r.code, name: r.name }, crew: r.crew === null ? null : { id: r.crew, name: r.crew_name },
        weekMinutes: this.creditedInWeek(r.code, r.week),
      })),
    });
  }

  private resolveRow(table: "crew_reports" | "crew_flags", id: number, resolution: string, now: number, what: string): Response {
    const done = this.sql.exec(`UPDATE ${table} SET resolved_at = ?, resolution = ? WHERE id = ? AND resolved_at IS NULL`, now, resolution, id).rowsWritten > 0;
    if (!done && this.sql.exec(`SELECT 1 FROM ${table} WHERE id = ?`, id).toArray().length === 0) {
      throw new HttpError(404, `${what}_not_found`, `no ${what} has that id`);
    }
    return json({ ok: true, dismissed: done });
  }

  /**
   * POST /v1/admin/crews/flags/{id}/void: removes the flagged user's credited minutes for the flag's week
   * while it is open, and resolves the flag. A frozen week keeps its board (`frozen: true`, nothing voided).
   */
  private voidFlag(id: number, now: number): Response {
    const flag = this.sql.exec<{ code: string; week: string }>("SELECT code, week FROM crew_flags WHERE id = ?", id).toArray()[0];
    if (!flag) throw new HttpError(404, "flag_not_found", "no flag has that id");
    const frozen = flag.week !== weekOf(now).id;
    let voided = 0;
    this.host.transaction(() => {
      if (!frozen) voided = this.voidCredits(flag.code, flag.week);
      this.sql.exec("UPDATE crew_flags SET resolved_at = ?, resolution = 'voided' WHERE id = ?", now, id);
    });
    return json({ ok: true, voided, frozen });
  }

  /** GET /v1/admin/crews/{id}: the crew with its members' friend codes and minutes. */
  private adminView(raw: string, now: number): Response {
    const crew = this.adminTarget(raw);
    const week = weekOf(now).id;
    const members = this.sql.exec<{ code: string; ref: string; name: string; joined_at: number; show_pet: number }>(
      `SELECT m.code, m.ref, u.name, m.joined_at, m.show_pet FROM crew_members m JOIN users u ON u.code = m.code
       WHERE m.crew = ? ORDER BY m.joined_at, m.rowid`, crew.id).toArray();
    return json({
      ok: true,
      crew: {
        ...this.summary(crew, now), owner: crew.owner, inviteCode: crew.invite_code, hidden: crew.hidden === 1,
        createdAt: crew.created_at, medals: { gold: crew.gold, silver: crew.silver, bronze: crew.bronze },
        members: members.map((m) => ({
          code: m.code, ref: m.ref, name: m.name, joinedAt: m.joined_at, showPet: m.show_pet === 1,
          weekMinutes: this.sql.exec<{ n: number }>(
            "SELECT COALESCE(SUM(minutes), 0) AS n FROM crew_day_credits WHERE code = ? AND crew = ? AND week = ?", m.code, crew.id, week).one().n,
        })),
      },
    });
  }

  private resolveCrewReports(crew: string, resolution: string, now: number): void {
    this.sql.exec("UPDATE crew_reports SET resolved_at = ?, resolution = ? WHERE crew = ? AND member IS NULL AND resolved_at IS NULL",
      now, resolution, crew);
  }

  /**
   * POST /v1/admin/crews/{id}/rename: the name becomes "Crew" plus the id's first four characters (the
   * whole id if that is taken), the description is cleared, the old name is held, and open reports about
   * the crew itself are resolved.
   */
  private adminRename(raw: string, now: number): Response {
    const crew = this.adminTarget(raw);
    let name = `Crew ${crew.id.slice(0, 4)}`;
    const taken = (n: string) => this.sql.exec<{ id: string }>("SELECT id FROM crews WHERE name_key = ?", nameKey(n)).toArray()
      .some((r) => r.id !== crew.id);
    if (taken(name)) name = `Crew ${crew.id}`;
    this.host.transaction(() => {
      if (crew.name_key !== nameKey(name)) {
        this.sql.exec("INSERT OR IGNORE INTO crew_name_holds (name_key, created_at) VALUES (?, ?)", crew.name_key, now);
      }
      this.sql.exec("UPDATE crews SET name = ?, name_key = ?, description = '' WHERE id = ?", name, nameKey(name), crew.id);
      this.resolveCrewReports(crew.id, "renamed", now);
    });
    return json({ ok: true, crew: this.summary(this.crewRow(crew.id)!, now) });
  }

  /** POST (hide) or DELETE (show again) /v1/admin/crews/{id}/hide. */
  private adminHide(raw: string, hidden: boolean, now: number): Response {
    const crew = this.adminTarget(raw);
    this.host.transaction(() => {
      this.sql.exec("UPDATE crews SET hidden = ? WHERE id = ?", hidden ? 1 : 0, crew.id);
      if (hidden) {
        this.resolveCrewReports(crew.id, "hidden", now);
        this.sql.exec("DELETE FROM crew_join_requests WHERE crew = ?", crew.id);
      }
    });
    return json({ ok: true, hidden, changed: (crew.hidden === 1) !== hidden });
  }

  /** DELETE /v1/admin/crews/{id}: every member leaves and the crew is gone; its past awards stay as recorded. */
  private adminDelete(raw: string, now: number): Response {
    const crew = this.adminTarget(raw);
    this.host.transaction(() => {
      this.deleteCrew(crew.id, now);
      this.resolveCrewReports(crew.id, "deleted", now);
    });
    return json({ ok: true, deleted: true });
  }
}
