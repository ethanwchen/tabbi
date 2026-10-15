import { describe, expect, it } from "vitest";
import { ProvidedFocus } from "../../../src/core/providers/providedFocus";
import { PetNightRhythm } from "../../../src/core/pets/petNightRhythm";
import { PetPresence } from "../../../src/core/pets/petPresence";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { zonedInstant, type DayCalendar } from "../../../src/core/streaks/dayCalendar";

// Port of PetNightRhythmTests.swift.

const rhythm = PetNightRhythm.standard;

function calendar(zone: string): DayCalendar {
  return { timeZone: zone, firstWeekday: 1 };
}

function date(hour: number, minute = 0, zone = "America/New_York"): number {
  return zonedInstant(2026, 10, 11, hour, minute, 0, zone);
}

function runningFocus(now: number): ProvidedFocus {
  return new ProvidedFocus({ source: "focus", phase: "focus", clock: { kind: "countdown", endsAt: now + 600 }, phaseLength: 25 * 60, completedFocusCount: 0 });
}

const ny = calendar("America/New_York");

describe("PetNightRhythm", () => {
  it("wraps the night window past midnight", () => {
    expect(rhythm.isNight(date(22, 59), ny)).toBe(false);
    expect(rhythm.isNight(date(23), ny)).toBe(true);
    expect(rhythm.isNight(date(0, 30), ny)).toBe(true);
    expect(rhythm.isNight(date(5, 59), ny)).toBe(true);
    expect(rhythm.isNight(date(6), ny)).toBe(false);
    expect(rhythm.isNight(date(14), ny)).toBe(false);
  });

  it("follows local time across a time zone change", () => {
    const moment = date(2);
    expect(rhythm.isNight(moment, ny)).toBe(true);
    expect(rhythm.isNight(moment, calendar("Europe/London"))).toBe(false);
    const afternoon = date(15);
    expect(rhythm.isNight(afternoon, ny)).toBe(false);
    expect(rhythm.isNight(afternoon, calendar("Asia/Tokyo"))).toBe(true);
  });

  it("dozes at night without a session", () => {
    expect(rhythm.dozes(date(1), undefined, undefined, ny)).toBe(true);
    expect(rhythm.dozes(date(13), undefined, undefined, ny)).toBe(false);
  });

  it("keeps the pet awake through a running or paused session", () => {
    const now = date(1);
    expect(rhythm.dozes(now, runningFocus(now), undefined, ny)).toBe(false);
    const paused = new ProvidedFocus({ source: "focus", phase: "focus", clock: { kind: "paused", shown: 300 }, phaseLength: 1500, completedFocusCount: 0 });
    expect(rhythm.dozes(now, paused, undefined, ny)).toBe(false);
    const idle = new ProvidedFocus({ source: "focus", phase: "focus", clock: { kind: "idle" }, phaseLength: 1500, completedFocusCount: 0 });
    expect(rhythm.dozes(now, idle, undefined, ny)).toBe(true);
  });

  it("wakes the pet for a quiet spell when the island opens", () => {
    const woke = date(1);
    expect(rhythm.dozes(woke, undefined, woke, ny)).toBe(false);
    expect(rhythm.dozes(woke + rhythm.wakeSpell - 1, undefined, woke, ny)).toBe(false);
    expect(rhythm.dozes(woke + rhythm.wakeSpell, undefined, woke, ny)).toBe(true);
  });

  it("never keeps the pet up forever for a wake in the future", () => {
    expect(rhythm.dozes(date(1), undefined, date(3), ny)).toBe(true);
  });

  it("supports a daytime window and an empty one", () => {
    const utc = calendar("UTC");
    const nap = new PetNightRhythm(13, 15, 0);
    expect(nap.isNight(date(14, 0, "UTC"), utc)).toBe(true);
    expect(nap.isNight(date(15, 0, "UTC"), utc)).toBe(false);
    const never = new PetNightRhythm(4, 4, 0);
    expect(never.isNight(date(4, 0, "UTC"), utc)).toBe(false);
  });

  const presence = (lastActive: number) => new PetPresence(PetProfile.starter("cat"), lastActive, ny, { night: rhythm });

  it("dozes after the shorter wake spell at night", () => {
    const pet = presence(date(23, 30));
    expect(pet.mood(undefined, date(23, 39))).toBe("awake");
    expect(pet.mood(undefined, date(23, 40))).toBe("asleep");
    expect(pet.mood(runningFocus(date(23, 45)), date(23, 45))).toBe("studying");
  });

  it("wakes only at night when the island opens", () => {
    const pet = presence(date(12));
    pet.wake(date(14));
    expect(pet.mood(undefined, date(14, 1))).toBe("asleep");
    pet.wake(date(23, 50));
    expect(pet.mood(undefined, date(23, 55))).toBe("awake");
    expect(pet.mood(undefined, date(23, 50) + rhythm.wakeSpell)).toBe("asleep");
  });

  it("ends the night doze in the morning", () => {
    const pet = presence(date(5, 45));
    expect(pet.mood(undefined, date(5, 55))).toBe("asleep");
    expect(pet.mood(undefined, date(6))).toBe("awake");
    expect(pet.mood(undefined, date(6, 5))).toBe("asleep");
  });

  it("schedules a wake at each night change", () => {
    const pet = presence(date(22));
    expect(pet.sleepsAt(undefined, date(22, 30))).toBe(date(23));
    const woken = presence(date(22));
    woken.wake(date(23, 30));
    expect(woken.sleepsAt(undefined, date(23, 31))).toBe(date(23, 40));
    expect(pet.sleepsAt(runningFocus(date(23)), date(23))).toBeUndefined();
  });

  it("places the night in the calendar's time zone", () => {
    const pet = presence(date(0));
    expect(pet.mood(undefined, date(2))).toBe("asleep");
    pet.calendar = calendar("Europe/London");
    expect(pet.mood(undefined, date(2))).toBe("asleep");
    pet.wake(date(2));
    expect(pet.mood(undefined, date(2, 1)), "opening the island in the London morning doesn't wake it").toBe("asleep");
    pet.calendar = ny;
    expect(pet.mood(undefined, date(2, 1)), "but it does at 2 AM in New York").toBe("awake");
  });

  it("finds the next night start or end", () => {
    expect(rhythm.nextBoundary(date(12), ny)).toBe(date(23));
    expect(rhythm.nextBoundary(date(3), ny)).toBe(date(6));
    expect(new PetNightRhythm(5, 5, 0).nextBoundary(date(3), ny)).toBeUndefined();
  });
});
