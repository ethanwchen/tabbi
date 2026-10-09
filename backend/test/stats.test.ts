import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { SIGNUP_DAYS, activeCounts, signupsByDay, signupsSince } from "../src/stats";
import { utcDay } from "../src/lib";
import { admin, call, expectError, freshIp, linkAppleAccount, pinClockToMinuteStart, register } from "./helpers";

const DAY = 86_400;
const nowS = () => Math.floor(Date.now() / 1000);
const advance = (seconds: number) => vi.setSystemTime(Date.now() + seconds * 1000);
const heartbeat = (token: string) =>
  call("POST", "/v1/presence", { status: "idle", sessionMinutes: 0, todayMinutes: 0, streakDays: 0 }, token);
const stats = async () => {
  const r = await admin("GET", "/stats");
  expect(r.status).toBe(200);
  return r.body;
};

describe("activeCounts", () => {
  const now = 100 * DAY;

  it("counts persisted rows and adds users whose newer heartbeat is only in memory", () => {
    // Rows' last_seen: two users with live heartbeats, one without, and one long gone.
    const rows = [now - 5, now - DAY - 50, now - 3 * DAY, now - 40 * DAY];
    const persisted = (since: number) => rows.filter((t) => t >= since).length;
    const live = [
      { lastSeen: now - 5, flushedAt: now - 5 }, // already counted by its row
      { lastSeen: now - 100, flushedAt: now - DAY - 50 }, // its row is just outside the day
      { lastSeen: now - 40 * DAY, flushedAt: now - 40 * DAY }, // too old for any window
    ];
    expect(activeCounts(persisted, live, now)).toEqual({ day: 2, week: 3, month: 3 });
  });

  it("is all zero with no heartbeats", () => {
    expect(activeCounts(() => 0, [], now)).toEqual({ day: 0, week: 0, month: 0 });
  });
});

describe("signupsByDay", () => {
  it("lists every one of the last days oldest first, with zero for days without sign-ups", () => {
    const now = Date.UTC(2026, 9, 9, 15) / 1000;
    const days = signupsByDay(new Map([["2026-10-09", 3], ["2026-09-10", 1], ["2026-09-09", 7]]), now);
    expect(days).toHaveLength(SIGNUP_DAYS);
    expect(days[0]).toEqual({ day: "2026-09-10", users: 1 });
    expect(days.at(-1)).toEqual({ day: "2026-10-09", users: 3 });
    expect(days.slice(1, -1).every((d) => d.users === 0)).toBe(true);
    expect(utcDay(signupsSince(now))).toBe("2026-09-10");
    expect(signupsSince(now) % DAY).toBe(0);
  });
});

describe("GET /v1/admin/stats", () => {
  beforeEach(pinClockToMinuteStart);
  afterEach(() => vi.useRealTimers());

  it("looks like an unknown path without the admin token", async () => {
    const user = await register();
    for (const token of [undefined, user.token, "f".repeat(64)]) {
      expectError(await call("GET", "/v1/admin/stats", undefined, token, freshIp()), 404, "not_found");
    }
  });

  it("returns only aggregate counts", async () => {
    const body = await stats();
    expect(Object.keys(body).sort()).toEqual(["active", "at", "hub", "ok", "parties", "signups", "suggestions", "users"]);
    expect(body.at).toBe(nowS());
    expect(JSON.stringify(body)).not.toMatch(/"code"|"name"|"token"/);
  });

  it("counts users, sign-ins, sign-ups per day, parties and active users", async () => {
    // Far enough ahead that every earlier heartbeat and sign-up in this file is outside all windows.
    advance(400 * DAY);
    const before = await stats();
    expect(before.active).toEqual({ day: 0, week: 0, month: 0 });
    expect(before.signups.every((d: { users: number }) => d.users === 0)).toBe(true);

    const signupDay = utcDay(nowS());
    const a = await register();
    const b = await register();
    await linkAppleAccount(b.code);
    await call("POST", "/v1/party", undefined, a.token);
    expect((await heartbeat(a.token)).status).toBe(200);
    // Five minutes later: the Hub keeps this heartbeat in memory without writing the row.
    advance(300);
    expect((await heartbeat(a.token)).status).toBe(200);

    const after = await stats();
    expect(after.users.total - before.users.total).toBe(2);
    expect(after.users.signedIn - before.users.signedIn).toBe(1);
    expect(after.signups.at(-1)).toEqual({ day: signupDay, users: 2 });
    expect(after.parties.open - before.parties.open).toBe(1);
    expect(after.parties.members - before.parties.members).toBe(1);
    expect(after.active).toEqual({ day: 1, week: 1, month: 1 });

    // A day after the written row but not after the in-memory heartbeat: still active today.
    advance(DAY - 200);
    expect((await stats()).active).toEqual({ day: 1, week: 1, month: 1 });

    advance(7 * DAY);
    const later = await stats();
    expect(later.active).toEqual({ day: 0, week: 0, month: 1 });
    expect(later.parties.open).toBe(before.parties.open);
    expect(later.signups.find((d: { day: string }) => d.day === signupDay)).toEqual({ day: signupDay, users: 2 });

    advance(30 * DAY);
    expect((await stats()).active).toEqual({ day: 0, week: 0, month: 0 });
  });

  it("counts this instance's requests and SQLite rows, which is what a route costs", async () => {
    const user = await register();
    const usage = async () => (await stats()).hub as { since: number; requests: number; rowsRead: number; rowsWritten: number };
    // The difference between two stats calls is the cost of the requests in between plus one stats call.
    const a = await usage();
    const b = await usage();
    const statsCall = { requests: b.requests - a.requests, rowsRead: b.rowsRead - a.rowsRead, rowsWritten: b.rowsWritten - a.rowsWritten };
    expect(statsCall.requests).toBe(1);
    expect(statsCall.rowsWritten).toBe(0);
    const cost = async (run: () => Promise<unknown>) => {
      const before = await usage();
      await run();
      const after = await usage();
      return {
        requests: after.requests - before.requests - statsCall.requests,
        rowsRead: after.rowsRead - before.rowsRead - statsCall.rowsRead,
        rowsWritten: after.rowsWritten - before.rowsWritten - statsCall.rowsWritten,
      };
    };
    expect(b.since).toBeLessThanOrEqual(nowS());

    // The first heartbeat writes the presence row; an unchanged one a minute later writes nothing.
    const first = await cost(() => heartbeat(user.token));
    expect(first.requests).toBe(1);
    expect(first.rowsWritten).toBeGreaterThan(0);
    advance(60);
    const steady = await cost(() => heartbeat(user.token));
    expect(steady).toMatchObject({ requests: 1, rowsWritten: 0 });
    expect(steady.rowsRead).toBeGreaterThan(0);
    expect(steady.rowsRead).toBeLessThanOrEqual(4); // the token lookup through its index

    // Starting a session is visible to friends, so it writes the presence row right away, and the
    // day's new study minutes with it.
    const changed = await cost(() => call("POST", "/v1/presence", { status: "studying", method: "pomodoro", todayMinutes: 5 }, user.token));
    expect(changed).toMatchObject({ requests: 1, rowsWritten: 2 });
  });
});
