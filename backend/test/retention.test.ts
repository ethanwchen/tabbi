import { runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import catalog from "../shared/catalog.json";
import { LIVE_IDLE_S, RETENTION_SWEEP_S, type Hub } from "../src/hub";
import { STUDY_DAY_RETENTION_DAYS } from "../src/leaderboard";
import { utcDay } from "../src/lib";
import { call, hub, pinClockToMinuteStart, register } from "./helpers";

const EXPIRY = catalog.limits.partyIdleExpirySeconds;
const nowS = () => Math.floor(Date.now() / 1000);

function advance(seconds: number) {
  vi.setSystemTime(Date.now() + seconds * 1000);
}

const rows = (sql: string, ...params: unknown[]) =>
  runInDurableObject(hub(), (_hub: Hub, state) => state.storage.sql.exec(sql, ...params).toArray());

beforeEach(pinClockToMinuteStart);

afterEach(() => {
  vi.useRealTimers();
});

describe("retention sweep", () => {
  it("keeps an alarm scheduled, and schedules the next sweep one interval after each run", async () => {
    await register();
    const at = await runInDurableObject(hub(), (_hub: Hub, state) => state.storage.getAlarm());
    expect(at).not.toBeNull();

    expect(await runDurableObjectAlarm(hub())).toBe(true);
    const next = await runInDurableObject(hub(), (_hub: Hub, state) => state.storage.getAlarm());
    expect(next).toBe(Date.now() + RETENTION_SWEEP_S * 1000);
  });

  it("deletes idle parties nobody touches, and keeps live ones", async () => {
    const a = await register();
    const b = await register();
    const idle = (await call("POST", "/v1/party", undefined, a.token)).body.party;
    advance(EXPIRY - 60);
    const live = (await call("POST", "/v1/party", undefined, b.token)).body.party;
    advance(60);

    expect(await runDurableObjectAlarm(hub())).toBe(true);
    expect(await rows("SELECT code FROM parties WHERE code = ?", idle.code)).toEqual([]);
    expect(await rows("SELECT code FROM party_members WHERE party = ?", idle.code)).toEqual([]);
    expect(await rows("SELECT code FROM party_members WHERE party = ?", live.code)).toEqual([{ code: b.code }]);
  });

  it("deletes study minutes past their retention for users who stopped sending heartbeats", async () => {
    const a = await register();
    // Other tests' sweeps may have run on the days around now in this isolate (the Hub deletes study
    // minutes once per UTC day), so this test moves to a day none of them reaches.
    advance(1000 * 86_400);
    const keep = utcDay(nowS() - STUDY_DAY_RETENTION_DAYS * 86_400);
    const drop = utcDay(nowS() - (STUDY_DAY_RETENTION_DAYS + 1) * 86_400);
    await runInDurableObject(hub(), (_hub: Hub, state) => {
      for (const day of [drop, keep]) state.storage.sql.exec("INSERT INTO study_days (code, day, minutes) VALUES (?, ?, 30)", a.code, day);
    });

    expect(await runDurableObjectAlarm(hub())).toBe(true);
    expect(await rows("SELECT day FROM study_days WHERE code = ?", a.code)).toEqual([{ day: keep }]);
  });

  it("deletes identity token hashes once their token has expired", async () => {
    await register();
    await runInDurableObject(hub(), (_hub: Hub, state) => {
      state.storage.sql.exec("INSERT INTO used_identity_tokens (token_hash, expires_at) VALUES ('old', ?), ('new', ?)", nowS() - 1, nowS() + 600);
    });

    expect(await runDurableObjectAlarm(hub())).toBe(true);
    expect(await rows("SELECT token_hash FROM used_identity_tokens WHERE token_hash IN ('old', 'new')")).toEqual([{ token_hash: "new" }]);
  });

  it("writes and drops the live presence of users who stopped sending heartbeats, and keeps active ones", async () => {
    const a = await register();
    const b = await register();
    await call("POST", "/v1/presence", { status: "studying", todayMinutes: 10 }, a.token);
    advance(120);
    // Not written yet: only the minutes changed since the last write.
    await call("POST", "/v1/presence", { status: "studying", todayMinutes: 12 }, a.token);
    const lastSeen = nowS();
    expect(await rows("SELECT last_seen, today_minutes FROM presence WHERE code = ?", a.code))
      .toEqual([{ last_seen: lastSeen - 120, today_minutes: 10 }]);
    advance(LIVE_IDLE_S - 60);
    await call("POST", "/v1/presence", { status: "idle" }, b.token);
    advance(60);

    expect(await runDurableObjectAlarm(hub())).toBe(true);
    const live = await runInDurableObject(hub(), (h: Hub) => (h as unknown as { live: Map<string, unknown> }).live);
    expect(live.has(a.code)).toBe(false);
    expect(live.has(b.code)).toBe(true);
    expect(await rows("SELECT last_seen, today_minutes FROM presence WHERE code = ?", a.code))
      .toEqual([{ last_seen: lastSeen, today_minutes: 12 }]);
    expect(await rows("SELECT minutes FROM study_days WHERE code = ?", a.code)).toEqual([{ minutes: 12 }]);

    // Back from the row, the user shows offline to friends with the minutes they studied.
    await call("POST", "/v1/friends", { code: a.code }, b.token);
    const { friends } = (await call("GET", "/v1/friends", undefined, b.token)).body;
    expect(friends[0].profile.code).toBe(a.code);
    expect(friends[0].presence).toMatchObject({ status: "offline", todayMinutes: 12, lastSeen });
  });
});
