import { describe, expect, it } from "vitest";
import { PetCoachGlance } from "../../../src/core/coach/petCoachGlance";
import { COACH_WALK_FRAME_RATE, glanceNextRedraw, strollNextRedraw } from "../../../src/core/coach/petCoachRedraw";
import { PetCoachStroll, type PetCoachStrollPhase } from "../../../src/core/coach/petCoachStroll";
import { cachedClipSet } from "../../../src/core/pets/petAnimator";
import type { PetAnimation } from "../../../src/core/pets/petKinds";
import { PetProfile } from "../../../src/core/pets/petProfile";

const t0 = 1_800_000_000;
const at = (seconds: number) => t0 + seconds;

/* 100 at 50 per second: two seconds each way, ten seconds of talking. */
const stroll = () => new PetCoachStroll(t0, { distance: 100, speed: 50, talkDuration: 10 });

describe("PetCoachStroll", () => {
  it("walks out, talks and walks back when unanswered", () => {
    const s = stroll();
    expect(s.phase(at(1))).toBe("walkingOut");
    expect(s.phase(at(2))).toBe("talking");
    expect(s.phase(at(11.9))).toBe("talking");
    expect(s.phase(at(12))).toBe("walkingBack");
    expect(s.phase(at(14))).toBe("finished");
    expect(s.endsAt).toBe(at(14));
  });

  it("moves at walking speed and holds still while talking", () => {
    const s = stroll();
    expect(s.offset(at(-1))).toBe(0);
    expect(s.offset(at(1))).toBeCloseTo(50, 3);
    expect(s.offset(at(5))).toBeCloseTo(100, 3);
    expect(s.offset(at(13))).toBeCloseTo(50, 3);
    expect(s.offset(at(20))).toBe(0);
  });

  it("faces away going out and toward the island coming back, with the bubble only while standing", () => {
    const s = stroll();
    expect(s.heading(at(1))).toBe("awayFromNotch");
    expect(s.heading(at(5))).toBe("awayFromNotch");
    expect(s.heading(at(13))).toBe("towardNotch");
    expect(s.showsBubble(at(1))).toBe(false);
    expect(s.showsBubble(at(3))).toBe(true);
    expect(s.showsBubble(at(13))).toBe(false);
  });

  it("sends the pet home at once when dismissed while talking", () => {
    const s = stroll();
    s.dismiss(at(4));
    expect(s.phase(at(4))).toBe("walkingBack");
    expect(s.showsBubble(at(4))).toBe(false);
    expect(s.endsAt).toBe(at(6));
  });

  it("turns around where the pet stands when dismissed mid-walk", () => {
    const s = stroll();
    s.dismiss(at(1));
    expect(s.phase(at(1.5))).toBe("walkingBack");
    expect(s.offset(at(1.5))).toBeCloseTo(25, 3);
    expect(s.endsAt).toBe(at(2));
  });

  it("counts only the first dismissal, and one after the timeout changes nothing", () => {
    const s = stroll();
    s.dismiss(at(4));
    s.dismiss(at(9));
    expect(s.dismissedAt).toBe(at(4));
    const late = stroll();
    late.dismiss(at(13));
    expect(late.turnsBackAt).toBe(at(12));
    expect(late.endsAt).toBe(at(14));
  });

  it("is short and readable by default", () => {
    const s = new PetCoachStroll(t0);
    expect(s.walkDuration).toBeLessThanOrEqual(2);
    expect(s.talkDuration).toBeGreaterThanOrEqual(8);
  });

  it("holds the bubble and stops the talk clock while hovered", () => {
    const s = stroll();
    s.hold(at(5));
    expect(s.phase(at(100))).toBe("talking");
    expect(s.talkElapsed(at(100))).toBeCloseTo(3, 3);
    expect(s.dateAfterTalking(4)).toBeUndefined();
    s.release(at(20));
    expect(s.turnsBackAt).toBe(at(27));
    expect(s.talkElapsed(at(21))).toBeCloseTo(4, 3);
    expect(s.dateAfterTalking(4)).toBe(at(21));
  });

  it("lingers briefly after a release near the end", () => {
    const s = stroll();
    s.hold(at(11.9));
    s.release(at(11.95));
    expect(s.turnsBackAt - at(11.95)).toBeCloseTo(PetCoachStroll.lingerAfterHold, 3);
  });

  it("ignores a hold while walking or after a dismissal, and a dismissal ends a hold", () => {
    const walking = stroll();
    walking.hold(at(1));
    expect(walking.heldSince).toBeUndefined();
    const dismissed = stroll();
    dismissed.dismiss(at(4));
    dismissed.hold(at(4.5));
    expect(dismissed.heldSince).toBeUndefined();
    expect(dismissed.turnsBackAt).toBe(at(4));
    const held = stroll();
    held.hold(at(5));
    held.dismiss(at(30));
    expect(held.turnsBackAt).toBe(at(30));
  });
});

