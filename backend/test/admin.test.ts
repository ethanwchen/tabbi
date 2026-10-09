import { env } from "cloudflare:workers";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { MIN_ADMIN_TOKEN_LENGTH, RESTORE_WINDOW_S, isAdminToken } from "../src/admin";
import { AUTH_FAILURES_PER_MIN } from "../src/lib";
import { call, expectError, freshIp, pinClockToMinuteStart, register } from "./helpers";

const admin = () => env.ADMIN_TOKEN as string;

describe("isAdminToken", () => {
  const secret = "s".repeat(MIN_ADMIN_TOKEN_LENGTH);

  it("accepts only the exact configured token", async () => {
    expect(await isAdminToken(secret, secret)).toBe(true);
    expect(await isAdminToken(secret + "x", secret)).toBe(false);
    expect(await isAdminToken(secret.slice(1), secret)).toBe(false);
    expect(await isAdminToken(null, secret)).toBe(false);
  });

  it("is off without a configured token or with a short one", async () => {
    expect(await isAdminToken("", undefined)).toBe(false);
    expect(await isAdminToken("anything", undefined)).toBe(false);
    expect(await isAdminToken("", "")).toBe(false);
    const short = "s".repeat(MIN_ADMIN_TOKEN_LENGTH - 1);
    expect(await isAdminToken(short, short)).toBe(false);
  });
});

describe("admin endpoints", () => {
  beforeEach(pinClockToMinuteStart);
  afterEach(() => vi.useRealTimers());

  it("look like unknown paths to anyone without the admin token", async () => {
    const user = await register();
    for (const token of [undefined, user.token, "f".repeat(64), admin().slice(1)]) {
      expectError(await call("GET", "/v1/admin/export", undefined, token, freshIp()), 404, "not_found");
      expectError(await call("POST", "/v1/admin/restore", { at: 1 }, token, freshIp()), 404, "not_found");
    }
  });

  it("count wrong admin tokens as failed authentications per IP", async () => {
    const ip = freshIp();
    for (let i = 0; i < AUTH_FAILURES_PER_MIN; i++) {
      expectError(await call("GET", "/v1/admin/export", undefined, "f".repeat(64), ip), 404, "not_found");
    }
    const r = await call("GET", "/v1/admin/export", undefined, admin(), ip);
    expectError(r, 429, "rate_limited");
    expect(r.headers.get("Retry-After")).toBe("60");
  });

  it("export every table with the schema version", async () => {
    const user = await register({ name: "Ada" });
    const r = await call("GET", "/v1/admin/export", undefined, admin(), freshIp());
    expect(r.status).toBe(200);
    expect(r.headers.get("Cache-Control")).toBe("no-store");
    expect(r.body.exportedAt).toBe(Math.floor(Date.now() / 1000));
    expect(r.body.schemaVersion).toBeGreaterThanOrEqual(2);
    expect(Object.keys(r.body.tables)).toEqual(expect.arrayContaining([
      "users", "friends", "presence", "study_days", "parties", "party_members", "apple_accounts", "device_tokens", "sync_documents",
    ]));
    expect(Object.keys(r.body.tables).some((t) => t.startsWith("_cf_") || t.startsWith("sqlite_"))).toBe(false);
    const row = r.body.tables.users.find((u: { code: string }) => u.code === user.code);
    expect(row.name).toBe("Ada");
    expect(row.token_hash).toMatch(/^[0-9a-f]{64}$/);
    expect(JSON.stringify(r.body)).not.toContain(user.token);
  });

  it("validate a restore before touching storage", async () => {
    const now = Math.floor(Date.now() / 1000);
    for (const body of [{}, { at: now, bookmark: "abc" }, { at: now + 1 }, { at: now - RESTORE_WINDOW_S - 1 }, { at: "yesterday" },
      { bookmark: "'; DROP TABLE users" }, { bookmark: "" }]) {
      expectError(await call("POST", "/v1/admin/restore", body, admin(), freshIp()), 400, "invalid_field");
    }
    expectError(await call("POST", "/v1/admin/restore", { at: now, extra: 1 }, admin(), freshIp()), 400, "unknown_field");
  });

  it("report a restore the runtime cannot do without restarting", async () => {
    // Local workerd has no point-in-time recovery, so a valid restore fails cleanly instead of resetting.
    const r = await call("POST", "/v1/admin/restore", { at: Math.floor(Date.now() / 1000) - 60 }, admin(), freshIp());
    expectError(r, 501, "restore_unavailable");
    expect((await register()).code).toMatch(/^[A-HJ-NP-Z2-9]{8}$/);
  });

  it("delete an account again, as DELETE /v1/me does, for deletions a restore brought back", async () => {
    const gone = await register();
    const friend = await register();
    await call("POST", "/v1/friends", { code: gone.code }, friend.token);
    expectError(await call("DELETE", `/v1/admin/users/${gone.code}`, undefined, friend.token, freshIp()), 404, "not_found");
    const r = await call("DELETE", `/v1/admin/users/${gone.code.toLowerCase()}`, undefined, admin(), freshIp());
    expect(r.body).toEqual({ ok: true, deleted: true });
    expectError(await call("GET", "/v1/me", undefined, gone.token), 401, "unauthorized");
    expect((await call("GET", "/v1/friends", undefined, friend.token)).body.friends).toEqual([]);
    const dump = JSON.stringify((await call("GET", "/v1/admin/export", undefined, admin(), freshIp())).body.tables);
    expect(dump).not.toContain(gone.code);
    expect((await call("DELETE", `/v1/admin/users/${gone.code}`, undefined, admin(), freshIp())).body).toEqual({ ok: true, deleted: false });
    expectError(await call("DELETE", "/v1/admin/users/nope", undefined, admin(), freshIp()), 400, "invalid_field");
  });

  it("have no other routes", async () => {
    expectError(await call("GET", "/v1/admin/users", undefined, admin(), freshIp()), 404, "not_found");
    expectError(await call("POST", "/v1/admin/export", undefined, admin(), freshIp()), 404, "not_found");
  });
});
