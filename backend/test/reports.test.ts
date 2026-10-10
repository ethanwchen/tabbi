import { describe, expect, it } from "vitest";
import { env, runInDurableObject } from "cloudflare:test";
import { migrate } from "../src/hub";
import { MAX_REPORTS_PER_DAY, REPORTS_PER_MIN } from "../src/moderation";
import { admin, call, expectError, freshIp, hub, register } from "./helpers";

const report = (by: { token: string }, who: { code: string }, reason = "inappropriate_name", note?: string) =>
  call("POST", "/v1/reports", note === undefined ? { code: who.code, reason } : { code: who.code, reason, note }, by.token);
const openReports = async () => (await admin("GET", "/reports")).body.reports as any[]; // eslint-disable-line @typescript-eslint/no-explicit-any
const about = async (who: { code: string }) => (await openReports()).filter((r) => r.reported.code === who.code);
const codes = (list: { profile: { code: string } }[]) => list.map((x) => x.profile.code);

async function createParty(u: { token: string }) {
  const r = await call("POST", "/v1/party", undefined, u.token);
  expect(r.status).toBe(201);
  return r.body.party.code as string;
}

/** Moves stored reports back in time, so the daily cap can be tested without waiting a day. */
async function ageReports(reporter: string, seconds: number) {
  await runInDurableObject(hub(), (_, state) => {
    state.storage.sql.exec("UPDATE reports SET created_at = created_at - ? WHERE reporter = ?", seconds, reporter);
  });
}

describe("POST /v1/reports", () => {
  it("stores the reason, note, reporter and the reported user's name and pet at that moment", async () => {
    const a = await register({ name: "Ana" });
    const b = await register({ name: "Rude Name", petName: "Worse" });
    const r = await report(a, b, "harassment", "  keeps sending mean party invites \u0007");
    expect(r.status).toBe(201);
    expect(r.body).toEqual({ ok: true, created: true });

    await call("PATCH", "/v1/me", { name: "Nice Name", petName: "Mochi" }, b.token);
    const [stored] = await about(b);
    expect(stored).toEqual({
      id: expect.any(Number),
      createdAt: expect.any(Number),
      reason: "harassment",
      note: "keeps sending mean party invites",
      resolvedAt: null,
      resolution: null,
      reporter: { code: a.code, name: "Ana" },
      reported: {
        code: b.code, name: "Rude Name", petName: "Worse", currentName: "Nice Name", currentPetName: "Mochi",
        banned: false, openReports: 1,
      },
    });
  });

  it("keeps one open report per reporter and user, updated by a repeat", async () => {
    const a = await register();
    const b = await register();
    await report(a, b, "spam");
    const again = await report(a, b, "other", "it was more than spam");
    expect(again.status).toBe(200);
    expect(again.body.created).toBe(false);
    const list = await about(b);
    expect(list).toHaveLength(1);
    expect(list[0].reason).toBe("other");
    expect(list[0].note).toBe("it was more than spam");
  });

  it("rejects bad input", async () => {
    const a = await register();
    const b = await register();
    expectError(await report(a, a), 400, "self_report");
    expectError(await report(a, { code: "ZZZZZZZZ" }), 404, "unknown_code");
    expectError(await report(a, b, "rude"), 400, "invalid_field");
    expectError(await report(a, b, "spam", "x".repeat(281)), 400, "invalid_field");
    expectError(await call("POST", "/v1/reports", { code: b.code, reason: "spam", extra: 1 }, a.token), 400, "unknown_field");
    expectError(await call("POST", "/v1/reports", { code: b.code, reason: "spam" }), 401, "unauthorized");
  });

  it("limits how fast and how much one user reports", async () => {
    const a = await register();
    const targets = await Promise.all(Array.from({ length: REPORTS_PER_MIN + 1 }, () => register()));
    for (const t of targets.slice(0, REPORTS_PER_MIN)) expect((await report(a, t)).status).toBe(201);
    const limited = await report(a, targets[REPORTS_PER_MIN]);
    expectError(limited, 429, "rate_limited");
    expect(Number(limited.headers.get("Retry-After"))).toBeGreaterThan(0);

    const b = await register();
    await runInDurableObject(hub(), (_, state) => {
      for (let i = 0; i < MAX_REPORTS_PER_DAY; i++) {
        state.storage.sql.exec(
          "INSERT INTO reports (reporter, reported, reason, note, name, pet_name, created_at, resolved_at) VALUES (?, 'ZZZZZZZZ', 'spam', NULL, 'n', 'p', ?, 1)",
          b.code, Math.floor(Date.now() / 1000) - 60);
      }
    });
    const c = await register();
    expectError(await report(b, c), 429, "report_limit");
    await ageReports(b.code, 86_400);
    expect((await report(b, c)).status).toBe(201);
  });

  it("is deleted with the reporter's or the reported user's account", async () => {
    const a = await register();
    const b = await register();
    const c = await register();
    await report(a, b);
    await report(b, c);
    await call("DELETE", "/v1/me", undefined, b.token);
    const all = (await admin("GET", "/reports?status=all")).body.reports as any[]; // eslint-disable-line @typescript-eslint/no-explicit-any
    expect(all.filter((r) => r.reporter.code === b.code || r.reported.code === b.code)).toEqual([]);
  });
});

