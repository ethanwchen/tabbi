/**
 * The Hub: one SQLite-backed Durable Object that owns all state (users, friends, presence, parties,
 * daily study minutes).
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
import { AdminSecrets, exportTables, isAdminToken, notFound, parseRestore } from "./admin";
import {
  AUTH_FAILURES_PER_MIN, DEFAULT_NAME, DEFAULT_PET_NAME, HttpError, MAX_DEVICE_TOKENS, MAX_FRIENDS, MAX_PARTY_MEMBERS, PARTY_IDLE_EXPIRY_S, RATE_LIMIT_PER_MIN, REGISTER_PER_MIN, FRIEND_CODE_RE, TOKEN_RE,
  clientKey, isoWeekDays, isoWeekKeyOfDay, newCode, newToken, nowS, parseFriendCode, readBody, sha256Hex, utcDay,
} from "./lib";
import { PROFILE_FIELDS, Profile, applyProfilePatch, defaultProfile, parseProfilePatch, sameProfile } from "./profile";
import { json } from "./http";
import { SYNC_PUT_PER_MIN, etag, parseIfMatch, readSyncDocument } from "./sync";
import {
  APPLE_AUTH_FIELDS, APPLE_AUTH_PER_MIN, AppleSecrets, exchangeAuthorizationCode, parseAppleAuth, revokeRefreshToken,
  invalidToken, verifyIdentityToken,
} from "./apple";
import { PRESENCE_FIELDS, Presence, heartbeatSeconds, isOnline, parseHeartbeat, presenceChanged, publicPresence } from "./presence";
import { STUDY_DAY_RETENTION_DAYS, rankEntries } from "./leaderboard";
import {
  ADMIN_REPORTS_PAGE, MAX_BLOCKS, MAX_REPORTS_PER_DAY, REPORTS_PER_MIN, REPORT_FIELDS, parseReport,
} from "./moderation";
import { JOIN_FIELDS, PARTY_TOUCH_S, PartySession, SESSION_FIELDS, parseJoin, parseSession, partyExpired } from "./party";

export interface Env extends AppleSecrets, AdminSecrets {
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
  day             TEXT NOT NULL,
  last_seen       INTEGER NOT NULL
) WITHOUT ROWID;
-- Study minutes per user per local calendar day (the last todayMinutes reported for that day), kept
-- for STUDY_DAY_RETENTION_DAYS. The weekly leaderboard sums one ISO week of these.
CREATE TABLE IF NOT EXISTS study_days (
  code    TEXT NOT NULL,
  day     TEXT NOT NULL,
  minutes INTEGER NOT NULL,
  PRIMARY KEY (code, day)
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

/** Sign in with Apple accounts and their sync documents. */
const SYNC_SCHEMA = `
-- An Apple account maps Apple's stable user id (sub) to one friends user. No email or name is stored.
-- The refresh token from the authorization code exchange is kept only to revoke it when the account
-- is deleted; it is null when the exchange was skipped (Apple secrets unset) or failed.
CREATE TABLE apple_accounts (
  apple_sub     TEXT PRIMARY KEY,
  code          TEXT NOT NULL UNIQUE,
  refresh_token TEXT,
  created_at    INTEGER NOT NULL
) WITHOUT ROWID;
-- More tokens for a user, one per Mac that signed in to an existing account, so each Mac has its own
-- secret and none of them is ever sent back. users.token_hash stays the first Mac's token.
CREATE TABLE device_tokens (
  token_hash TEXT PRIMARY KEY,
  code       TEXT NOT NULL,
  created_at INTEGER NOT NULL
) WITHOUT ROWID;
CREATE INDEX device_tokens_by_code ON device_tokens (code);
-- The app's sync document (see sync.ts), stored as sent, with a revision for optimistic concurrency.
CREATE TABLE sync_documents (
  code       TEXT PRIMARY KEY,
  revision   INTEGER NOT NULL,
  document   TEXT NOT NULL,
  updated_at INTEGER NOT NULL
) WITHOUT ROWID;
`;

/** Moderation: blocks between users. */
const MODERATION_SCHEMA = `
-- A block hides two users from each other (friends, parties, leaderboard) and stops the blocked user
-- from adding the blocker or joining a party they host. Stored one way: only the blocker can lift it.
CREATE TABLE blocks (
  blocker    TEXT NOT NULL,
  blocked    TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (blocker, blocked)
) WITHOUT ROWID;
CREATE INDEX blocks_by_blocked ON blocks (blocked);
`;

/** Moderation: reports, bans and the names a maintainer took away. */
const REPORTS_SCHEMA = `
-- A user's report about another user. The reported user's name and pet name are copied as they were
-- when reported, since they may change before a maintainer reads it. Open while resolved_at is null;
-- resolution is dismissed, renamed or banned.
CREATE TABLE reports (
  id          INTEGER PRIMARY KEY,
  reporter    TEXT NOT NULL,
  reported    TEXT NOT NULL,
  reason      TEXT NOT NULL,
  note        TEXT,
  name        TEXT NOT NULL,
  pet_name    TEXT NOT NULL,
  created_at  INTEGER NOT NULL,
  resolved_at INTEGER,
  resolution  TEXT
);
CREATE INDEX reports_by_reporter ON reports (reporter, created_at);
CREATE INDEX reports_by_reported ON reports (reported);
-- A banned user keeps their data but cannot set a name or join parties, and no one else sees them.
CREATE TABLE bans (
  code       TEXT PRIMARY KEY,
  created_at INTEGER NOT NULL
) WITHOUT ROWID;
-- The name and pet name a maintainer replaced with placeholders; the user cannot set them again.
CREATE TABLE name_holds (
  code       TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  pet_name   TEXT NOT NULL,
  created_at INTEGER NOT NULL
) WITHOUT ROWID;
`;

/**
 * Ordered schema steps; step i brings the database to version i + 1. Append new steps and never edit
 * one that has been deployed. Step 1 is the original schema, written with IF NOT EXISTS so databases
 * created before versioning (which have its tables but no recorded version) pass through it unchanged.
 */
/** Apple identity tokens already used to sign in, so none of them signs in twice. */
const USED_IDENTITY_TOKENS_SCHEMA = `
-- The SHA-256 of each identity token that signed in, kept until the token would expire anyway.
CREATE TABLE used_identity_tokens (
  token_hash TEXT PRIMARY KEY,
  expires_at INTEGER NOT NULL
) WITHOUT ROWID;
CREATE INDEX used_identity_tokens_by_expiry ON used_identity_tokens (expires_at);
`;

/**
 * Name holds become one row per replaced name, so a second rename or an account fold adds to what a
 * user cannot set again instead of overwriting it. Only names that were not the placeholders are held; the
 * placeholders are written out (not DEFAULT_NAME) because a shipped step must never change.
 */