describe("PetCoachGlance", () => {
  const glance = () => new PetCoachGlance(t0, 1, 1, 2);

  it("lowers, holds and pulls back up", () => {
    const g = glance();
    expect(g.pose(at(-0.1))).toBeUndefined();
    expect(g.pose(at(0.5))?.animation).toBe("peekIn");
    expect(g.pose(at(0.5))?.elapsed).toBeCloseTo(0.5, 3);
    expect(g.pose(at(2.5))?.animation).toBe("peekIn");
    expect(g.pose(at(3.25))?.animation).toBe("peekOut");
    expect(g.pose(at(3.25))?.elapsed).toBeCloseTo(0.25, 3);
    expect(g.pose(at(4))).toBeUndefined();
    expect(g.endsAt).toBe(at(4));
  });

  it("is timed by the pet's own peek clips and stays brief", () => {
    const clips = cachedClipSet({ breed: PetProfile.starter("cat").breed });
    const g = PetCoachGlance.timedBy(t0, clips);
    expect(g.enter).toBe(clips.clip("peekIn").duration);
    expect(g.leave).toBe(clips.clip("peekOut").duration);
    expect(g.hold).toBe(PetCoachGlance.standardHold);
    expect(g.duration).toBeLessThan(5);
  });

  it("has a stroll that stays at the edge and ends with the glance", () => {
    const s = glance().stroll;
    expect(s.endsAt).toBe(glance().endsAt);
    for (let second = 0; second <= 4; second += 0.5) expect(s.offset(at(second))).toBe(0);
  });

  it("clamps negative durations to zero", () => {
    const g = new PetCoachGlance(t0, -1, -1, -1);
    expect(g.duration).toBe(0);
    expect(g.pose(t0)).toBeUndefined();
  });
});

