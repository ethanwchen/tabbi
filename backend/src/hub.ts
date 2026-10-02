/**
 * The Hub: one SQLite-backed Durable Object that owns all state (users, friends, presence, parties).
 *
 * Why a single object: it gives strongly consistent, transactional state (symmetric friendships and
 * party capacity cannot race), and on the Workers Free plan one always-warm object costs at most
 * 86,400 s x 128 MB = 11,059 GB-s/day, inside the 13,000 GB-s/day allowance. Sharding into many
 * objects would multiply that duration. See README.md "Free-tier math".
 *
 * Rate-limit counters live in memory: there is exactly one instance, so they are exact while it is
 * alive, and keeping them out of SQLite saves a billed row write on every request.
 */
import { DurableObject } from "cloudflare:workers";
import {
  HttpError, MAX_FRIENDS, MAX_PARTY_MEMBERS, PARTY_IDLE_EXPIRY_S, RATE_LIMIT_PER_MIN, REGISTER_PER_MIN, FRIEND_CODE_RE, TOKEN_RE,
  newCode, newToken, nowS, parseFriendCode, readBody, sha256Hex,
} from "./lib";
import { PROFILE_FIELDS, Profile, applyProfilePatch, defaultProfile, parseProfilePatch, sameProfile } from "./profile";
import { json } from "./http";
import { PRESENCE_FIELDS, Presence, heartbeatSeconds, isOnline, parseHeartbeat, presenceChanged, publicPresence } from "./presence";
import { JOIN_FIELDS, PARTY_TOUCH_S, PartySession, SESSION_FIELDS, parseJoin, parseSession, partyExpired } from "./party";

export interface Env {
  HUB: DurableObjectNamespace<Hub>;
}

const SCHEMA = `
CREATE TABLE IF NOT EXISTS users (
  code        TEXT PRIMARY KEY,
  token_hash  TEXT NOT NULL UNIQUE,
  name        TEXT NOT NULL,
  pet_name    TEXT NOT NULL,
  species     TEXT NOT NULL,
  breed       TEXT NOT NULL,
  colors      TEXT NOT NULL,
  costume     TEXT NOT NULL,
  accessories TEXT NOT NULL,
  points      INTEGER NOT NULL,
  level       INTEGER NOT NULL,
  created_at  INTEGER NOT NULL
);
-- Friendships are symmetric and stored in both directions, so "my friends" is one indexed range scan.
CREATE TABLE IF NOT EXISTS friends (
  a          TEXT NOT NULL,
  b          TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (a, b)
) WITHOUT ROWID;
-- Last persisted heartbeat per user. The live copy is in Hub memory; see Hub.heartbeat for when it is flushed.
CREATE TABLE IF NOT EXISTS presence (
  code            TEXT PRIMARY KEY,
  status          TEXT NOT NULL,
  method          TEXT,
  phase_ends_at   INTEGER,
  session_minutes INTEGER NOT NULL,
  today_minutes   INTEGER NOT NULL,
  streak_days     INTEGER NOT NULL,
  last_seen       INTEGER NOT NULL
) WITHOUT ROWID;
-- A party and its optional shared session (all three session columns are set together or all null).
CREATE TABLE IF NOT EXISTS parties (
  code                  TEXT PRIMARY KEY,
  host                  TEXT NOT NULL,
  created_at            INTEGER NOT NULL,
  last_active           INTEGER NOT NULL,
  session_method        TEXT,
  session_phase_ends_at INTEGER,
  session_started_at    INTEGER
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS parties_by_last_active ON parties (last_active);
-- Keyed by user: a user is in at most one party at a time. A rowid table on purpose: the rowid breaks
-- ties between members who joined in the same second, so join order is stable.
CREATE TABLE IF NOT EXISTS party_members (
  code      TEXT PRIMARY KEY,
  party     TEXT NOT NULL,
  joined_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS party_members_by_party ON party_members (party, joined_at);
`;