describe("admin routes", () => {
  it("need the admin token and look like unknown paths without it", async () => {
    const a = await register();
    expectError(await admin("GET", "/reports", "wrong"), 404, "not_found");
    expectError(await admin("GET", "/reports", a.token), 404, "not_found");
    expectError(await call("GET", "/v1/admin/reports", undefined, undefined, freshIp()), 404, "not_found");
    expectError(await admin("GET", "/nothing"), 404, "not_found");
    expectError(await admin("GET", "/reports?status=closed"), 400, "invalid_field");
  });

  it("dismiss a report, which leaves the open list but stays in the full one", async () => {
    const a = await register();
    const b = await register();
    await report(a, b);
    const [r] = await about(b);
    expect((await admin("POST", `/reports/${r.id}/dismiss`)).body).toEqual({ ok: true, dismissed: true });
    expect((await admin("POST", `/reports/${r.id}/dismiss`)).body.dismissed).toBe(false);
    expect(await about(b)).toEqual([]);
    const all = (await admin("GET", "/reports?status=all")).body.reports as any[]; // eslint-disable-line @typescript-eslint/no-explicit-any
    expect(all.find((x) => x.id === r.id)).toMatchObject({ resolution: "dismissed", resolvedAt: expect.any(Number) });
    expectError(await admin("POST", "/reports/999999999/dismiss"), 404, "report_not_found");
  });

  it("rename a user to the placeholders, resolve their reports and keep the old names from coming back", async () => {
    const a = await register();
    const b = await register({ name: "Rude Name", petName: "Worse" });
    await report(a, b);
    const r = await admin("POST", `/users/${b.code}/rename`);
    expect(r.body.profile).toMatchObject({ code: b.code, name: "student", petName: "buddy" });
    expect((await call("GET", "/v1/me", undefined, b.token)).body.profile).toMatchObject({ name: "student", petName: "buddy" });
    expect(await about(b)).toEqual([]);

    expectError(await call("PATCH", "/v1/me", { name: "rude name" }, b.token), 400, "name_not_allowed");
    expectError(await call("PATCH", "/v1/me", { petName: "WORSE" }, b.token), 400, "pet_name_not_allowed");
    // Unchanged names and other fields still save, so the app can keep sending the whole profile.
    expect((await call("PATCH", "/v1/me", { name: "student", points: 9 }, b.token)).body.profile.points).toBe(9);
    expect((await call("PATCH", "/v1/me", { name: "Kind Name" }, b.token)).body.profile.name).toBe("Kind Name");
    expectError(await admin("POST", "/users/ZZZZZZZZ/rename"), 404, "unknown_code");
  });

  it("keep every replaced name held when a user is renamed more than once", async () => {
    const b = await register({ name: "First Bad", petName: "Pet One" });
    await admin("POST", `/users/${b.code}/rename`);
    await call("PATCH", "/v1/me", { name: "Second Bad", petName: "Pet Two" }, b.token);
    await admin("POST", `/users/${b.code}/rename`);

    expectError(await call("PATCH", "/v1/me", { name: "first bad" }, b.token), 400, "name_not_allowed");
    expectError(await call("PATCH", "/v1/me", { name: "Second Bad" }, b.token), 400, "name_not_allowed");
    expectError(await call("PATCH", "/v1/me", { petName: "Pet One" }, b.token), 400, "pet_name_not_allowed");
    expectError(await call("PATCH", "/v1/me", { petName: "pet two" }, b.token), 400, "pet_name_not_allowed");
  });

  it("hold only the names a rename replaced, so a default name stays settable", async () => {
    const b = await register({ name: "student", petName: "Rude Pet" });
    await admin("POST", `/users/${b.code}/rename`);
    expectError(await call("PATCH", "/v1/me", { petName: "Rude Pet" }, b.token), 400, "pet_name_not_allowed");
    expect((await call("PATCH", "/v1/me", { name: "Kind" }, b.token)).body.profile.name).toBe("Kind");
    expect((await call("PATCH", "/v1/me", { name: "student" }, b.token)).body.profile.name).toBe("student");
  });

  it("ban a user: hidden from friends, parties and the leaderboard, no name changes or joining, reversible", async () => {
    const a = await register();
    const b = await register({ name: "Rude" });
    const c = await register();
    await call("POST", "/v1/friends", { code: b.code }, a.token);
    const party = await createParty(a);
    await call("POST", "/v1/party/join", { code: party }, b.token);
    await report(a, b, "harassment");

    expect((await admin("POST", `/users/${b.code}/ban`)).body).toEqual({ ok: true, banned: true });
    expect((await admin("POST", `/users/${b.code}/ban`)).body.banned).toBe(false);
    expect((await admin("GET", "/reports?status=all")).body.reports.find((r: any) => r.reported.code === b.code)) // eslint-disable-line @typescript-eslint/no-explicit-any
      .toMatchObject({ resolution: "banned", reported: { banned: true, openReports: 0 } });

    // Gone for everyone else.
    expect(await codes((await call("GET", "/v1/friends", undefined, a.token)).body.friends)).toEqual([]);
    const board = (await call("GET", "/v1/leaderboard", undefined, a.token)).body.entries;
    expect(codes(board)).toEqual([a.code]);
    expect(codes((await call("GET", "/v1/party", undefined, a.token)).body.party.members)).toEqual([a.code]);
    expect((await call("GET", "/v1/party", undefined, b.token)).body.party).toBeNull();
    expectError(await call("POST", "/v1/friends", { code: b.code }, c.token), 404, "unknown_code");

    // What the banned user can no longer do; their own data stays readable.
    const me = await call("GET", "/v1/me", undefined, b.token);
    expect(me.body).toMatchObject({ banned: true, profile: { name: "Rude" } });
    expectError(await call("PATCH", "/v1/me", { name: "Other" }, b.token), 403, "banned");
    expect((await call("PATCH", "/v1/me", { name: "Rude", points: 3 }, b.token)).body)
      .toMatchObject({ banned: true, profile: { name: "Rude", points: 3 } });
    expectError(await call("POST", "/v1/party", undefined, b.token), 403, "banned");
    expectError(await call("POST", "/v1/party/join", { code: party }, b.token), 403, "banned");
    expectError(await call("POST", "/v1/friends", { code: c.code }, b.token), 403, "banned");

    expect((await admin("DELETE", `/users/${b.code}/ban`)).body).toEqual({ ok: true, unbanned: true });
    expect((await admin("DELETE", `/users/${b.code}/ban`)).body.unbanned).toBe(false);
    expect((await call("GET", "/v1/me", undefined, b.token)).body.banned).toBeUndefined();
    expect((await call("PATCH", "/v1/me", {}, b.token)).body.banned).toBeUndefined();
    expect(codes((await call("GET", "/v1/friends", undefined, a.token)).body.friends)).toEqual([b.code]);
    expect((await call("POST", "/v1/party/join", { code: party }, b.token)).body.joined).toBe(true);
  });
});

