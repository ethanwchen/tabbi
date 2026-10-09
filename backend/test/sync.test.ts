import { SELF, runInDurableObject } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { describe, expect, it, vi } from "vitest";
import { migrate } from "../src/hub";
import { MAX_SYNC_BYTES, SYNC_PUT_PER_MIN } from "../src/sync";
import { BASE, Reply, call, expectError, hub, linkAppleAccount, pinClockToMinuteStart, register } from "./helpers";

const DOC = {
  schemaVersion: 1,
  pet: { profile: { name: "Mochi", species: "cat" }, updatedAt: "2026-10-08T12:00:00Z" },
  tallies: { "mac-a": { earned: 120, spent: 40 } },
  unlocks: ["hat.beret"],
  studyDays: ["2026-10-07", "2026-10-08"],
  longestStreak: 2,
};

async function put(token: string, document: unknown, ifMatch?: string): Promise<Reply> {
  const headers: Record<string, string> = { "Content-Type": "application/json", Authorization: `Bearer ${token}` };
  if (ifMatch !== undefined) headers["If-Match"] = ifMatch;
  const res = await SELF.fetch(BASE + "/v1/sync", { method: "PUT", headers, body: JSON.stringify({ document }) });
  const text = await res.text();
  return { status: res.status, headers: res.headers, body: text ? JSON.parse(text) : null };
}

async function signedIn() {
  const a = await register();
  await linkAppleAccount(a.code);
  return a;
}

describe("GET /v1/sync", () => {
  it("is revision 0 with no document before the first write", async () => {
    const a = await signedIn();
    const r = await call("GET", "/v1/sync", undefined, a.token);
    expect(r.status).toBe(200);
    expect(r.body).toEqual({ ok: true, revision: 0, updatedAt: null, document: null });
    expect(r.headers.get("ETag")).toBe('"0"');
  });

  it("needs a Sign in with Apple account and a token", async () => {
    const a = await register();
    expectError(await call("GET", "/v1/sync", undefined, a.token), 403, "no_account");
    expectError(await put(a.token, DOC, "0"), 403, "no_account");
    expectError(await call("GET", "/v1/sync"), 401, "unauthorized");
  });
});

describe("PUT /v1/sync", () => {
  it("stores the document as sent and bumps the revision", async () => {
    const a = await signedIn();
    const first = await put(a.token, DOC, "0");
    expect(first.status).toBe(200);
    expect(first.body).toMatchObject({ ok: true, revision: 1 });
    expect(typeof first.body.updatedAt).toBe("number");
    expect(first.headers.get("ETag")).toBe('"1"');

    const got = await call("GET", "/v1/sync", undefined, a.token);
    expect(got.body).toEqual({ ok: true, revision: 1, updatedAt: first.body.updatedAt, document: DOC });

    // A quoted ETag works as well as a bare number.
    const next = { ...DOC, longestStreak: 3, futureField: { kept: true } };
    expect((await put(a.token, next, '"1"')).body.revision).toBe(2);
    expect((await call("GET", "/v1/sync", undefined, a.token)).body.document).toEqual(next);
  });

  it("rejects a stale revision with 409 and the current revision", async () => {
    const a = await signedIn();
    await put(a.token, DOC, "0");
    // A second Mac that never pulled tries to create the document.
    const stale = await put(a.token, { ...DOC, unlocks: [] }, "0");
    expectError(stale, 409, "revision_conflict");
    expect(stale.headers.get("ETag")).toBe('"1"');
    expectError(await put(a.token, DOC, "7"), 409, "revision_conflict");
    expect((await call("GET", "/v1/sync", undefined, a.token)).body.document).toEqual(DOC);
  });

  it("needs If-Match", async () => {
    const a = await signedIn();
    expectError(await put(a.token, DOC), 428, "revision_required");
    expectError(await put(a.token, DOC, "one"), 400, "invalid_revision");
    expectError(await put(a.token, DOC, "-1"), 400, "invalid_revision");
  });

  it("rejects bodies that are not a versioned document", async () => {
    const a = await signedIn();
    expectError(await put(a.token, null, "0"), 400, "invalid_field");
    expectError(await put(a.token, [DOC], "0"), 400, "invalid_field");
    expectError(await put(a.token, { pet: null }, "0"), 400, "invalid_field");
    expectError(await put(a.token, { ...DOC, schemaVersion: 0 }, "0"), 400, "invalid_field");
    expectError(await put(a.token, { ...DOC, schemaVersion: "1" }, "0"), 400, "invalid_field");
    const extra = await SELF.fetch(BASE + "/v1/sync", {
      method: "PUT",
      headers: { Authorization: `Bearer ${a.token}`, "If-Match": "0" },
      body: JSON.stringify({ document: DOC, email: "a@b.c" }),
    });
    expect(extra.status).toBe(400);
    expect(((await extra.json()) as { error: string }).error).toBe("unknown_field");
  });

  it("accepts a large document and rejects one over the cap", async () => {
    const a = await signedIn();
    const days = Array.from({ length: 400 }, (_, i) => new Date(Date.UTC(2025, 0, 1 + i)).toISOString().slice(0, 10));
    expect((await put(a.token, { ...DOC, studyDays: days }, "0")).status).toBe(200);
    const huge = { ...DOC, unlocks: ["x".repeat(MAX_SYNC_BYTES)] };
    expectError(await put(a.token, huge, "1"), 413, "body_too_large");
  });

  it("rate limits writes per user", async () => {
    pinClockToMinuteStart();
    try {
      const a = await signedIn();
      for (let i = 0; i < SYNC_PUT_PER_MIN; i++) expect((await put(a.token, DOC, String(i))).status).toBe(200);
      const limited = await put(a.token, DOC, String(SYNC_PUT_PER_MIN));
      expectError(limited, 429, "rate_limited");
      expect(limited.headers.get("Retry-After")).toBe("60");
    } finally {
      vi.useRealTimers();
    }
  });

  it("keeps each user's document apart", async () => {
    const a = await signedIn();
    const b = await signedIn();
    await put(a.token, DOC, "0");
    expect((await call("GET", "/v1/sync", undefined, b.token)).body.document).toBeNull();
  });
});