const NAME_HOLDS_SCHEMA = `
-- One name (kind 'name') or pet name (kind 'pet') a maintainer replaced; the user cannot set it again.
CREATE TABLE name_holds_by_value (
  code       TEXT NOT NULL,
  kind       TEXT NOT NULL CHECK (kind IN ('name', 'pet')),
  value      TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (code, kind, value)
) WITHOUT ROWID;
INSERT OR IGNORE INTO name_holds_by_value (code, kind, value, created_at)
  SELECT code, 'name', name, created_at FROM name_holds WHERE name != 'student';
INSERT OR IGNORE INTO name_holds_by_value (code, kind, value, created_at)
  SELECT code, 'pet', pet_name, created_at FROM name_holds WHERE pet_name != 'buddy';
DROP TABLE name_holds;
ALTER TABLE name_holds_by_value RENAME TO name_holds;
`;

const MIGRATIONS = [SCHEMA, SYNC_SCHEMA, MODERATION_SCHEMA, REPORTS_SCHEMA, USED_IDENTITY_TOKENS_SCHEMA, NAME_HOLDS_SCHEMA];

/** Runs the steps a database has not had yet, each in its own transaction with its version bump. */
export function migrate(storage: DurableObjectStorage): void {
  const sql = storage.sql;
  sql.exec("CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL)");
  const row = sql.exec<{ version: number }>("SELECT version FROM schema_version").toArray()[0];
  if (!row) sql.exec("INSERT INTO schema_version (version) VALUES (0)");
  for (let v = row?.version ?? 0; v < MIGRATIONS.length; v++) {
    storage.transactionSync(() => {
      sql.exec(MIGRATIONS[v]);
      sql.exec("UPDATE schema_version SET version = ?", v + 1);
    });
  }
}

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
  day: string;
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
    day: r.day ?? "",
    lastSeen: r.last_seen ?? 0,
  };
}

function bearer(req: Request): string | null {
  const m = /^Bearer\s+(\S+)$/i.exec((req.headers.get("Authorization") ?? "").trim());
  return m ? m[1] : null;
}

/** In-memory presence of a user and what of it is already persisted. */
interface LivePresence {
  presence: Presence;
  /** When the presence row was last written. */
  flushedAt: number;
  /** The `day:minutes` last written to `study_days`, so unchanged minutes are not rewritten. */
  savedDay: string | null;
}

/** How often the alarm deletes data past its retention (see `Hub.alarm`). */
export const RETENTION_SWEEP_S = 3600;

function rateLimited(minute: number, now: number): HttpError {
  const retry = Math.max(1, (minute + 1) * 60 - now);
  return new HttpError(429, "rate_limited", "too many requests", { "Retry-After": String(retry) });
}