describe("schema step 4", () => {
  it("adds the reports, bans and name holds tables to a database at version 3 and keeps its data", async () => {
    const stub = env.HUB.get(env.HUB.idFromName("before-reports"));
    await runInDurableObject(stub, (_, state) => {
      const sql = state.storage.sql;
      sql.exec("DROP TABLE reports");
      sql.exec("DROP TABLE bans");
      sql.exec("DROP TABLE name_holds");
      sql.exec("DROP TABLE used_identity_tokens");
      sql.exec("DROP TABLE grants");
      sql.exec("DROP TABLE suggestions");
      sql.exec("DROP TABLE crashes");
      sql.exec("DROP TABLE web_sign_ins");
      sql.exec("ALTER TABLE apple_accounts DROP COLUMN client_id");
      sql.exec("UPDATE schema_version SET version = 3");
      sql.exec("INSERT INTO blocks (blocker, blocked, created_at) VALUES ('AAAAAAAA', 'BBBBBBBB', 0)");
      migrate(state.storage);
      expect(sql.exec("SELECT version FROM schema_version").toArray()).toEqual([{ version: 11 }]);
      expect(sql.exec("SELECT * FROM reports").toArray()).toEqual([]);
      expect(sql.exec("SELECT * FROM bans").toArray()).toEqual([]);
      expect(sql.exec("SELECT * FROM name_holds").toArray()).toEqual([]);
      expect(sql.exec("SELECT blocker FROM blocks").toArray()).toEqual([{ blocker: "AAAAAAAA" }]);
    });
  });
});

