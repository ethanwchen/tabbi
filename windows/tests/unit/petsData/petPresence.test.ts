import { describe, expect, it } from "vitest";
import { PetAnimator, PetClipSet, activityForMood } from "../../../src/core/pets/petAnimator";
import { ProvidedFocus } from "../../../src/core/providers/providedFocus";
import { PetPresence } from "../../../src/core/pets/petPresence";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { REFERENCE_DATE_OFFSET } from "../../../src/core/pets/petUnlocks";
import type { DayCalendar } from "../../../src/core/streaks/dayCalendar";

// Port of PetPresenceTests.swift. The Mac drives these with a FocusTimer;
// here the shared clock it would provide is written out directly.

const start = 800_000_000 + REFERENCE_DATE_OFFSET;
const profile = PetProfile.starter("cat");
const calendar: DayCalendar = { timeZone: "America/New_York", firstWeekday: 1 };

const minutes = (value: number) => start + value * 60;

const idleTimer = new ProvidedFocus({ source: "focus", phase: "focus", clock: { kind: "idle" }, phaseLength: 25 * 60, completedFocusCount: 0 });

function focusRunning(since: number): ProvidedFocus {
  return new ProvidedFocus({ source: "focus", phase: "focus", clock: { kind: "countdown", endsAt: since + 25 * 60 }, phaseLength: 25 * 60, completedFocusCount: 0 });
}

function breakRunning(since: number): ProvidedFocus {
  return new ProvidedFocus({ source: "focus", phase: "rest", clock: { kind: "countdown", endsAt: since + 5 * 60 }, phaseLength: 5 * 60, completedFocusCount: 0 });
}

const presence = (lastActive = start) => new PetPresence(profile, lastActive, calendar);

describe("PetPresence", () => {
  it("is awake at first and falls asleep after a quiet spell", () => {
    const pet = presence();
    expect(pet.mood(undefined, minutes(19))).toBe("awake");
    expect(pet.mood(undefined, minutes(20))).toBe("asleep");
    expect(pet.mood(idleTimer, minutes(60)), "an idle timer is no session").toBe("asleep");
  });

  it("shows studying or a break whatever the quiet time", () => {
    const pet = presence();
    expect(pet.mood(focusRunning(minutes(59)), minutes(60))).toBe("studying");
    expect(pet.mood(breakRunning(minutes(59)), minutes(60))).toBe("onBreak");
  });

  it("keeps the pet awake through a paused session", () => {
    const paused = new ProvidedFocus({ source: "focus", phase: "focus", clock: { kind: "paused", shown: 24 * 60 }, phaseLength: 25 * 60, completedFocusCount: 0 });
    expect(presence().mood(paused, minutes(90))).toBe("awake");
  });

  it("counts ending a session as activity", () => {
    const pet = presence();
    pet.observe(focusRunning(minutes(30)), minutes(30));
    expect(pet.lastActive).toBe(minutes(30));
    pet.observe(idleTimer, minutes(55));
    expect(pet.lastActive).toBe(minutes(55));
    expect(pet.mood(idleTimer, minutes(74))).toBe("awake");
    expect(pet.mood(idleTimer, minutes(75))).toBe("asleep");
    pet.observe(undefined, minutes(80));
    expect(pet.lastActive).toBe(minutes(55));
  });

  it("never moves last active back", () => {
    const pet = presence(minutes(10));
    pet.observe(focusRunning(start), start);
    expect(pet.lastActive).toBe(minutes(10));
  });

  it("sleeps at the end of the quiet spell", () => {
    const pet = presence();
    expect(pet.sleepsAt(undefined, minutes(5))).toBe(minutes(20));
    expect(pet.sleepsAt(undefined, minutes(20)), "already asleep").toBeUndefined();
    expect(pet.sleepsAt(focusRunning(start), minutes(5))).toBeUndefined();
  });

  it("yawns when a long block ends, though the pet was drawn anew mid-block", () => {
    // The ticker hands the animator the phase start as the mood's start.
    const block = PetAnimator.longSession + 5 * 60;
    const focus = new ProvidedFocus({ source: "study", phase: "focus", clock: { kind: "countdown", endsAt: start + block }, phaseLength: block, completedFocusCount: 0 });
    const rebuiltAt = start + block - 60;
    const mood = presence().mood(focus, rebuiltAt);
    expect(mood).toBe("studying");
    const clips = new PetClipSet({ breed: profile.breed });
    const animator = new PetAnimator(clips.durations, { activity: activityForMood(mood), activitySince: start, at: rebuiltAt });
    const breakAt = start + block;
    animator.send({ kind: "activity", activity: "onBreak" }, breakAt);
    expect(animator.playback).toEqual({ animation: "yawn", startedAt: breakAt });
  });
});