describe("PetCoachRedraw", () => {
  const clips = cachedClipSet({ breed: PetProfile.starter("cat").breed });
  /* Redraws land a hair after each change; samples sit between the clips' frame boundaries. */
  const lateness = 0.002;

  function picture(s: PetCoachStroll, arrival: PetAnimation, date: number): string {
    const phase: PetCoachStrollPhase = s.phase(date);
    if (phase !== "talking") return phase;
    const elapsed = date - s.arrivesAt;
    const arrivalClip = clips.clip(arrival);
    if (elapsed < arrivalClip.duration) return `${arrival}-${arrivalClip.frameIndex(elapsed)}`;
    return `idle-${clips.clip("idle").frameIndex(elapsed - arrivalClip.duration)}`;
  }

  function redraws(s: PetCoachStroll, arrival: PetAnimation, start: number): number[] {
    const dates: number[] = [];
    let next: number | undefined = start;
    while (next !== undefined && dates.length < 10_000) {
      const date: number = next;
      dates.push(date);
      next = strollNextRedraw(s, date, clips, arrival);
      if (next !== undefined) expect(next).toBeGreaterThan(date);
    }
    return dates;
  }

  it("redraws a standing pet only on frame changes", () => {
    const s = new PetCoachStroll(t0);
    const talking = redraws(s, "alert", t0).filter((date) => s.phase(date) === "talking");
    expect(talking.length).toBeGreaterThan(3);
    expect(talking.length).toBeLessThan(120);
    for (let index = 1; index < talking.length; index++) {
      expect(picture(s, "alert", talking[index] ?? 0)).not.toBe(picture(s, "alert", talking[index - 1] ?? 0));
    }
  });

  it("misses no frame change while the pet stands", () => {
    const s = new PetCoachStroll(t0, { talkDuration: 8 });
    for (const arrival of ["alert", "celebrate"] as const) {
      const dates = redraws(s, arrival, t0);
      let index = 0;
      for (let step = s.arrivesAt - t0 + 0.005; step < 10; step += 0.01) {
        const date = t0 + step;
        while (index + 1 < dates.length && (dates[index + 1] ?? Infinity) <= date + lateness) index += 1;
        expect(picture(s, arrival, dates[index] ?? 0), `${arrival} at ${step}`).toBe(picture(s, arrival, date));
      }
    }
  });

  it("moves a walking pet every frame and ends at home", () => {
    const s = new PetCoachStroll(t0);
    const dates = redraws(s, "alert", t0);
    for (let index = 1; index < dates.length; index++) {
      const previous = dates[index - 1] ?? 0;
      if (s.phase(previous) !== "talking") expect((dates[index] ?? 0) - previous).toBeLessThanOrEqual(1 / COACH_WALK_FRAME_RATE + 1e-6);
    }
    expect(dates.some((date) => date >= s.arrivesAt && date < s.arrivesAt + 0.01)).toBe(true);
    expect(dates.some((date) => date >= s.turnsBackAt && date < s.turnsBackAt + 0.01)).toBe(true);
    expect(s.phase(dates[dates.length - 1] ?? 0)).toBe("finished");
    expect(strollNextRedraw(s, s.endsAt, clips, "alert")).toBeUndefined();
  });

  it("redraws marks while talking on time", () => {
    const s = new PetCoachStroll(t0, { talkDuration: 10 });
    const mark = s.arrivesAt + 4;
    let date = s.arrivesAt + 1;
    for (;;) {
      const next = strollNextRedraw(s, date, clips, "celebrate", [mark]);
      if (next === undefined || next > mark) break;
      date = next;
    }
    const next = strollNextRedraw(s, date, clips, "celebrate", [mark]);
    expect(next).toBeDefined();
    expect((next ?? Infinity) - mark).toBeLessThan(0.01);
  });

  it("waits for the pet to set off before the start", () => {
    expect(strollNextRedraw(new PetCoachStroll(t0), t0 - 1, clips, "alert")).toBeCloseTo(t0, 2);
  });

  it("turns a dismissed pet back right away", () => {
    const s = new PetCoachStroll(t0);
    const answered = s.arrivesAt + 2;
    s.dismiss(answered);
    expect(strollNextRedraw(s, answered - 0.0005, clips, "alert") ?? Infinity).toBeLessThanOrEqual(answered + 0.01);
    const home = strollNextRedraw(s, answered + 0.1, clips, "alert");
    expect((home ?? 0) - answered).toBeCloseTo(0.1 + 1 / COACH_WALK_FRAME_RATE, 6);
  });

  it("redraws a glance on peek frames and holds still while looking", () => {
    const glance = PetCoachGlance.timedBy(t0, clips);
    const dates: number[] = [];
    let next: number | undefined = t0 - 0.5;
    while (next !== undefined && dates.length < 10_000) {
      dates.push(next);
      next = glanceNextRedraw(glance, next, clips);
    }
    expect(dates.length).toBeLessThanOrEqual(clips.clip("peekIn").frames.length + clips.clip("peekOut").frames.length + 4);
    const holdStart = t0 + glance.enter + 0.01;
    const holdEnd = t0 + glance.enter + glance.hold;
    expect(dates.some((date) => date > holdStart && date < holdEnd)).toBe(false);
    const shown = (date: number) => {
      const pose = glance.pose(date);
      return pose ? `${pose.animation}-${clips.clip(pose.animation).frameIndex(pose.elapsed)}` : "hidden";
    };
    let index = 0;
    for (let step = -0.495; step < glance.duration + 0.5; step += 0.01) {
      const date = t0 + step;
      while (index + 1 < dates.length && (dates[index + 1] ?? Infinity) <= date + lateness) index += 1;
      expect(shown(dates[index] ?? 0), `at ${step}`).toBe(shown(date));
    }
    expect(glance.pose(dates[dates.length - 1] ?? 0)).toBeUndefined();
  });
});