describe("schema step 6", () => {
  it("splits each old name hold into one row per replaced name and drops held placeholders", async () => {
    const stub = env.HUB.get(env.HUB.idFromName("before-name-holds-by-value"));
    await runInDurableObject(stub, (_, state) => {
      const sql = state.storage.sql;
      // A version 5 database: one hold row per user with both names, placeholders included.
      sql.exec("DROP TABLE grants");
      sql.exec("DROP TABLE suggestions");
      sql.exec("DROP TABLE crashes");
      sql.exec("DROP TABLE web_sign_ins");
      sql.exec("ALTER TABLE apple_accounts DROP COLUMN client_id");
      sql.exec("DROP TABLE name_holds");
      sql.exec(`CREATE TABLE name_holds (code TEXT PRIMARY KEY, name TEXT NOT NULL, pet_name TEXT NOT NULL,
        created_at INTEGER NOT NULL) WITHOUT ROWID`);
      sql.exec("INSERT INTO name_holds VALUES ('AAAAAAAA', 'Rude', 'Worse', 7), ('BBBBBBBB', 'student', 'Bad Pet', 8)");
      sql.exec("UPDATE schema_version SET version = 5");
      migrate(state.storage);
      expect(sql.exec("SELECT version FROM schema_version").toArray()).toEqual([{ version: 11 }]);
      expect(sql.exec("SELECT code, kind, value, created_at FROM name_holds ORDER BY code, kind").toArray()).toEqual([
        { code: "AAAAAAAA", kind: "name", value: "Rude", created_at: 7 },
        { code: "AAAAAAAA", kind: "pet", value: "Worse", created_at: 7 },
        { code: "BBBBBBBB", kind: "pet", value: "Bad Pet", created_at: 8 },
      ]);
    });
  });
});