describe("DELETE /v1/me", () => {
  it("deletes the sync document and the Apple account", async () => {
    const a = await signedIn();
    await put(a.token, DOC, "0");
    expect((await call("DELETE", "/v1/me", undefined, a.token)).status).toBe(200);
    const left = await runInDurableObject(hub(), (_, state) => ({
      docs: state.storage.sql.exec("SELECT 1 FROM sync_documents WHERE code = ?", a.code).toArray().length,
      accounts: state.storage.sql.exec("SELECT 1 FROM apple_accounts WHERE code = ?", a.code).toArray().length,
    }));
    expect(left).toEqual({ docs: 0, accounts: 0 });
  });
});

describe("schema migrations", () => {
  it("brings a database from before versioning up to date and keeps its data", async () => {
    const stub = env.HUB.get(env.HUB.idFromName("legacy"));
    await runInDurableObject(stub, (_, state) => {
      const sql = state.storage.sql;
      // What a deployment from before versioning has: the original tables and no version.
      sql.exec("DROP TABLE sync_documents");
      sql.exec("DROP TABLE apple_accounts");
      sql.exec("DROP TABLE device_tokens");
      sql.exec("DROP TABLE blocks");
      sql.exec("DROP TABLE reports");
      sql.exec("DROP TABLE bans");
      sql.exec("DROP TABLE name_holds");
      sql.exec("DROP TABLE used_identity_tokens");
      sql.exec("DROP TABLE schema_version");
      sql.exec(`INSERT INTO users (code, token_hash, name, pet_name, species, breed, colors, costume, accessories, points, level, created_at)
        VALUES ('AAAAAAAA', 'h', 'n', 'p', 'cat', 'tabby', '[]', 'none', '[]', 5, 1, 0)`);
      migrate(state.storage);
      expect(sql.exec<{ version: number }>("SELECT version FROM schema_version").one().version).toBe(5);
      expect(sql.exec<{ points: number }>("SELECT points FROM users WHERE code = 'AAAAAAAA'").one().points).toBe(5);
      expect(sql.exec("SELECT * FROM sync_documents").toArray()).toEqual([]);
      expect(sql.exec("SELECT * FROM used_identity_tokens").toArray()).toEqual([]);
      // Running again is a no-op.
      migrate(state.storage);
      expect(sql.exec("SELECT version FROM schema_version").toArray()).toEqual([{ version: 5 }]);
    });
  });

  it("adds the used identity token table to a version 4 database and keeps its accounts", async () => {
    const stub = env.HUB.get(env.HUB.idFromName("version-4"));
    await runInDurableObject(stub, (_, state) => {
      const sql = state.storage.sql;
      sql.exec("DROP TABLE used_identity_tokens");
      sql.exec("UPDATE schema_version SET version = 4");
      sql.exec("INSERT INTO apple_accounts (apple_sub, code, refresh_token, created_at) VALUES ('s', 'BBBBBBBB', NULL, 0)");
      migrate(state.storage);
      expect(sql.exec("SELECT version FROM schema_version").toArray()).toEqual([{ version: 5 }]);
      expect(sql.exec("SELECT apple_sub FROM apple_accounts").toArray()).toEqual([{ apple_sub: "s" }]);
      expect(sql.exec("SELECT * FROM used_identity_tokens").toArray()).toEqual([]);
    });
  });
});
