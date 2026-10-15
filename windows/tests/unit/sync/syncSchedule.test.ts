import { describe, expect, it } from "vitest";
import { PartyError } from "../../../src/core/party/partyError";
import { SyncSchedule } from "../../../src/core/sync/syncSchedule";

// When sync rounds run: on launch and resume, about 30 s after progress
// settles, once on quit, and backing off after failures.

describe("SyncSchedule", () => {
  it("syncs at once on launch and on resume, and not on a timer otherwise", () => {
    const schedule = new SyncSchedule();
    expect(schedule.nextDue()).toBeUndefined();
    schedule.launched(100);
    expect(schedule.isDue(100)).toBe(true);
    schedule.willSync();
    schedule.didSync();
    expect(schedule.nextDue()).toBeUndefined();
    schedule.resumed(5000);
    expect(schedule.nextDue()).toBe(5000);
  });

  it("debounces progress changes by about 30 s", () => {
    const schedule = new SyncSchedule();
    schedule.progressChanged(0);
    expect(schedule.nextDue()).toBe(30);
    schedule.progressChanged(20);
    expect(schedule.nextDue(), "a new change moves the round on").toBe(50);
    expect(schedule.isDue(49)).toBe(false);
    expect(schedule.isDue(50)).toBe(true);
  });

  it("never lets a stream of changes hold a round back for more than two minutes", () => {
    const schedule = new SyncSchedule();
    for (let time = 0; time <= 200; time += 10) schedule.progressChanged(time);
    expect(schedule.nextDue()).toBe(SyncSchedule.maxWait);
  });

  it("syncs once on quit only with unsynced progress", () => {
    const schedule = new SyncSchedule();
    expect(schedule.quitting()).toBe(false);
    schedule.progressChanged(0);
    expect(schedule.quitting()).toBe(true);
    schedule.willSync();
    expect(schedule.quitting()).toBe(false);
  });

  it("backs off 5 s, 10 s, 20 s, capped at 5 minutes, on outages and network errors", () => {
    const schedule = new SyncSchedule();
    const delays: number[] = [];
    for (let attempt = 0; attempt < 8; attempt += 1) {
      schedule.willSync();
      const at = schedule.didFail(attempt % 2 === 0 ? PartyError.of("serverUnavailable") : PartyError.of("unreachable"), 1000);
      delays.push((at ?? 0) - 1000);
    }
    expect(delays).toEqual([5, 10, 20, 40, 80, 160, 300, 300]);
    schedule.didSync();
    schedule.willSync();
    expect(schedule.didFail(PartyError.of("timedOut"), 0)).toBe(5);
  });

  it("waits Retry-After on 429 and holds triggers back until then", () => {
    const schedule = new SyncSchedule();
    expect(schedule.didFail(PartyError.rateLimited(42), 100)).toBe(142);
    schedule.progressChanged(101);
    expect(schedule.nextDue()).toBe(142);
  });

  it("waits for the next trigger after a failure retrying can't fix", () => {
    const schedule = new SyncSchedule();
    schedule.willSync();
    expect(schedule.didFail(PartyError.server("no_account", 403), 0)).toBeUndefined();
    expect(schedule.nextDue()).toBeUndefined();
    expect(schedule.hasPendingChanges).toBe(true);
  });
});