/** Unchanged heartbeats are flushed to SQLite at most this often, so a restart loses little. */
const PRESENCE_FLUSH_S = 600;

interface UserRow extends Record<string, SqlStorageValue> {
  code: string;
  token_hash: string;
  name: string;
  pet_name: string;
  species: string;
  breed: string;
  colors: string;
  costume: string;
  accessories: string;
  points: number;
  level: number;
  created_at: number;
}

function rowToProfile(r: UserRow): Profile {
  return {
    code: r.code,
    name: r.name,
    petName: r.pet_name,
    species: r.species,
    breed: r.breed,
    colors: JSON.parse(r.colors) as string[],
    costume: r.costume,
    accessories: JSON.parse(r.accessories) as string[],
    points: r.points,
    level: r.level,
  };
}

interface PresenceRow extends Record<string, SqlStorageValue> {
  status: string;
  method: string | null;
  phase_ends_at: number | null;
  session_minutes: number;
  today_minutes: number;
  streak_days: number;
  last_seen: number;
}

/** Reads the presence columns of a row (which may come from a LEFT JOIN, so `status` can be null). */
function rowToPresence(r: Partial<PresenceRow>): Presence | null {
  if (r.status == null) return null;
  return {
    status: r.status,
    method: r.method ?? null,
    phaseEndsAt: r.phase_ends_at ?? null,
    sessionMinutes: r.session_minutes ?? 0,
    todayMinutes: r.today_minutes ?? 0,
    streakDays: r.streak_days ?? 0,
    lastSeen: r.last_seen ?? 0,
  };
}

function bearer(req: Request): string | null {
  const m = /^Bearer\s+(\S+)$/i.exec((req.headers.get("Authorization") ?? "").trim());
  return m ? m[1] : null;
}

interface Caller {
  code: string;
  tokenHash: string;
  profile: Profile;
}