const dayKey = (p: Presence) => `${p.day}:${p.todayMinutes}`;

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
  private live = new Map<string, LivePresence>();
  /** The UTC day the retention sweep last deleted old study minutes on. */
  private studyDaysSweptOn: string | null = null;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    migrate(ctx.storage);
    ctx.blockConcurrencyWhile(async () => {
      if ((await ctx.storage.getAlarm()) === null) await ctx.storage.setAlarm(Date.now() + RETENTION_SWEEP_S * 1000);
    });
  }

  /**
   * Runs the retention sweep every RETENTION_SWEEP_S. Without it, data of users who stopped using the
   * service would only expire when someone touched it: an idle party would outlive its 12 hours and an
   * inactive user's study minutes their 28 days, which PRIVACY.md promises.
   */
  async alarm(): Promise<void> {
    this.sweepRetention(nowS());
    await this.ctx.storage.setAlarm(Date.now() + RETENTION_SWEEP_S * 1000);
  }

  /**
   * Deletes every expired party, study minutes past their retention and spent identity token hashes.
   * Study minutes have no index by day, so that scan runs once per UTC day (again after an eviction,
   * which is harmless) rather than every hour.
   */
  private sweepRetention(now: number): void {
    const today = utcDay(now);
    this.ctx.storage.transactionSync(() => {
      const idleSince = now - PARTY_IDLE_EXPIRY_S;
      this.sql.exec("DELETE FROM party_members WHERE party IN (SELECT code FROM parties WHERE last_active <= ?)", idleSince);
      this.sql.exec("DELETE FROM parties WHERE last_active <= ?", idleSince);
      this.sql.exec("DELETE FROM used_identity_tokens WHERE expires_at < ?", now);
      if (this.studyDaysSweptOn !== today) {
        this.sql.exec("DELETE FROM study_days WHERE day < ?", utcDay(now - STUDY_DAY_RETENTION_DAYS * 86_400));
      }
    });
    this.studyDaysSweptOn = today;
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
      this.rateLimit("register:" + clientKey(req), REGISTER_PER_MIN, now);
      return this.register(req, now);
    }

    if (path === "/v1/auth/apple" && method === "POST") return await this.signInWithApple(req, now);
    if (path.startsWith("/v1/admin/")) return await this.admin(req, path, method, now);

    const caller = await this.authenticate(req, now);

    if (path === "/v1/me" && method === "GET") {
      return json(this.isBanned(caller.code) ? { ok: true, profile: caller.profile, banned: true } : { ok: true, profile: caller.profile });
    }
    if (path === "/v1/me" && method === "PATCH") return this.updateProfile(req, caller, false);
    if (path === "/v1/me" && method === "DELETE") return await this.deleteMe(caller);
    if (path === "/v1/auth/signout" && method === "POST") return await this.signOut(caller);

    if (path === "/v1/friends" && method === "GET") return this.listFriends(caller, now);
    if (path === "/v1/friends" && method === "POST") return this.addFriend(req, caller, now);
    const friendPath = /^\/v1\/friends\/([^/]+)$/.exec(path);
    if (friendPath && method === "DELETE") return this.removeFriend(caller, friendPath[1]);

    if (path === "/v1/blocks" && method === "GET") return this.listBlocks(caller);
    if (path === "/v1/blocks" && method === "POST") return this.block(req, caller, now);
    const blockPath = /^\/v1\/blocks\/([^/]+)$/.exec(path);
    if (blockPath && method === "DELETE") return this.unblock(caller, blockPath[1]);
    if (path === "/v1/reports" && method === "POST") return await this.report(req, caller, now);

    if (path === "/v1/presence" && method === "POST") return this.heartbeat(req, caller, now);
    if (path === "/v1/leaderboard" && method === "GET") return this.leaderboard(caller, now);

    if (path === "/v1/party" && method === "GET") return this.getParty(caller, now);
    if (path === "/v1/party" && method === "POST") return this.createParty(req, caller, now);
    if (path === "/v1/party/join" && method === "POST") return this.joinParty(req, caller, now);
    if (path === "/v1/party/leave" && method === "POST") return this.leavePartyRoute(req, caller, now);
    if (path === "/v1/party/session" && method === "POST") return this.startSession(req, caller, now);
    if (path === "/v1/party/session" && method === "DELETE") return this.endSession(caller, now);

    if (path === "/v1/sync" && method === "GET") return this.getSync(caller);
    // Awaited here: putSync can throw before its first await, and a rejection that is only adopted by
    // route's promise on a later tick is reported as unhandled by workerd.
    if (path === "/v1/sync" && method === "PUT") return await this.putSync(req, caller, now);

    throw new HttpError(404, "not_found", "not found");
  }

  // ---------- auth + rate limiting ----------

  /**
   * Resolves the caller from the Bearer token. Failures count per client IP, and an IP over its limit
   * is refused before any lookup, so guessing tokens costs the guesser, not the Hub. Only a token that
   * resolves gets a window of its own: unknown tokens never add entries to the rate-limit map.
   */
  private async authenticate(req: Request, now: number): Promise<Caller> {
    const failures = "authfail:" + clientKey(req);
    this.checkLimit(failures, AUTH_FAILURES_PER_MIN, now);
    const unauthorized = () => {
      this.rateLimit(failures, Infinity, now);
      return new HttpError(401, "unauthorized", "missing or invalid token");
    };
    const token = bearer(req);
    if (!token || !TOKEN_RE.test(token)) throw unauthorized();
    const tokenHash = await sha256Hex(token);
    const row = this.sql.exec<UserRow>("SELECT * FROM users WHERE token_hash = ?", tokenHash).toArray()[0]
      ?? this.sql.exec<UserRow>(
        "SELECT u.* FROM device_tokens d JOIN users u ON u.code = d.code WHERE d.token_hash = ?", tokenHash).toArray()[0];
    if (!row) throw unauthorized();
    this.rateLimit("t:" + tokenHash, RATE_LIMIT_PER_MIN, now);
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
    if (count > perMinute) throw rateLimited(minute, now);
  }

  /** Throws 429 if `id` has already used up this minute's window, without counting a request. */
  private checkLimit(id: string, perMinute: number, now: number): void {
    const minute = Math.floor(now / 60);
    const w = this.windows.get(id);
    if (w && w.minute === minute && w.count >= perMinute) throw rateLimited(minute, now);
  }

  // ---------- admin ----------

  /** Operator routes (see admin.ts). Anything short of a valid admin token is a plain 404. */
  private async admin(req: Request, path: string, method: string, now: number): Promise<Response> {
    const failures = "authfail:" + clientKey(req);
    this.checkLimit(failures, AUTH_FAILURES_PER_MIN, now);
    if (!(await isAdminToken(bearer(req), this.env.ADMIN_TOKEN))) {
      this.rateLimit(failures, Infinity, now);
      throw notFound();
    }
    if (path === "/v1/admin/export" && method === "GET") {
      const version = this.sql.exec<{ version: number }>("SELECT version FROM schema_version").one().version;
      return json({ ok: true, exportedAt: now, schemaVersion: version, tables: exportTables(this.sql) });
    }
    if (path === "/v1/admin/restore" && method === "POST") return await this.restore(req, now);
    if (path === "/v1/admin/reports" && method === "GET") {
      const status = new URL(req.url).searchParams.get("status") ?? "open";
      if (status !== "open" && status !== "all") throw new HttpError(400, "invalid_field", "status must be open or all");
      return this.adminReports(status === "open");
    }
    const dismiss = /^\/v1\/admin\/reports\/(\d+)\/dismiss$/.exec(path);
    if (dismiss && method === "POST") return this.dismissReport(Number(dismiss[1]), now);
    const user = /^\/v1\/admin\/users\/([^/]+)\/(rename|ban)$/.exec(path);
    if (user && user[2] === "rename" && method === "POST") return this.adminRename(user[1], now);
    if (user && user[2] === "ban" && method === "POST") return this.adminBan(user[1], now);
    if (user && user[2] === "ban" && method === "DELETE") return this.adminUnban(user[1]);
    throw notFound();
  }

  /**
   * Point-in-time recovery: the storage goes back to the requested time or bookmark when the object
   * next starts, and the object restarts right after replying. The reply carries a bookmark of the
   * state just before the restore, which a later restore can return to.
   */
  private async restore(req: Request, now: number): Promise<Response> {
    const target = await parseRestore(req, now);
    let undoBookmark: string;
    try {
      const bookmark = "bookmark" in target ? target.bookmark : await this.ctx.storage.getBookmarkForTime(target.at * 1000);
      undoBookmark = await this.ctx.storage.onNextSessionRestoreBookmark(bookmark);
    } catch (e) {
      console.error(e);
      throw new HttpError(501, "restore_unavailable", "point-in-time recovery is not available here");
    }
    console.log("admin: restoring storage to " + ("at" in target ? `time ${target.at}` : "a bookmark"));
    setTimeout(() => this.ctx.abort("restoring a backup"), 100);
    return json({ ok: true, undoBookmark });
  }

  // ---------- profile ----------

  private async register(req: Request, now: number): Promise<Response> {
    const patch = parseProfilePatch(await readBody(req, PROFILE_FIELDS));
    const token = newToken();
    const profile = this.insertUser(await sha256Hex(token), patch, now);
    return json({ ok: true, token, code: profile.code, profile }, 201);
  }

  /** Creates a user with a fresh friend code. Synchronous, so it can run inside a transaction. */
  private insertUser(tokenHash: string, patch: ReturnType<typeof parseProfilePatch>, now: number): Profile {
    let code = newCode(8);
    for (let i = 0; i < 20 && this.userExists(code); i++) code = newCode(8);
    if (this.userExists(code)) throw new HttpError(503, "unavailable", "could not allocate a code, retry");
    const profile = applyProfilePatch(defaultProfile(code), patch);
    this.sql.exec(
      `INSERT INTO users (code, token_hash, name, pet_name, species, breed, colors, costume, accessories, points, level, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      code, tokenHash, profile.name, profile.petName, profile.species, profile.breed,
      JSON.stringify(profile.colors), profile.costume, JSON.stringify(profile.accessories),
      profile.points, profile.level, now,
    );
    return profile;
  }

  /** PATCH /v1/me, and POST /v1/register with a valid token (idempotent re-register). */
  private async updateProfile(req: Request, caller: Caller, isRegister: boolean): Promise<Response> {
    const patch = parseProfilePatch(await readBody(req, PROFILE_FIELDS));
    const next = applyProfilePatch(caller.profile, patch);
    this.checkNames(caller, next);
    // Write only on change: SQLite row writes are the scarce free-tier resource.
    if (!sameProfile(next, caller.profile)) {
      this.sql.exec(
        `UPDATE users SET name = ?, pet_name = ?, species = ?, breed = ?, colors = ?, costume = ?,
           accessories = ?, points = ?, level = ? WHERE code = ?`,
        next.name, next.petName, next.species, next.breed, JSON.stringify(next.colors), next.costume,
        JSON.stringify(next.accessories), next.points, next.level, caller.code,
      );
    }
    if (isRegister) return json({ ok: true, code: caller.code, profile: next });
    // Like GET /v1/me, so the app learns of a ban on its connect PATCH without another request.
    return json(this.isBanned(caller.code) ? { ok: true, profile: next, banned: true } : { ok: true, profile: next });
  }

  /**
   * DELETE /v1/me: deletes everything about the user (every Mac's token stops working) and, for a Sign
   * in with Apple account, revokes its Apple refresh token. The data is gone before Apple is called, so
   * deletion never depends on Apple; `appleRevoked` says whether the revoke went through.
   */
  private async deleteMe(caller: Caller): Promise<Response> {
    const now = nowS();
    const account = this.sql.exec<{ refresh_token: string | null }>(
      "SELECT refresh_token FROM apple_accounts WHERE code = ?", caller.code).toArray()[0];
    this.ctx.storage.transactionSync(() => this.purgeUser(caller.code, now));
    const appleRevoked = account?.refresh_token ? await revokeRefreshToken(account.refresh_token, this.env, now) : false;
    return json(account ? { ok: true, appleRevoked } : { ok: true });
  }

  /** Deletes a user and all their rows (call inside a transaction). */
  private purgeUser(code: string, now: number): void {
    this.leaveParty(code, now);
    this.sql.exec("DELETE FROM users WHERE code = ?", code);
    // Both directions via the primary key: the reverse rows are found through my own friend list.
    this.sql.exec("DELETE FROM friends WHERE b = ? AND a IN (SELECT b FROM friends WHERE a = ?)", code, code);
    this.sql.exec("DELETE FROM friends WHERE a = ?", code);
    this.sql.exec("DELETE FROM presence WHERE code = ?", code);
    this.sql.exec("DELETE FROM study_days WHERE code = ?", code);
    this.sql.exec("DELETE FROM sync_documents WHERE code = ?", code);
    this.sql.exec("DELETE FROM apple_accounts WHERE code = ?", code);
    this.sql.exec("DELETE FROM device_tokens WHERE code = ?", code);
    this.sql.exec("DELETE FROM blocks WHERE blocker = ?", code);
    this.sql.exec("DELETE FROM blocks WHERE blocked = ?", code);
    this.sql.exec("DELETE FROM reports WHERE reporter = ? OR reported = ?", code, code);
    this.sql.exec("DELETE FROM bans WHERE code = ?", code);
    this.sql.exec("DELETE FROM name_holds WHERE code = ?", code);
    this.live.delete(code);
  }

  private userExists(code: string): boolean {
    return FRIEND_CODE_RE.test(code) && this.sql.exec("SELECT 1 FROM users WHERE code = ?", code).toArray().length > 0;
  }

  // ---------- friends ----------

  /** Each friend's party size counts only the members the caller would see in that party's view. */
  private listFriends(caller: Caller, now: number): Response {
    const rows = this.sql.exec<UserRow & Partial<PresenceRow> & { since: number; party_code: string | null; party_size: number | null }>(
      `SELECT u.*, f.created_at AS since, p.status, p.method, p.phase_ends_at, p.session_minutes,
         p.today_minutes, p.streak_days, p.day, p.last_seen, pa.code AS party_code,
         (SELECT COUNT(*) FROM party_members m2 WHERE m2.party = pa.code
            AND m2.code NOT IN (SELECT blocked FROM blocks WHERE blocker = ?)
            AND m2.code NOT IN (SELECT blocker FROM blocks WHERE blocked = ?)
            AND (m2.code = ? OR m2.code NOT IN (SELECT code FROM bans))) AS party_size
       FROM friends f JOIN users u ON u.code = f.b LEFT JOIN presence p ON p.code = f.b
         LEFT JOIN party_members m ON m.code = f.b
         LEFT JOIN parties pa ON pa.code = m.party AND pa.last_active > ?
       WHERE f.a = ? AND f.b NOT IN (SELECT code FROM bans) ORDER BY u.name COLLATE NOCASE, u.code`,
      caller.code, caller.code, caller.code, now - PARTY_IDLE_EXPIRY_S, caller.code,
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
    this.requireNotBanned(caller);
    if (this.hasBlocked(caller.code, code)) throw new HttpError(409, "blocked", "you blocked them; unblock them first");
    const row = this.knownUser(caller, code);
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

  // ---------- blocks ----------

  private hasBlocked(blocker: string, blocked: string): boolean {
    return this.sql.exec("SELECT 1 FROM blocks WHERE blocker = ? AND blocked = ?", blocker, blocked).toArray().length > 0;
  }

  private blockedEitherWay(a: string, b: string): boolean {
    return this.hasBlocked(a, b) || this.hasBlocked(b, a);
  }

  /**
   * The user a friend, block or report request names. A banned user, or one who blocked the caller,
   * answers `404 unknown_code` exactly like a code no one has, so no route reveals a block or a ban.
   */
  private knownUser(caller: Caller, code: string): UserRow {
    const row = this.sql.exec<UserRow>("SELECT * FROM users WHERE code = ?", code).toArray()[0];
    if (!row || this.isBanned(code) || this.hasBlocked(code, caller.code)) {
      throw new HttpError(404, "unknown_code", "no one has that code");
    }
    return row;
  }

  /** GET /v1/blocks: the users I blocked, newest first, with their current name and pet name. */
  private listBlocks(caller: Caller): Response {
    const rows = this.sql.exec<{ code: string; name: string; pet_name: string; created_at: number }>(
      `SELECT u.code, u.name, u.pet_name, b.created_at FROM blocks b JOIN users u ON u.code = b.blocked
       WHERE b.blocker = ? ORDER BY b.created_at DESC, u.code`,
      caller.code,
    ).toArray();
    return json({ ok: true, blocks: rows.map((r) => ({ code: r.code, name: r.name, petName: r.pet_name, since: r.created_at })) });
  }

  /**
   * POST /v1/blocks with `{ code }`: ends the friendship and hides us from each other. If we share a
   * party, the blocked user leaves it when I host, I leave it when they host, and otherwise we just stop
   * seeing each other in it. Blocking someone already blocked is a no-op success (`blocked: false`).
   */
  private async block(req: Request, caller: Caller, now: number): Promise<Response> {
    const body = await readBody(req, ["code"]);
    const code = parseFriendCode(body.code);
    if (code === caller.code) throw new HttpError(400, "self_block", "you cannot block yourself");
    const already = this.hasBlocked(caller.code, code);
    // Re-blocking someone I already blocked is answered from my own list, so it reveals nothing new.
    const row = (already ? this.sql.exec<UserRow>("SELECT * FROM users WHERE code = ?", code).toArray()[0] : undefined)
      ?? this.knownUser(caller, code);
    if (!already) {
      const count = this.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM blocks WHERE blocker = ?", caller.code).one().n;
      if (count >= MAX_BLOCKS) throw new HttpError(409, "block_limit", `you already blocked ${MAX_BLOCKS} people`);
      const mine = this.currentParty(caller.code, now);
      const shared = mine !== null && mine === this.currentParty(code, now) ? mine : null;
      const host = shared ? this.sql.exec<{ host: string }>("SELECT host FROM parties WHERE code = ?", shared).one().host : null;
      this.ctx.storage.transactionSync(() => {
        this.sql.exec("INSERT INTO blocks (blocker, blocked, created_at) VALUES (?, ?, ?)", caller.code, code, now);
        this.sql.exec("DELETE FROM friends WHERE (a = ? AND b = ?) OR (a = ? AND b = ?)", caller.code, code, code, caller.code);
        if (host === caller.code) this.leaveParty(code, now);
        else if (host === code) this.leaveParty(caller.code, now);
      });
    }
    return json({ ok: true, blocked: !already, block: { code, name: row.name, petName: row.pet_name } });
  }

  /** DELETE /v1/blocks/{code}: lifts my block. The friendship is not restored; either can add again. */
  private unblock(caller: Caller, raw: string): Response {
    const code = parseFriendCode(raw);
    const unblocked = this.sql.exec("DELETE FROM blocks WHERE blocker = ? AND blocked = ?", caller.code, code).rowsWritten > 0;
    return json({ ok: true, unblocked });
  }

  // ---------- reports, bans and name holds ----------

  private isBanned(code: string): boolean {
    return this.sql.exec("SELECT 1 FROM bans WHERE code = ?", code).toArray().length > 0;
  }

  private requireNotBanned(caller: Caller): void {
    if (this.isBanned(caller.code)) throw new HttpError(403, "banned", "this account can no longer use Party");
  }

  /**
   * A banned user cannot change their name or pet name, and no one can set again a name a maintainer
   * replaced. Unchanged names pass, so the app can keep sending the whole profile.
   */
  private checkNames(caller: Caller, next: Profile): void {
    const nameChanged = next.name !== caller.profile.name;
    const petChanged = next.petName !== caller.profile.petName;
    if (!nameChanged && !petChanged) return;
    this.requireNotBanned(caller);
    const holds = this.sql.exec<{ kind: string; value: string }>(
      "SELECT kind, value FROM name_holds WHERE code = ?", caller.code).toArray();
    const held = (kind: string, value: string) => holds.some((h) =>
      h.kind === kind && h.value.localeCompare(value, undefined, { sensitivity: "base" }) === 0);
    if (nameChanged && held("name", next.name)) {
      throw new HttpError(400, "name_not_allowed", "That name isn't allowed. Please pick another.");
    }
    if (petChanged && held("pet", next.petName)) {
      throw new HttpError(400, "pet_name_not_allowed", "That pet name isn't allowed. Please pick another.");
    }
  }

  /**
   * POST /v1/reports with `{ code, reason, note? }`: stores a report with the reported user's current
   * name and pet name. A second report about the same user while the first is still open updates it
   * (`created: false`), so the review queue holds one entry per reporter and user.
   */
  private async report(req: Request, caller: Caller, now: number): Promise<Response> {
    const body = await readBody(req, REPORT_FIELDS);
    const code = parseFriendCode(body.code);
    const { reason, note } = parseReport(body);
    if (code === caller.code) throw new HttpError(400, "self_report", "you cannot report yourself");
    const row = this.knownUser(caller, code);
    this.rateLimit("report:" + caller.code, REPORTS_PER_MIN, now);
    const open = this.sql.exec<{ id: number }>(
      "SELECT id FROM reports WHERE reporter = ? AND reported = ? AND resolved_at IS NULL", caller.code, code).toArray()[0];
    if (open) {
      this.sql.exec("UPDATE reports SET reason = ?, note = ?, name = ?, pet_name = ?, created_at = ? WHERE id = ?",
        reason, note, row.name, row.pet_name, now, open.id);
      return json({ ok: true, created: false });
    }
    const today = this.sql.exec<{ n: number }>(
      "SELECT COUNT(*) AS n FROM reports WHERE reporter = ? AND created_at > ?", caller.code, now - 86_400).one().n;
    if (today >= MAX_REPORTS_PER_DAY) {
      throw new HttpError(429, "report_limit", `at most ${MAX_REPORTS_PER_DAY} reports a day`);
    }
    this.sql.exec(
      `INSERT INTO reports (reporter, reported, reason, note, name, pet_name, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      caller.code, code, reason, note, row.name, row.pet_name, now,
    );
    return json({ ok: true, created: true }, 201);
  }

  /** GET /v1/admin/reports[?status=all]: open (or all) reports, newest first, with who is involved now. */
  private adminReports(openOnly: boolean): Response {
    const rows = this.sql.exec<{
      id: number; reporter: string; reported: string; reason: string; note: string | null; name: string; pet_name: string;
      created_at: number; resolved_at: number | null; resolution: string | null;
      reporter_name: string | null; current_name: string | null; current_pet_name: string | null;
      banned: number; open_reports: number;
    }>(
      `SELECT r.*, a.name AS reporter_name, u.name AS current_name, u.pet_name AS current_pet_name,
         EXISTS (SELECT 1 FROM bans WHERE code = r.reported) AS banned,
         (SELECT COUNT(*) FROM reports o WHERE o.reported = r.reported AND o.resolved_at IS NULL) AS open_reports
       FROM reports r LEFT JOIN users a ON a.code = r.reporter LEFT JOIN users u ON u.code = r.reported
       WHERE ? = 0 OR r.resolved_at IS NULL
       ORDER BY r.created_at DESC, r.id DESC LIMIT ?`,
      openOnly ? 1 : 0, ADMIN_REPORTS_PAGE,
    ).toArray();
    const reports = rows.map((r) => ({
      id: r.id,
      createdAt: r.created_at,
      reason: r.reason,
      note: r.note,
      resolvedAt: r.resolved_at,
      resolution: r.resolution,
      reporter: { code: r.reporter, name: r.reporter_name },
      reported: {
        code: r.reported,
        name: r.name,
        petName: r.pet_name,
        currentName: r.current_name,
        currentPetName: r.current_pet_name,
        banned: r.banned === 1,
        openReports: r.open_reports,
      },
    }));
    return json({ ok: true, reports });
  }

  /** POST /v1/admin/reports/{id}/dismiss: closes a report without acting on the user. */
  private dismissReport(id: number, now: number): Response {
    const done = this.sql.exec(
      "UPDATE reports SET resolved_at = ?, resolution = 'dismissed' WHERE id = ? AND resolved_at IS NULL", now, id).rowsWritten > 0;
    if (!done && this.sql.exec("SELECT 1 FROM reports WHERE id = ?", id).toArray().length === 0) {
      throw new HttpError(404, "report_not_found", "no report has that id");
    }
    return json({ ok: true, dismissed: done });
  }

  /** The user an admin route acts on, or 404. */
  private adminTarget(raw: string): UserRow {
    const code = parseFriendCode(raw);
    const row = this.sql.exec<UserRow>("SELECT * FROM users WHERE code = ?", code).toArray()[0];
    if (!row) throw new HttpError(404, "unknown_code", "no one has that code");
    return row;
  }

  private resolveReportsAbout(code: string, resolution: string, now: number): void {
    this.sql.exec("UPDATE reports SET resolved_at = ?, resolution = ? WHERE reported = ? AND resolved_at IS NULL",
      now, resolution, code);
  }

  /**
   * POST /v1/admin/users/{code}/rename: replaces the name and pet name with the defaults new users get,
   * holds the old ones so the user cannot set them again, and resolves open reports about the user.
   */
  private adminRename(raw: string, now: number): Response {
    const row = this.adminTarget(raw);
    this.ctx.storage.transactionSync(() => {
      if (row.name !== DEFAULT_NAME || row.pet_name !== DEFAULT_PET_NAME) {
        const hold = "INSERT OR IGNORE INTO name_holds (code, kind, value, created_at) VALUES (?, ?, ?, ?)";
        if (row.name !== DEFAULT_NAME) this.sql.exec(hold, row.code, "name", row.name, now);
        if (row.pet_name !== DEFAULT_PET_NAME) this.sql.exec(hold, row.code, "pet", row.pet_name, now);
        this.sql.exec("UPDATE users SET name = ?, pet_name = ? WHERE code = ?", DEFAULT_NAME, DEFAULT_PET_NAME, row.code);
      }
      this.resolveReportsAbout(row.code, "renamed", now);
    });
    return json({ ok: true, profile: { ...rowToProfile(row), name: DEFAULT_NAME, petName: DEFAULT_PET_NAME } });
  }

  /**
   * POST /v1/admin/users/{code}/ban: the user leaves their party, disappears for everyone else and
   * cannot set a name or join parties; their data stays, so the ban can be lifted.
   */
  private adminBan(raw: string, now: number): Response {
    const row = this.adminTarget(raw);
    let banned = false;
    this.ctx.storage.transactionSync(() => {
      banned = this.sql.exec("INSERT OR IGNORE INTO bans (code, created_at) VALUES (?, ?)", row.code, now).rowsWritten > 0;
      this.leaveParty(row.code, now);
      this.resolveReportsAbout(row.code, "banned", now);
    });
    return json({ ok: true, banned });
  }

  /** DELETE /v1/admin/users/{code}/ban: lifts a ban. Friendships come back as they were. */
  private adminUnban(raw: string): Response {
    const code = parseFriendCode(raw);
    const unbanned = this.sql.exec("DELETE FROM bans WHERE code = ?", code).rowsWritten > 0;
    return json({ ok: true, unbanned });
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
   * different status, method, phase or streak, on a new day, or when the last write is PRESENCE_FLUSH_S
   * old. The day's study minutes are written with the same flushes, and only when they changed.
   */
  private async heartbeat(req: Request, caller: Caller, now: number): Promise<Response> {
    const body = await readBody(req, PRESENCE_FIELDS);
    const live = this.live.get(caller.code);
    const prev = live?.presence ?? this.presenceOf(caller.code);
    const next = parseHeartbeat(body, prev, now);
    let flushedAt = live?.flushedAt ?? 0;
    let savedDay = live?.savedDay ?? null;
    const newDay = prev !== null && prev.day !== next.day;
    if (!live || !prev || newDay || presenceChanged(prev, next) || now - flushedAt >= PRESENCE_FLUSH_S) {
      this.ctx.storage.transactionSync(() => {
        this.sql.exec(
          `INSERT OR REPLACE INTO presence
             (code, status, method, phase_ends_at, session_minutes, today_minutes, streak_days, day, last_seen)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          caller.code, next.status, next.method, next.phaseEndsAt, next.sessionMinutes, next.todayMinutes,
          next.streakDays, next.day, next.lastSeen,
        );
        if (newDay) {
          // Close out the previous day with its final count (it may not have been flushed yet).
          if (prev.todayMinutes > 0 && savedDay !== dayKey(prev)) this.saveStudyDay(caller.code, prev);
          this.sql.exec("DELETE FROM study_days WHERE code = ? AND day < ?",
            caller.code, utcDay(now - STUDY_DAY_RETENTION_DAYS * 86_400));
        }
        // A zero count is skipped unless it corrects a count already saved for the same day.
        if (savedDay !== dayKey(next) && (next.todayMinutes > 0 || savedDay?.startsWith(next.day + ":"))) {
          this.saveStudyDay(caller.code, next);
          savedDay = dayKey(next);
        }
      });
      flushedAt = now;
    }
    this.live.set(caller.code, { presence: next, flushedAt, savedDay });
    return json({ ok: true, presence: next, heartbeatSeconds: heartbeatSeconds(next.status) });
  }

  private saveStudyDay(code: string, p: Presence): void {
    this.sql.exec(
      `INSERT INTO study_days (code, day, minutes) VALUES (?, ?, ?)
       ON CONFLICT (code, day) DO UPDATE SET minutes = excluded.minutes`,
      code, p.day, p.todayMinutes,
    );
  }

  // ---------- leaderboard ----------

  /**
   * GET /v1/leaderboard: study minutes of the caller and their friends in the current ISO week (by the
   * UTC calendar), summed over each user's local days. Live, not yet flushed counts are included.
   */
  private leaderboard(caller: Caller, now: number): Response {
    const today = utcDay(now);
    const days = isoWeekDays(today);
    const from = days[0];
    const to = days[6];
    const users = this.sql.exec<UserRow>(
      `SELECT * FROM users WHERE code = ?
         OR (code IN (SELECT b FROM friends WHERE a = ?) AND code NOT IN (SELECT code FROM bans))`, caller.code, caller.code,
    ).toArray();
    const perDay = new Map<string, Map<string, number>>(users.map((u) => [u.code, new Map()]));
    const rows = this.sql.exec<{ code: string; day: string; minutes: number }>(
      `SELECT code, day, minutes FROM study_days
       WHERE (code = ? OR code IN (SELECT b FROM friends WHERE a = ?)) AND day BETWEEN ? AND ?`,
      caller.code, caller.code, from, to,
    ).toArray();
    for (const r of rows) perDay.get(r.code)?.set(r.day, r.minutes);
    for (const [code, daysOfUser] of perDay) {
      const p = this.live.get(code)?.presence;
      if (p && p.day >= from && p.day <= to) daysOfUser.set(p.day, p.todayMinutes);
    }
    const entries = rankEntries(users.map((u) => ({
      minutes: [...(perDay.get(u.code)?.values() ?? [])].reduce((a, b) => a + b, 0),
      me: u.code === caller.code,
      profile: rowToProfile(u),
    })));
    return json({ ok: true, week: isoWeekKeyOfDay(today), from, to, entries });
  }

  // ---------- Sign in with Apple ----------

  /**
   * POST /v1/auth/apple with `{ identityToken, authorizationCode? }` and, optionally, the caller's
   * anonymous friends token as Bearer. Maps Apple's `sub` to one friends user:
   * - a known account returns a new token of its own for this Mac (the same friend code, friends and
   *   sync document follow the user). An anonymous caller is folded into it: its friends and study
   *   days move to the account, then the anonymous user is deleted, since the app drops its token.
   * - a new account links the caller's anonymous user (same token and friend code), or, without one,
   *   creates a user.
   * The authorization code's refresh token is stored only to revoke it on deletion.
   */
  private async signInWithApple(req: Request, now: number): Promise<Response> {
    this.rateLimit("apple:" + clientKey(req), APPLE_AUTH_PER_MIN, now);
    const body = parseAppleAuth(await readBody(req, APPLE_AUTH_FIELDS));
    const callerToken = bearer(req);
    // A token that no longer resolves (its user was deleted) signs in as if there were none.
    const live = callerToken ? await this.authenticate(req, now).catch((e: unknown) => {
      if (e instanceof HttpError && e.status === 401) return null;
      throw e;
    }) : null;
    const identityHash = await sha256Hex(body.identityToken);
    const { sub, reusableUntil } = await verifyIdentityToken(body.identityToken, now);
    // Claimed before Apple is asked about the code, with no await between the check and the insert, so
    // two copies of one token racing each other cannot both get through.
    this.claimIdentityToken(identityHash, reusableUntil, now);
    const refreshToken = body.authorizationCode
      ? await exchangeAuthorizationCode(body.authorizationCode, this.env, now)
      : null;
    const freshToken = newToken();
    const freshHash = await sha256Hex(freshToken);

    // No awaits from here on: the state read below cannot change before it is written.
    let result: { token: string; code: string; newAccount: boolean } | null = null;
    this.ctx.storage.transactionSync(() => {
      // The caller may have been deleted while this request waited on Apple.
      const caller = live && this.sql.exec("SELECT 1 FROM users WHERE code = ?", live.code).toArray().length > 0
        ? live : null;
      const linked = this.sql.exec<{ code: string }>(
        "SELECT code FROM apple_accounts WHERE apple_sub = ?", sub).toArray()[0]?.code;
      if (linked) {
        if (refreshToken) this.sql.exec("UPDATE apple_accounts SET refresh_token = ? WHERE apple_sub = ?", refreshToken, sub);
        if (caller && callerToken && caller.code === linked) {
          result = { token: callerToken, code: linked, newAccount: false };
          return;
        }
        if (caller && !this.hasAppleAccount(caller.code)) this.foldInto(caller.code, linked, now);
        this.sql.exec(
          `DELETE FROM device_tokens WHERE token_hash IN (SELECT token_hash FROM device_tokens WHERE code = ?
           ORDER BY created_at DESC, token_hash LIMIT -1 OFFSET ?)`,
          linked, MAX_DEVICE_TOKENS - 1,
        );
        this.sql.exec("INSERT INTO device_tokens (token_hash, code, created_at) VALUES (?, ?, ?)", freshHash, linked, now);
        result = { token: freshToken, code: linked, newAccount: false };
        return;
      }
      // A caller already linked to another Apple ID keeps that account; this Apple ID gets a new user.
      const code = caller && callerToken && !this.hasAppleAccount(caller.code)
        ? caller.code
        : this.insertUser(freshHash, {}, now).code;
      this.sql.exec("INSERT INTO apple_accounts (apple_sub, code, refresh_token, created_at) VALUES (?, ?, ?, ?)",
        sub, code, refreshToken, now);
      result = { token: code === caller?.code ? callerToken! : freshToken, code, newAccount: true };
    });
    const { token, code, newAccount } = result!;
    const profile = rowToProfile(this.sql.exec<UserRow>("SELECT * FROM users WHERE code = ?", code).one());
    return json({ ok: true, token, code, profile, newAccount });
  }

  /**
   * POST /v1/auth/signout: the caller's token stops working; the account and every other Mac's token
   * stay. A per-Mac token is deleted. The first Mac's token lives on the user row, so it is replaced by
   * the hash of a token nobody holds. An anonymous user is refused, since it would lose its only token.
   */
  private async signOut(caller: Caller): Promise<Response> {
    this.requireAccount(caller);
    const retired = await sha256Hex(newToken());
    this.sql.exec("DELETE FROM device_tokens WHERE token_hash = ?", caller.tokenHash);
    this.sql.exec("UPDATE users SET token_hash = ? WHERE token_hash = ?", retired, caller.tokenHash);
    return json({ ok: true });
  }

  /**
   * Accepts an identity token once: a second sign-in with the same token is refused, even with a fresh
   * IP or after the first one failed later on (the user signs in with Apple again, which mints a new
   * token). Hashes are dropped once their token has expired, so the table stays small.
   */
  private claimIdentityToken(hash: string, reusableUntil: number, now: number): void {
    this.sql.exec("DELETE FROM used_identity_tokens WHERE expires_at < ?", now);
    const used = this.sql.exec("SELECT 1 FROM used_identity_tokens WHERE token_hash = ?", hash).toArray().length > 0;
    if (used) throw invalidToken("already used");
    this.sql.exec("INSERT INTO used_identity_tokens (token_hash, expires_at) VALUES (?, ?)", hash, reusableUntil);
  }

  private hasAppleAccount(code: string): boolean {
    return this.sql.exec("SELECT 1 FROM apple_accounts WHERE code = ?", code).toArray().length > 0;
  }

  /**
   * Moves an anonymous user's friends (up to the friend limit) and study days (the larger count per day)
   * to an account, then deletes the anonymous user (call inside a transaction).
   */
  private foldInto(from: string, to: string, now: number): void {
    const friends = this.sql.exec<{ b: string }>(
      `SELECT b FROM friends WHERE a = ? AND b != ? AND b NOT IN (SELECT b FROM friends WHERE a = ?)
         AND b NOT IN (SELECT blocked FROM blocks WHERE blocker = ?) AND b NOT IN (SELECT blocker FROM blocks WHERE blocked = ?)
       ORDER BY created_at`,
      from, to, to, to, to).toArray();
    let count = this.friendCount(to);
    for (const { b } of friends) {
      if (count >= MAX_FRIENDS) break;
      this.sql.exec("INSERT OR IGNORE INTO friends (a, b, created_at) VALUES (?, ?, ?), (?, ?, ?)", to, b, now, b, to, now);
      count++;
    }
    this.sql.exec(
      `INSERT INTO study_days (code, day, minutes) SELECT ?, day, minutes FROM study_days WHERE code = ? AND true
       ON CONFLICT (code, day) DO UPDATE SET minutes = MAX(minutes, excluded.minutes)`,
      to, from,
    );
    // Blocks follow the user both ways, so signing in never lifts a block.
    this.sql.exec(
      `INSERT OR IGNORE INTO blocks (blocker, blocked, created_at)
       SELECT ?, blocked, created_at FROM blocks WHERE blocker = ? AND blocked != ?`, to, from, to);
    this.sql.exec(
      `INSERT OR IGNORE INTO blocks (blocker, blocked, created_at)
       SELECT blocker, ?, created_at FROM blocks WHERE blocked = ? AND blocker != ?`, to, from, to);
    if (this.sql.exec("SELECT 1 FROM blocks WHERE blocker = ? OR blocked = ? LIMIT 1", to, to).toArray().length > 0) {
      this.sql.exec(
        `DELETE FROM friends WHERE a = ? AND (b IN (SELECT blocked FROM blocks WHERE blocker = ?)
           OR b IN (SELECT blocker FROM blocks WHERE blocked = ?))`, to, to, to);
      this.sql.exec(
        `DELETE FROM friends WHERE b = ? AND (a IN (SELECT blocked FROM blocks WHERE blocker = ?)
           OR a IN (SELECT blocker FROM blocks WHERE blocked = ?))`, to, to, to);
    }
    // Reports, bans and name holds follow the user too, so signing in never lifts a ban. Reports between
    // the two are dropped: once they are one user, they would be reports about oneself.
    this.sql.exec("DELETE FROM reports WHERE (reporter = ? AND reported = ?) OR (reporter = ? AND reported = ?)", from, to, to, from);
    this.sql.exec("UPDATE reports SET reporter = ? WHERE reporter = ?", to, from);
    this.sql.exec("UPDATE reports SET reported = ? WHERE reported = ?", to, from);
    this.sql.exec("INSERT OR IGNORE INTO bans (code, created_at) SELECT ?, created_at FROM bans WHERE code = ?", to, from);
    this.sql.exec(
      "INSERT OR IGNORE INTO name_holds (code, kind, value, created_at) SELECT ?, kind, value, created_at FROM name_holds WHERE code = ?",
      to, from);
    this.purgeUser(from, now);
    // An inherited ban takes the account out of its party, as banning it would; blocks the account just
    // inherited apply to its party as they would to a fresh block.
    if (this.isBanned(to)) {
      this.leaveParty(to, now);
      return;
    }
    const party = this.sql.exec<{ party: string }>("SELECT party FROM party_members WHERE code = ?", to).toArray()[0]?.party;
    if (party) this.dropMembersBlockedWithHost(party);
  }

  // ---------- sync ----------

  /** Sync belongs to Sign in with Apple accounts; an anonymous friends user has nothing to sync with. */
  private requireAccount(caller: Caller): void {
    if (!this.hasAppleAccount(caller.code)) throw new HttpError(403, "no_account", "sign in with Apple to sync");
  }

  /** GET /v1/sync: the caller's document and its revision (0 and `null` before the first write). */
  private getSync(caller: Caller): Response {
    this.requireAccount(caller);
    const row = this.sql.exec<{ revision: number; document: string; updated_at: number }>(
      "SELECT revision, document, updated_at FROM sync_documents WHERE code = ?", caller.code).toArray()[0];
    const revision = row?.revision ?? 0;
    return json(
      { ok: true, revision, updatedAt: row?.updated_at ?? null, document: row ? JSON.parse(row.document) : null },
      200, { ETag: etag(revision) },
    );
  }

  /**
   * PUT /v1/sync with `If-Match: <revision>`: replaces the document if the caller merged into the
   * current revision, else 409 with the current revision (the app pulls, merges and retries).
   */
  private async putSync(req: Request, caller: Caller, now: number): Promise<Response> {
    this.requireAccount(caller);
    const expected = parseIfMatch(req.headers.get("If-Match"));
    this.rateLimit("sync:" + caller.code, SYNC_PUT_PER_MIN, now);
    const document = JSON.stringify(await readSyncDocument(req));
    const current = this.sql.exec<{ revision: number }>(
      "SELECT revision FROM sync_documents WHERE code = ?", caller.code).toArray()[0]?.revision ?? 0;
    if (expected !== current) {
      throw new HttpError(409, "revision_conflict", `the document is at revision ${current}; pull, merge and retry`,
        { ETag: etag(current) });
    }
    const revision = current + 1;
    this.sql.exec(
      `INSERT INTO sync_documents (code, revision, document, updated_at) VALUES (?, ?, ?, ?)
       ON CONFLICT (code) DO UPDATE SET revision = excluded.revision, document = excluded.document,
         updated_at = excluded.updated_at`,
      caller.code, revision, document, now,
    );
    return json({ ok: true, revision, updatedAt: now }, 200, { ETag: etag(revision) });
  }

  // ---------- parties ----------

  /** GET /v1/party: the caller's party, or `null`. A member's poll counts as party activity. */
  private getParty(caller: Caller, now: number): Response {
    const code = this.currentParty(caller.code, now);
    if (code) this.touchParty(code, now, false);
    return json({ ok: true, party: code ? this.partyView(code, now, caller.code) : null });
  }

  /** POST /v1/party: creates a party with the caller as host, leaving any party they were in. */
  private async createParty(req: Request, caller: Caller, now: number): Promise<Response> {
    await readBody(req, []);
    this.requireNotBanned(caller);
    this.sweepExpiredParties(now);
    let code = newCode(6);
    for (let i = 0; i < 20 && this.partyExists(code); i++) code = newCode(6);
    if (this.partyExists(code)) throw new HttpError(503, "unavailable", "could not allocate a party code, retry");
    this.ctx.storage.transactionSync(() => {
      this.leaveParty(caller.code, now);
      this.sql.exec("INSERT INTO parties (code, host, created_at, last_active) VALUES (?, ?, ?, ?)", code, caller.code, now, now);
      this.sql.exec("INSERT INTO party_members (code, party, joined_at) VALUES (?, ?, ?)", caller.code, code, now);
    });
    return json({ ok: true, party: this.partyView(code, now, caller.code) }, 201);
  }

  /**
   * POST /v1/party/join with `{ code }` (a party code) or `{ friend }` (the friend code of an online
   * friend who is in a party). Joining leaves the caller's previous party. Joining the party the caller
   * is already in is a no-op success.
   */
  private async joinParty(req: Request, caller: Caller, now: number): Promise<Response> {
    const target = parseJoin(await readBody(req, JOIN_FIELDS));
    this.requireNotBanned(caller);
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
    const host = this.sql.exec<{ host: string }>("SELECT host FROM parties WHERE code = ?", code).one().host;
    // A party whose host and the caller blocked each other looks like it does not exist.
    if (this.blockedEitherWay(caller.code, host)) throw new HttpError(404, "party_not_found", "no active party has that code");
    if (this.currentParty(caller.code, now) === code) {
      this.touchParty(code, now, false);
      return json({ ok: true, joined: false, party: this.partyView(code, now, caller.code) });
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
    return json({ ok: true, joined: true, party: this.partyView(party, now, caller.code) });
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
    return json({ ok: true, party: this.partyView(code, now, caller.code) });
  }

  /** DELETE /v1/party/session: the host ends the shared session. */
  private endSession(caller: Caller, now: number): Response {
    const code = this.hostedParty(caller, now);
    this.sql.exec(
      `UPDATE parties SET session_method = NULL, session_phase_ends_at = NULL, session_started_at = NULL, last_active = ?
       WHERE code = ?`,
      now, code,
    );
    return json({ ok: true, party: this.partyView(code, now, caller.code) });
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
   * party; a leaving host hands over to the longest-standing member, and members who blocked the new
   * host or were blocked by them leave too. Returns whether the user was in one.
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
      this.dropMembersBlockedWithHost(row.party);
    }
    return true;
  }

  /**
   * Removes the members of a party who blocked its host or were blocked by them (call inside a
   * transaction), so a party never holds both sides of a block with the host, as POST /v1/blocks and
   * joining already guarantee. Needed when the host changes or an account inherits blocks.
   */
  private dropMembersBlockedWithHost(party: string): void {
    this.sql.exec(
      `DELETE FROM party_members WHERE party = ?1 AND code IN (
         SELECT blocked FROM blocks WHERE blocker = (SELECT host FROM parties WHERE code = ?1)
         UNION SELECT blocker FROM blocks WHERE blocked = (SELECT host FROM parties WHERE code = ?1))`,
      party,
    );
  }

  /**
   * The party as `viewer` sees it: members in join order with profiles and presence, leaving out anyone
   * the viewer blocked or was blocked by, and banned users.
   */
  private partyView(code: string, now: number, viewer: string) {
    const p = this.sql.exec<{
      host: string; created_at: number; last_active: number;
      session_method: string | null; session_phase_ends_at: number | null; session_started_at: number | null;
    }>("SELECT * FROM parties WHERE code = ?", code).one();
    const rows = this.sql.exec<UserRow & { joined_at: number }>(
      `SELECT u.*, m.joined_at FROM party_members m JOIN users u ON u.code = m.code
       WHERE m.party = ?
         AND m.code NOT IN (SELECT blocked FROM blocks WHERE blocker = ?)
         AND m.code NOT IN (SELECT blocker FROM blocks WHERE blocked = ?)
         AND (m.code = ? OR m.code NOT IN (SELECT code FROM bans))
       ORDER BY m.joined_at, m.rowid`,
      code, viewer, viewer, viewer,
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
