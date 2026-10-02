import { env, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { Hub } from "../src/hub";
import { rankEntries } from "../src/leaderboard";
import type { Profile } from "../src/profile";
import { call, expectError, register } from "./helpers";

/** Sets the clock (seen by both the test and the Hub, which share an isolate) to an ISO time. */
function setTime(iso: string) {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(iso));
}

function advance(seconds: number) {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(Date.now() + seconds * 1000);
}

async function sql<T>(query: string, ...args: unknown[]): Promise<T[]> {
  const stub = env.HUB.get(env.HUB.idFromName("hub"));
  return runInDurableObject(stub, (_hub: Hub, state) => state.storage.sql.exec(query, ...args).toArray() as T[]);
}

const storedDays = (code: string) =>
  sql<{ day: string; minutes: number }>("SELECT day, minutes FROM study_days WHERE code = ? ORDER BY day", code);

const beat = (user: { token: string }, body: Record<string, unknown>) =>
  call("POST", "/v1/presence", { status: "studying", ...body }, user.token);

async function board(user: { token: string }) {
  const r = await call("GET", "/v1/leaderboard", undefined, user.token);
  expect(r.status).toBe(200);
  return r.body;
}

const summary = (b: { entries: { rank: number; minutes: number; me: boolean; profile: { code: string } }[] }) =>
  b.entries.map((e) => [e.profile.code, e.rank, e.minutes, e.me]);

afterEach(() => {
  vi.useRealTimers();
});