export class Hub extends DurableObject<Env> {
  private sql: SqlStorage;
  private windows = new Map<string, { minute: number; count: number }>();
  /**
   * Live presence by friend code, plus when each entry was last written to SQLite. Heartbeats update
   * this map every time but write a row only on a visible change or every PRESENCE_FLUSH_S, which keeps
   * row writes far below the free-tier allowance. Entries missing here are read from SQLite.
   */
  private live = new Map<string, { presence: Presence; flushedAt: number }>();

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    this.sql.exec(SCHEMA);
  }

  async fetch(req: Request): Promise<Response> {
    try {
      return await this.route(req);
    } catch (e) {
      if (e instanceof HttpError) return json({ ok: false, error: e.error, message: e.message }, e.status, e.headers);
      console.error(e);
      return json({ ok: false, error: "internal", message: "internal error" }, 500);
    }
  }

  private async route(req: Request): Promise<Response> {
    const url = new URL(req.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";
    const method = req.method.toUpperCase();
    const now = nowS();

    if (path === "/v1/register" && method === "POST") {
      const token = bearer(req);
      if (token) {
        const caller = await this.authenticate(req, now);
        return this.updateProfile(req, caller, true);
      }
      this.rateLimit("ip:" + (req.headers.get("CF-Connecting-IP") ?? "unknown"), REGISTER_PER_MIN, now);
      return this.register(req, now);
    }

    const caller = await this.authenticate(req, now);

    if (path === "/v1/me" && method === "GET") return json({ ok: true, profile: caller.profile });
    if (path === "/v1/me" && method === "PATCH") return this.updateProfile(req, caller, false);
    if (path === "/v1/me" && method === "DELETE") return this.deleteMe(caller);

    if (path === "/v1/friends" && method === "GET") return this.listFriends(caller, now);
    if (path === "/v1/friends" && method === "POST") return this.addFriend(req, caller, now);
    const friendPath = /^\/v1\/friends\/([^/]+)$/.exec(path);
    if (friendPath && method === "DELETE") return this.removeFriend(caller, friendPath[1]);

    if (path === "/v1/presence" && method === "POST") return this.heartbeat(req, caller, now);

    if (path === "/v1/party" && method === "GET") return this.getParty(caller, now);
    if (path === "/v1/party" && method === "POST") return this.createParty(req, caller, now);
    if (path === "/v1/party/join" && method === "POST") return this.joinParty(req, caller, now);
    if (path === "/v1/party/leave" && method === "POST") return this.leavePartyRoute(req, caller, now);
    if (path === "/v1/party/session" && method === "POST") return this.startSession(req, caller, now);
    if (path === "/v1/party/session" && method === "DELETE") return this.endSession(caller, now);

    throw new HttpError(404, "not_found", "not found");
  }

  // ---------- auth + rate limiting ----------

  /** Resolves the caller from the Bearer token (rate limited per token, even when the token is bad). */
  private async authenticate(req: Request, now: number): Promise<Caller> {
    const token = bearer(req);
    if (!token || !TOKEN_RE.test(token)) {
      this.rateLimit("ip:" + (req.headers.get("CF-Connecting-IP") ?? "unknown"), RATE_LIMIT_PER_MIN, now);
      throw new HttpError(401, "unauthorized", "missing or invalid token");
    }
    const tokenHash = await sha256Hex(token);
    this.rateLimit("t:" + tokenHash, RATE_LIMIT_PER_MIN, now);
    const row = this.sql.exec<UserRow>("SELECT * FROM users WHERE token_hash = ?", tokenHash).toArray()[0];
    if (!row) throw new HttpError(401, "unauthorized", "missing or invalid token");
    return { code: row.code, tokenHash, profile: rowToProfile(row) };
  }

  /** Fixed one-minute window per identity. Old windows are dropped lazily when the minute rolls over. */
  private rateLimit(id: string, perMinute: number, now: number): void {
    const minute = Math.floor(now / 60);
    if (this.windows.size > 10_000) {
      for (const [k, w] of this.windows) if (w.minute !== minute) this.windows.delete(k);
    }
    const w = this.windows.get(id);
    const count = w && w.minute === minute ? w.count + 1 : 1;
    this.windows.set(id, { minute, count });
    if (count > perMinute) {
      const retry = Math.max(1, (minute + 1) * 60 - now);
      throw new HttpError(429, "rate_limited", "too many requests", { "Retry-After": String(retry) });
    }
  }

  // ---------- profile ----------

  private async register(req: Request, now: number): Promise<Response> {
    const patch = parseProfilePatch(await readBody(req, PROFILE_FIELDS));
    let code = newCode(8);
    for (let i = 0; i < 20 && this.userExists(code); i++) code = newCode(8);
    if (this.userExists(code)) throw new HttpError(503, "unavailable", "could not allocate a code, retry");
    const profile = applyProfilePatch(defaultProfile(code), patch);
    const token = newToken();
    this.sql.exec(
      `INSERT INTO users (code, token_hash, name, pet_name, species, breed, colors, costume, accessories, points, level, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      code, await sha256Hex(token), profile.name, profile.petName, profile.species, profile.breed,
      JSON.stringify(profile.colors), profile.costume, JSON.stringify(profile.accessories),
      profile.points, profile.level, now,
    );
    return json({ ok: true, token, code, profile }, 201);
  }

  /** PATCH /v1/me, and POST /v1/register with a valid token (idempotent re-register). */
  private async updateProfile(req: Request, caller: Caller, isRegister: boolean): Promise<Response> {
    const patch = parseProfilePatch(await readBody(req, PROFILE_FIELDS));
    const next = applyProfilePatch(caller.profile, patch);
    // Write only on change: SQLite row writes are the scarce free-tier resource.
    if (!sameProfile(next, caller.profile)) {
      this.sql.exec(
        `UPDATE users SET name = ?, pet_name = ?, species = ?, breed = ?, colors = ?, costume = ?,
           accessories = ?, points = ?, level = ? WHERE code = ?`,
        next.name, next.petName, next.species, next.breed, JSON.stringify(next.colors), next.costume,
        JSON.stringify(next.accessories), next.points, next.level, caller.code,
      );
    }
    return json(isRegister ? { ok: true, code: caller.code, profile: next } : { ok: true, profile: next });
  }

  private deleteMe(caller: Caller): Response {
    const now = nowS();
    this.ctx.storage.transactionSync(() => {
      this.leaveParty(caller.code, now);
      this.sql.exec("DELETE FROM users WHERE code = ?", caller.code);
      // Both directions via the primary key: the reverse rows are found through my own friend list.
      this.sql.exec("DELETE FROM friends WHERE b = ? AND a IN (SELECT b FROM friends WHERE a = ?)", caller.code, caller.code);
      this.sql.exec("DELETE FROM friends WHERE a = ?", caller.code);
      this.sql.exec("DELETE FROM presence WHERE code = ?", caller.code);
    });
    this.live.delete(caller.code);
    return json({ ok: true });
  }

  private userExists(code: string): boolean {
    return FRIEND_CODE_RE.test(code) && this.sql.exec("SELECT 1 FROM users WHERE code = ?", code).toArray().length > 0;
  }

  // ---------- friends ----------

  private listFriends(caller: Caller, now: number): Response {
    const rows = this.sql.exec<UserRow & Partial<PresenceRow> & { since: number; party_code: string | null; party_size: number | null }>(
      `SELECT u.*, f.created_at AS since, p.status, p.method, p.phase_ends_at, p.session_minutes,
         p.today_minutes, p.streak_days, p.last_seen, pa.code AS party_code,
         (SELECT COUNT(*) FROM party_members m2 WHERE m2.party = pa.code) AS party_size
       FROM friends f JOIN users u ON u.code = f.b LEFT JOIN presence p ON p.code = f.b
         LEFT JOIN party_members m ON m.code = f.b
         LEFT JOIN parties pa ON pa.code = m.party AND pa.last_active > ?
       WHERE f.a = ? ORDER BY u.name COLLATE NOCASE, u.code`,
      now - PARTY_IDLE_EXPIRY_S, caller.code,
    ).toArray();
    const friends = rows.map((r) => {
      const presence = this.live.get(r.code)?.presence ?? rowToPresence(r);
      return {
        profile: rowToProfile(r),
        since: r.since,
        presence: publicPresence(presence, now),
        online: isOnline(presence, now),
        party: r.party_code ? { code: r.party_code, size: r.party_size ?? 0 } : null,
      };
    });
    return json({ ok: true, friends });
  }

  /** Symmetric add by friend code. Adding someone who is already a friend is a no-op success. */
  private async addFriend(req: Request, caller: Caller, now: number): Promise<Response> {
    const body = await readBody(req, ["code"]);
    const code = parseFriendCode(body.code);
    if (code === caller.code) throw new HttpError(400, "self_friend", "you cannot add yourself");
    const row = this.sql.exec<UserRow>("SELECT * FROM users WHERE code = ?", code).toArray()[0];
    if (!row) throw new HttpError(404, "unknown_code", "no one has that code");
    const already = this.sql.exec("SELECT 1 FROM friends WHERE a = ? AND b = ?", caller.code, code).toArray().length > 0;
    if (!already) {
      if (this.friendCount(caller.code) >= MAX_FRIENDS) {
        throw new HttpError(409, "friend_limit", `you already have ${MAX_FRIENDS} friends`);
      }
      if (this.friendCount(code) >= MAX_FRIENDS) {
        throw new HttpError(409, "their_friend_limit", `they already have ${MAX_FRIENDS} friends`);
      }
      this.ctx.storage.transactionSync(() => {
        this.sql.exec("INSERT OR IGNORE INTO friends (a, b, created_at) VALUES (?, ?, ?), (?, ?, ?)",
          caller.code, code, now, code, caller.code, now);
      });
    }
    return json({ ok: true, added: !already, friend: rowToProfile(row) });
  }

  /** Symmetric remove. Removing someone who is not a friend is a no-op success (`removed: false`). */
  private removeFriend(caller: Caller, raw: string): Response {
    const code = parseFriendCode(raw);
    let removed = false;
    this.ctx.storage.transactionSync(() => {
      removed = this.sql.exec("DELETE FROM friends WHERE a = ? AND b = ?", caller.code, code).rowsWritten > 0;
      this.sql.exec("DELETE FROM friends WHERE a = ? AND b = ?", code, caller.code);
    });
    return json({ ok: true, removed });
  }

  private friendCount(code: string): number {
    return this.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM friends WHERE a = ?", code).one().n;
  }

  // ---------- presence ----------

  private presenceOf(code: string): Presence | null {
    const live = this.live.get(code);
    if (live) return live.presence;
    const row = this.sql.exec<PresenceRow>("SELECT * FROM presence WHERE code = ?", code).toArray()[0];
    return row ? rowToPresence(row) : null;
  }

  /**
   * POST /v1/presence. Always updates the live copy; writes the row only when friends would see a
   * different status, method, phase or streak, or when the last write is PRESENCE_FLUSH_S old.
   */
  private async heartbeat(req: Request, caller: Caller, now: number): Promise<Response> {
    const body = await readBody(req, PRESENCE_FIELDS);
    const live = this.live.get(caller.code);
    const prev = live?.presence ?? this.presenceOf(caller.code);
    const next = parseHeartbeat(body, prev, now);
    let flushedAt = live?.flushedAt ?? 0;
    if (!live || !prev || presenceChanged(prev, next) || now - flushedAt >= PRESENCE_FLUSH_S) {
      this.sql.exec(
        `INSERT OR REPLACE INTO presence
           (code, status, method, phase_ends_at, session_minutes, today_minutes, streak_days, last_seen)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        caller.code, next.status, next.method, next.phaseEndsAt, next.sessionMinutes, next.todayMinutes,
        next.streakDays, next.lastSeen,
      );
      flushedAt = now;
    }
    this.live.set(caller.code, { presence: next, flushedAt });
    return json({ ok: true, presence: next, heartbeatSeconds: heartbeatSeconds(next.status) });
  }

  // ---------- parties ----------

  /** GET /v1/party: the caller's party, or `null`. A member's poll counts as party activity. */
  private getParty(caller: Caller, now: number): Response {
    const code = this.currentParty(caller.code, now);
    if (code) this.touchParty(code, now, false);
    return json({ ok: true, party: code ? this.partyView(code, now) : null });
  }

  /** POST /v1/party: creates a party with the caller as host, leaving any party they were in. */
  private async createParty(req: Request, caller: Caller, now: number): Promise<Response> {
    await readBody(req, []);
    this.sweepExpiredParties(now);
    let code = newCode(6);
    for (let i = 0; i < 20 && this.partyExists(code); i++) code = newCode(6);
    if (this.partyExists(code)) throw new HttpError(503, "unavailable", "could not allocate a party code, retry");
    this.ctx.storage.transactionSync(() => {
      this.leaveParty(caller.code, now);
      this.sql.exec("INSERT INTO parties (code, host, created_at, last_active) VALUES (?, ?, ?, ?)", code, caller.code, now, now);
      this.sql.exec("INSERT INTO party_members (code, party, joined_at) VALUES (?, ?, ?)", caller.code, code, now);
    });
    return json({ ok: true, party: this.partyView(code, now) }, 201);
  }

  /**
   * POST /v1/party/join with `{ code }` (a party code) or `{ friend }` (the friend code of an online
   * friend who is in a party). Joining leaves the caller's previous party. Joining the party the caller
   * is already in is a no-op success.
   */
  private async joinParty(req: Request, caller: Caller, now: number): Promise<Response> {
    const target = parseJoin(await readBody(req, JOIN_FIELDS));
    let code: string | null;
    if ("party" in target) {
      code = this.liveParty(target.party, now);
      if (!code) throw new HttpError(404, "party_not_found", "no active party has that code");
    } else {
      const friend = target.friend;
      const isFriend = this.sql.exec("SELECT 1 FROM friends WHERE a = ? AND b = ?", caller.code, friend).toArray().length > 0;
      if (!isFriend) throw new HttpError(403, "not_friend", "you can only join the party of a friend");
      if (!isOnline(this.presenceOf(friend), now)) throw new HttpError(409, "friend_offline", "that friend is not online");
      code = this.currentParty(friend, now);
      if (!code) throw new HttpError(404, "friend_not_in_party", "that friend is not in a party");
    }
    if (this.currentParty(caller.code, now) === code) {
      this.touchParty(code, now, false);
      return json({ ok: true, joined: false, party: this.partyView(code, now) });
    }
    if (this.memberCount(code) >= MAX_PARTY_MEMBERS) {
      throw new HttpError(409, "party_full", `a party has at most ${MAX_PARTY_MEMBERS} members`);
    }
    const party = code;
    this.ctx.storage.transactionSync(() => {
      this.leaveParty(caller.code, now);
      this.sql.exec("INSERT INTO party_members (code, party, joined_at) VALUES (?, ?, ?)", caller.code, party, now);
      this.touchParty(party, now, true);
    });
    return json({ ok: true, joined: true, party: this.partyView(party, now) });
  }

  /** POST /v1/party/leave. Leaving when not in a party is a no-op success (`left: false`). */
  private async leavePartyRoute(req: Request, caller: Caller, now: number): Promise<Response> {
    await readBody(req, []);
    let left = false;
    this.ctx.storage.transactionSync(() => {
      left = this.leaveParty(caller.code, now);
    });
    return json({ ok: true, left });
  }

  /** POST /v1/party/session: the host starts (or replaces) the shared session every member sees. */
  private async startSession(req: Request, caller: Caller, now: number): Promise<Response> {
    const session = parseSession(await readBody(req, SESSION_FIELDS), now);
    const code = this.hostedParty(caller, now);
    this.sql.exec(
      `UPDATE parties SET session_method = ?, session_phase_ends_at = ?, session_started_at = ?, last_active = ?
       WHERE code = ?`,
      session.method, session.phaseEndsAt, now, now, code,
    );
    return json({ ok: true, party: this.partyView(code, now) });
  }

  /** DELETE /v1/party/session: the host ends the shared session. */
  private endSession(caller: Caller, now: number): Response {
    const code = this.hostedParty(caller, now);
    this.sql.exec(
      `UPDATE parties SET session_method = NULL, session_phase_ends_at = NULL, session_started_at = NULL, last_active = ?
       WHERE code = ?`,
      now, code,
    );
    return json({ ok: true, party: this.partyView(code, now) });
  }

  /** The caller's party, which they must host. */
  private hostedParty(caller: Caller, now: number): string {
    const code = this.currentParty(caller.code, now);
    if (!code) throw new HttpError(404, "not_in_party", "you are not in a party");
    const host = this.sql.exec<{ host: string }>("SELECT host FROM parties WHERE code = ?", code).one().host;
    if (host !== caller.code) throw new HttpError(403, "not_host", "only the host can change the shared session");
    return code;
  }

  private partyExists(code: string): boolean {
    return this.sql.exec("SELECT 1 FROM parties WHERE code = ?", code).toArray().length > 0;
  }

  /** `code` if that party exists and has not expired; an expired party is deleted on the spot. */
  private liveParty(code: string, now: number): string | null {
    const row = this.sql.exec<{ last_active: number }>("SELECT last_active FROM parties WHERE code = ?", code).toArray()[0];
    if (!row) return null;
    if (partyExpired(row.last_active, now)) {
      this.deleteParty(code);
      return null;
    }
    return code;
  }

  /** The live party a user is in, or `null`. */
  private currentParty(user: string, now: number): string | null {
    const row = this.sql.exec<{ party: string }>("SELECT party FROM party_members WHERE code = ?", user).toArray()[0];
    return row ? this.liveParty(row.party, now) : null;
  }

  private memberCount(code: string): number {
    return this.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM party_members WHERE party = ?", code).one().n;
  }

  /** Records activity. Unless `force`, it writes only when the stored value is PARTY_TOUCH_S old. */
  private touchParty(code: string, now: number, force: boolean): void {
    if (force) this.sql.exec("UPDATE parties SET last_active = ? WHERE code = ?", now, code);
    else this.sql.exec("UPDATE parties SET last_active = ? WHERE code = ? AND last_active <= ?", now, code, now - PARTY_TOUCH_S);
  }

  private deleteParty(code: string): void {
    this.sql.exec("DELETE FROM party_members WHERE party = ?", code);
    this.sql.exec("DELETE FROM parties WHERE code = ?", code);
  }

  /** Expired parties are otherwise only removed when touched; this keeps storage from piling up. */
  private sweepExpiredParties(now: number): void {
    const expired = this.sql.exec<{ code: string }>(
      "SELECT code FROM parties WHERE last_active <= ? LIMIT 100", now - PARTY_IDLE_EXPIRY_S).toArray();
    for (const { code } of expired) this.deleteParty(code);
  }

  /**
   * Removes a user from their party (call inside a transaction). The last member leaving deletes the
   * party; a leaving host hands over to the longest-standing member. Returns whether they were in one.
   */
  private leaveParty(user: string, now: number): boolean {
    const row = this.sql.exec<{ party: string }>("SELECT party FROM party_members WHERE code = ?", user).toArray()[0];
    if (!row) return false;
    this.sql.exec("DELETE FROM party_members WHERE code = ?", user);
    const next = this.sql.exec<{ code: string }>(
      "SELECT code FROM party_members WHERE party = ? ORDER BY joined_at, rowid LIMIT 1", row.party).toArray()[0];
    if (!next) {
      this.deleteParty(row.party);
    } else {
      this.sql.exec(
        "UPDATE parties SET host = CASE WHEN host = ? THEN ? ELSE host END, last_active = ? WHERE code = ?",
        user, next.code, now, row.party,
      );
    }
    return true;
  }

  /** The party as members see it: members in join order with profiles and presence. */
  private partyView(code: string, now: number) {
    const p = this.sql.exec<{
      host: string; created_at: number; last_active: number;
      session_method: string | null; session_phase_ends_at: number | null; session_started_at: number | null;
    }>("SELECT * FROM parties WHERE code = ?", code).one();
    const rows = this.sql.exec<UserRow & { joined_at: number }>(
      `SELECT u.*, m.joined_at FROM party_members m JOIN users u ON u.code = m.code
       WHERE m.party = ? ORDER BY m.joined_at, m.rowid`,
      code,
    ).toArray();
    const session: PartySession | null = p.session_method !== null && p.session_phase_ends_at !== null && p.session_started_at !== null
      ? { method: p.session_method, phaseEndsAt: p.session_phase_ends_at, startedAt: p.session_started_at }
      : null;
    return {
      code,
      host: p.host,
      createdAt: p.created_at,
      lastActive: p.last_active,
      expiresAt: p.last_active + PARTY_IDLE_EXPIRY_S,
      maxMembers: MAX_PARTY_MEMBERS,
      session,
      members: rows.map((r) => {
        const presence = this.presenceOf(r.code);
        return {
          profile: rowToProfile(r),
          joinedAt: r.joined_at,
          host: r.code === p.host,
          presence: publicPresence(presence, now),
          online: isOnline(presence, now),
        };
      }),
    };
  }
}
