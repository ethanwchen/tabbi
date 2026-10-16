import { describe, expect, it } from "vitest";
import { MAX_TIMEOUT, WallClockAlarm, WATCHDOG_INTERVAL, type AlarmTimers } from "../../../src/ui/kit/clock";

/* A fake clock whose timeouts fire when the test advances it, and which can jump like a machine waking from sleep. */
class FakeTimers implements AlarmTimers {
  time = 1_000_000;
  private pending = new Map<number, { at: number; callback: () => void }>();
  private next = 1;
  now = () => this.time;
  setTimeout = (callback: () => void, ms: number) => {
    const id = this.next++;
    this.pending.set(id, { at: this.time + ms, callback });
    return id;
  };
  clearTimeout = (id: number) => {
    this.pending.delete(id);
  };
  /** Awake time passes: timers fire in order. */
  advance(ms: number) {
    const until = this.time + ms;
    for (;;) {
      const due = [...this.pending.entries()].filter(([, t]) => t.at <= until).sort((a, b) => a[1].at - b[1].at)[0];
      if (!due) break;
      this.time = due[1].at;
      this.pending.delete(due[0]);
      due[1].callback();
    }
    this.time = until;
  }
  /** The machine sleeps: the wall clock jumps, but awake timers do not. */
  sleep(ms: number) {
    for (const t of this.pending.values()) t.at += ms;
    this.time += ms;
  }
}

describe("WallClockAlarm", () => {
  it("fires at its moment on an awake machine", () => {
    const timers = new FakeTimers();
    let fired = 0;
    const alarm = new WallClockAlarm(() => fired++, timers);
    alarm.schedule(timers.time + 5000);
    timers.advance(4999);
    expect(fired).toBe(0);
    timers.advance(1);
    expect(fired).toBe(1);
    expect(alarm.date).toBeUndefined();
  });

  it("fires right away after a sleep that passed its moment", () => {
    const timers = new FakeTimers();
    let fired = 0;
    const alarm = new WallClockAlarm(() => fired++, timers);
    alarm.schedule(timers.time + 60_000);
    timers.advance(10_000);
    timers.sleep(120_000);
    expect(fired).toBe(0);
    /* The next watchdog tick sees the jump and re-arms from the wall clock. */
    timers.advance(WATCHDOG_INTERVAL);
    expect(fired).toBe(1);
  });

  it("cancels, and a later schedule replaces an earlier one", () => {
    const timers = new FakeTimers();
    let fired = 0;
    const alarm = new WallClockAlarm(() => fired++, timers);
    alarm.schedule(timers.time + 1000);
    alarm.cancel();
    timers.advance(2000);
    expect(fired).toBe(0);
    alarm.schedule(timers.time + 1000);
    alarm.schedule(timers.time + 3000);
    timers.advance(2000);
    expect(fired).toBe(0);
    timers.advance(1000);
    expect(fired).toBe(1);
  });

  it("waits out a moment more than 24.8 days away instead of firing at once", () => {
    /* Like the browser and Node: a delay past the 32-bit limit runs after 1 ms. */
    const timers = new FakeTimers();
    const platform: AlarmTimers = { ...timers, now: timers.now, clearTimeout: timers.clearTimeout, setTimeout: (callback, ms) => timers.setTimeout(callback, ms > MAX_TIMEOUT ? 1 : ms) };
    let fired = 0;
    const alarm = new WallClockAlarm(() => fired++, platform);
    const days = 26 * 24 * 60 * 60 * 1000;
    alarm.schedule(timers.time + days);
    timers.advance(1000);
    expect(fired).toBe(0);
    timers.advance(days - 1001);
    expect(fired).toBe(0);
    timers.advance(1);
    expect(fired).toBe(1);
  });
});