describe("weekly leaderboard", () => {
  it("sums this week's minutes of the caller and their friends", async () => {
    const a = await register({ name: "Ana" });
    const b = await register({ name: "Ben" });
    const c = await register({ name: "Cy" });
    const stranger = await register({ name: "Zed" });
    await call("POST", "/v1/friends", { code: b.code }, a.token);
    await call("POST", "/v1/friends", { code: c.code }, a.token);

    // Sunday belongs to the previous ISO week.
    setTime("2027-02-28T20:00:00Z");
    await beat(a, { day: "2027-02-28", todayMinutes: 45 });
    advance(14 * 3600); // Monday 10:00
    await beat(a, { day: "2027-03-01", todayMinutes: 60 });
    advance(86_400); // Tuesday
    await beat(a, { day: "2027-03-02", todayMinutes: 30 });
    await beat(b, { day: "2027-03-02", todayMinutes: 85 });
    // Not flushed yet (no visible change, flushed 2 minutes ago), but the leaderboard sees it.
    advance(120);
    await beat(b, { day: "2027-03-02", todayMinutes: 90 });
    expect(await storedDays(b.code)).toEqual([{ day: "2027-03-02", minutes: 85 }]);
    await beat(stranger, { day: "2027-03-02", todayMinutes: 500 });

    const body = await board(a);
    expect(body).toMatchObject({ ok: true, week: "2027-W09", from: "2027-03-01", to: "2027-03-07" });
    // Equal minutes share a rank and the next rank skips; strangers are not listed.
    expect(summary(body)).toEqual([[a.code, 1, 90, true], [b.code, 1, 90, false], [c.code, 3, 0, false]]);
    expect(body.entries[0].profile).toMatchObject({ code: a.code, name: "Ana" });
    expect(summary(await board(b))).toEqual([[a.code, 1, 90, false], [b.code, 1, 90, true]]);
    expect(summary(await board(stranger))).toEqual([[stranger.code, 1, 500, true]]);

    // The next week starts from zero.
    advance(6 * 86_400);
    expect((await board(a)).week).toBe("2027-W10");
    expect(summary(await board(a)).map((e) => e[2])).toEqual([0, 0, 0]);
  });

  it("counts a local day in the week it belongs to", async () => {
    const a = await register();
    // 23:00 UTC on Sunday is already Monday in UTC+1.
    setTime("2027-03-07T23:00:00Z");
    await beat(a, { day: "2027-03-08", todayMinutes: 20 });
    expect(summary(await board(a))).toEqual([[a.code, 1, 0, true]]);
    advance(2 * 3600);
    expect(summary(await board(a))).toEqual([[a.code, 1, 20, true]]);
  });

  it("closes out the previous day with its final count on a new day", async () => {
    const a = await register();
    setTime("2027-03-03T22:00:00Z");
    await beat(a, { day: "2027-03-03", todayMinutes: 10 });
    advance(120);
    await beat(a, { day: "2027-03-03", todayMinutes: 15 });
    expect(await storedDays(a.code)).toEqual([{ day: "2027-03-03", minutes: 10 }]);
    advance(2 * 3600);
    // A new day without todayMinutes starts counting from 0.
    const r = await beat(a, { day: "2027-03-04" });
    expect(r.body.presence).toMatchObject({ day: "2027-03-04", todayMinutes: 0 });
    expect(await storedDays(a.code)).toEqual([{ day: "2027-03-03", minutes: 15 }]);
    expect(summary(await board(a))).toEqual([[a.code, 1, 15, true]]);
  });

  it("defaults to the UTC day, skips zero counts and lets a client correct a count", async () => {
    const a = await register();
    setTime("2027-03-03T12:00:00Z");
    await call("POST", "/v1/presence", { status: "idle" }, a.token);
    expect(await storedDays(a.code)).toEqual([]);
    await beat(a, { todayMinutes: 40, method: "anki" });
    expect(await storedDays(a.code)).toEqual([{ day: "2027-03-03", minutes: 40 }]);
    await beat(a, { todayMinutes: 0, method: "qbank" });
    expect(await storedDays(a.code)).toEqual([{ day: "2027-03-03", minutes: 0 }]);
  });

  it("forgets study days older than 4 weeks", async () => {
    const a = await register();
    await sql("INSERT INTO study_days (code, day, minutes) VALUES (?, '2027-01-01', 5), (?, '2027-02-20', 7)", a.code, a.code);
    setTime("2027-03-03T12:00:00Z");
    await beat(a, { todayMinutes: 1 });
    advance(86_400);
    await beat(a, { todayMinutes: 2 });
    expect((await storedDays(a.code)).map((d) => d.day)).toEqual(["2027-02-20", "2027-03-03", "2027-03-04"]);
  });

  it("requires a token and forgets study days when the account is deleted", async () => {
    expectError(await call("GET", "/v1/leaderboard"), 401, "unauthorized");
    const a = await register();
    await beat(a, { todayMinutes: 30 });
    expect(await storedDays(a.code)).toHaveLength(1);
    await call("DELETE", "/v1/me", undefined, a.token);
    expect(await storedDays(a.code)).toEqual([]);
  });

  it("upgrades presence storage created before the day column existed", async () => {
    const stub = env.HUB.get(env.HUB.idFromName("hub"));
    const columns = await runInDurableObject(stub, (hub: Hub, state) => {
      state.storage.sql.exec("ALTER TABLE presence DROP COLUMN day");
      (hub as unknown as { migrate(): void }).migrate();
      return state.storage.sql.exec<{ name: string }>("SELECT name FROM pragma_table_info('presence')").toArray().map((c) => c.name);
    });
    expect(columns).toContain("day");
    const a = await register();
    expect((await beat(a, { todayMinutes: 3 })).status).toBe(200);
  });

  it("ranks by minutes, then name", () => {
    const p = (code: string, name: string) => ({ code, name } as Profile);
    const ranked = rankEntries([
      { minutes: 5, me: false, profile: p("C", "cy") },
      { minutes: 9, me: true, profile: p("B", "Bo") },
      { minutes: 5, me: false, profile: p("A", "al") },
      { minutes: 1, me: false, profile: p("D", "Al") },
    ]);
    expect(ranked.map((e) => [e.profile.code, e.rank])).toEqual([["B", 1], ["A", 2], ["C", 2], ["D", 4]]);
  });
});
