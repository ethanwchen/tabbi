import { env, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import catalog from "../shared/catalog.json";
import type { Hub } from "../src/hub";
import { call, expectError, pinClockToMinuteStart, register } from "./helpers";

const now = () => Math.floor(Date.now() / 1000);

/** Moves the clock (seen by both the test and the Hub, which share an isolate) forward. */
function advance(seconds: number) {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(Date.now() + seconds * 1000);
}

/** The presence row as persisted in SQLite, bypassing the Hub's in-memory copy. */
async function storedPresence(code: string) {
  const stub = env.HUB.get(env.HUB.idFromName("hub"));
  return runInDurableObject(stub, (_hub: Hub, state) =>
    state.storage.sql.exec("SELECT * FROM presence WHERE code = ?", code).toArray()[0] ?? null);
}

async function friends(a: { token: string }, b: { code: string }) {
  await call("POST", "/v1/friends", { code: b.code }, a.token);
}

beforeEach(pinClockToMinuteStart);

afterEach(() => {
  vi.useRealTimers();
});

describe("presence", () => {
  it("records a heartbeat and returns the recommended interval", async () => {
    const a = await register();
    const phaseEndsAt = now() + 25 * 60;
    const r = await call("POST", "/v1/presence", {
      status: "studying", method: "pomodoro", phaseEndsAt, sessionMinutes: 5, todayMinutes: 90, streakDays: 3,
    }, a.token);
    expect(r.status).toBe(200);
    expect(r.body).toEqual({
      ok: true,
      presence: {
        status: "studying", method: "pomodoro", phaseEndsAt, sessionMinutes: 5, todayMinutes: 90, streakDays: 3,
        day: new Date().toISOString().slice(0, 10), lastSeen: expect.any(Number),
      },
      heartbeatSeconds: catalog.heartbeatSeconds.studying,
    });
    expect(Math.abs(r.body.presence.lastSeen - now())).toBeLessThanOrEqual(2);

    const idle = await call("POST", "/v1/presence", { status: "idle", method: "pomodoro", phaseEndsAt }, a.token);
    // Session fields are cleared outside a session; omitted counters keep their previous values.
    expect(idle.body.presence).toMatchObject({
      status: "idle", method: null, phaseEndsAt: null, sessionMinutes: 0, todayMinutes: 90, streakDays: 3,
    });
    expect(idle.body.heartbeatSeconds).toBe(catalog.heartbeatSeconds.idle);
    expect((await call("POST", "/v1/presence", { status: "offline" }, a.token)).body.heartbeatSeconds).toBeNull();
  });

  it("shows friends' presence and online flag", async () => {
    const a = await register({ name: "A" });
    const b = await register({ name: "B" });
    const c = await register({ name: "C" });
    await friends(a, b);
    await friends(a, c);

    let list = (await call("GET", "/v1/friends", undefined, a.token)).body.friends;
    expect(list.map((f: { presence: unknown; online: boolean }) => [f.presence, f.online])).toEqual([[null, false], [null, false]]);

    const phaseEndsAt = now() + 300;
    await call("POST", "/v1/presence", { status: "break", method: "52-17", phaseEndsAt, todayMinutes: 52 }, b.token);
    await call("POST", "/v1/presence", { status: "offline", todayMinutes: 10 }, c.token);
    list = (await call("GET", "/v1/friends", undefined, a.token)).body.friends;
    expect(list[0].online).toBe(true);
    expect(list[0].presence).toMatchObject({ status: "break", method: "52-17", phaseEndsAt, todayMinutes: 52 });
    expect(list[1].online).toBe(false);
    expect(list[1].presence).toMatchObject({ status: "offline", todayMinutes: 10 });
    // Presence is only shared with friends: the caller's own list does not include strangers.
    expect((await call("GET", "/v1/friends", undefined, b.token)).body.friends).toHaveLength(1);
  });

  it("marks a friend offline once heartbeats stop", async () => {
    const a = await register();
    const b = await register();
    const d = await register();
    await friends(a, b);
    await friends(a, d);
    await call("POST", "/v1/presence", { status: "studying", method: "anki", phaseEndsAt: now() + 3600, sessionMinutes: 20 }, b.token);
    await call("POST", "/v1/presence", { status: "idle" }, d.token);
    const byCode = async () => {
      const list = (await call("GET", "/v1/friends", undefined, a.token)).body.friends;
      return Object.fromEntries(list.map((f: { profile: { code: string } }) => [f.profile.code, f]));
    };

    // 2.5 studying intervals: still online.
    advance(catalog.heartbeatSeconds.studying * 2.5);
    expect((await byCode())[b.code].online).toBe(true);

    advance(1);
    const f = await byCode();
    expect(f[b.code].online).toBe(false);
    expect(f[b.code].presence).toMatchObject({ status: "offline", method: null, phaseEndsAt: null, sessionMinutes: 0 });
    // Idle heartbeats are rarer, so idle users stay online longer.
    expect(f[d.code].online).toBe(true);
    advance(catalog.heartbeatSeconds.idle * 2.5);
    expect((await byCode())[d.code].online).toBe(false);
  });

  it("writes to storage only on a visible change or every 10 minutes", async () => {
    const a = await register();
    const phaseEndsAt = now() + 1500;
    const beat = (extra: Record<string, unknown> = {}) =>
      call("POST", "/v1/presence", { status: "studying", method: "pomodoro", phaseEndsAt, ...extra }, a.token);

    await beat({ todayMinutes: 1 });
    expect(await storedPresence(a.code)).toMatchObject({ status: "studying", today_minutes: 1 });

    // Ticking counters alone are kept in memory; friends still see them.
    advance(120);
    await beat({ todayMinutes: 3 });
    expect(await storedPresence(a.code)).toMatchObject({ today_minutes: 1 });
    const b = await register();
    await friends(b, a);
    expect((await call("GET", "/v1/friends", undefined, b.token)).body.friends[0].presence.todayMinutes).toBe(3);

    // A new phase is a visible change and is written at once.
    await beat({ todayMinutes: 4, phaseEndsAt: phaseEndsAt + 300 });
    expect(await storedPresence(a.code)).toMatchObject({ today_minutes: 4, phase_ends_at: phaseEndsAt + 300 });

    advance(599);
    await beat({ todayMinutes: 14, phaseEndsAt: phaseEndsAt + 300 });
    expect(await storedPresence(a.code)).toMatchObject({ today_minutes: 4 });
    advance(1);
    await beat({ todayMinutes: 15, phaseEndsAt: phaseEndsAt + 300 });
    expect(await storedPresence(a.code)).toMatchObject({ today_minutes: 15 });
  });

  it("validates the heartbeat", async () => {
    const a = await register();
    const bad: Record<string, unknown>[] = [
      {},
      { status: "sleeping" },
      { status: 1 },
      { status: "studying", method: "cramming" },
      { status: "studying", phaseEndsAt: "soon" },
      { status: "studying", phaseEndsAt: now() + 2 * 86400 },
      { status: "studying", phaseEndsAt: now() - 2 * 86400 },
      { status: "studying", phaseEndsAt: now() + 0.5 },
      { status: "studying", sessionMinutes: -1 },
      { status: "studying", sessionMinutes: 1441 },
      { status: "studying", todayMinutes: 1.5 },
      { status: "studying", todayMinutes: "10" },
      { status: "studying", streakDays: 36501 },
      { status: "studying", day: "2026-02-30" },
      { status: "studying", day: "20261001" },
      { status: "studying", day: 20261001 },
      { status: "studying", day: new Date(Date.now() - 2 * 86400_000).toISOString().slice(0, 10) },
      { status: "studying", day: new Date(Date.now() + 2 * 86400_000).toISOString().slice(0, 10) },
    ];
    for (const body of bad) expectError(await call("POST", "/v1/presence", body, a.token), 400, "invalid_field");
    expectError(await call("POST", "/v1/presence", { status: "idle", deck: "Cardio" }, a.token), 400, "unknown_field");
    expectError(await call("POST", "/v1/presence", "nope", a.token), 400, "invalid_json");
    expectError(await call("POST", "/v1/presence", { status: "idle" }), 401, "unauthorized");
    // Nothing was stored by the rejected heartbeats.
    expect(await storedPresence(a.code)).toBeNull();
    // Nulls are accepted for the optional session fields.
    const ok = await call("POST", "/v1/presence", { status: "studying", method: null, phaseEndsAt: null }, a.token);
    expect(ok.body.presence).toMatchObject({ status: "studying", method: null, phaseEndsAt: null });
  });

  it("forgets presence when the account is deleted", async () => {
    const a = await register();
    await call("POST", "/v1/presence", { status: "studying" }, a.token);
    expect(await storedPresence(a.code)).not.toBeNull();
    await call("DELETE", "/v1/me", undefined, a.token);
    expect(await storedPresence(a.code)).toBeNull();
  });
});
