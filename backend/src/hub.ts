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
  HttpError, RATE_LIMIT_PER_MIN, REGISTER_PER_MIN, FRIEND_CODE_RE, TOKEN_RE,
  newCode, newToken, nowS, readBody, sha256Hex,
} from "./lib";
import { PROFILE_FIELDS, Profile, applyProfilePatch, defaultProfile, parseProfilePatch, sameProfile } from "./profile";
import { json } from "./http";

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
`;

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
    this.ctx.storage.transactionSync(() => {
      this.sql.exec("DELETE FROM users WHERE code = ?", caller.code);
    });
    return json({ ok: true });
  }

  private userExists(code: string): boolean {
    return FRIEND_CODE_RE.test(code) && this.sql.exec("SELECT 1 FROM users WHERE code = ?", code).toArray().length > 0;
  }
}
