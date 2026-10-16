import { describe, expect, it } from "vitest";
import {
  CELEBRATION_STYLES,
  CelebrationBurst,
  CelebrationPacer,
  type CelebrationParticleState,
} from "../../../src/core/motion/celebration";
import { STREAK_MILESTONE_DAYS, isStreakMilestone, streakMilestoneReached } from "../../../src/core/motion/streakMilestone";

function defined(state: CelebrationParticleState | undefined): CelebrationParticleState {
  if (!state) throw new Error("expected a particle state");
  return state;
}

/* Swift's Date(timeIntervalSinceReferenceDate:) as seconds since 1970. */
const referenceDate = (seconds: number) => 978_307_200 + seconds;

/* Port of CelebrationTests. */
describe("CelebrationBurst", () => {
  it("throws the same burst for the same seed", () => {
    const first = new CelebrationBurst("burst", "confetti", 7, 5);
    const again = new CelebrationBurst("burst", "confetti", 7, 5);
    const other = new CelebrationBurst("burst", "confetti", 8, 5);
    expect(first).toEqual(again);
    expect(first).not.toEqual(other);
  });

  it("throws each tier's particles within its time budget", () => {
    for (const style of CELEBRATION_STYLES) {
      for (let seed = 0; seed < 20; seed++) {
        const burst = new CelebrationBurst("burst", style, seed, 6);
        expect(burst.particles.length).toBe(36);
        expect(burst.duration).toBeLessThanOrEqual(1.5);
        const milestone = new CelebrationBurst("milestone", style, seed, 6);
        expect(milestone.particles.length).toBe(72);
        expect(milestone.duration).toBeLessThan(2);
        expect(milestone.duration).toBeGreaterThan(burst.duration - 0.5);
      }
    }
  });

  it("uses every palette color and stays in range", () => {
    const burst = new CelebrationBurst("burst", "sparkles", 3, 5);
    expect(new Set(burst.particles.map((p) => p.colorIndex))).toEqual(new Set([0, 1, 2, 3, 4]));
    const single = new CelebrationBurst("burst", "hearts", 3, 0);
    expect(new Set(single.particles.map((p) => p.colorIndex))).toEqual(new Set([0]));
  });

  it("launches upward within the spread, then falls and fades", () => {
    const burst = new CelebrationBurst("milestone", "confetti", 42, 6);
    for (const particle of burst.particles) {
      expect(Math.abs(particle.angle)).toBeLessThanOrEqual(CelebrationBurst.spread);
      expect(CelebrationBurst.state(particle, particle.delay - 0.01)).toBeUndefined();
      const launch = defined(CelebrationBurst.state(particle, particle.delay));
      expect(launch.x).toBeCloseTo(0, 9);
      expect(launch.y).toBeCloseTo(0, 9);
      expect(launch.scale).toBeCloseTo(CelebrationBurst.popScale, 9);
      expect(launch.opacity).toBe(1);

      const rising = defined(CelebrationBurst.state(particle, particle.delay + 0.1));
      expect(rising.y).toBeLessThan(0);
      expect(Math.sign(rising.x) < 0).toBe(particle.angle < 0);

      const late = defined(CelebrationBurst.state(particle, particle.delay + particle.lifetime * 0.99));
      expect(late.y).toBeGreaterThan(rising.y);
      expect(late.opacity).toBeLessThan(0.05);
      expect(late.scale).toBeCloseTo(1, 9);
      expect(CelebrationBurst.state(particle, particle.delay + particle.lifetime + 1e-6)).toBeUndefined();
    }
  });

  it("holds opacity, then fades smoothly over the last stretch", () => {
    const particle = new CelebrationBurst("burst", "hearts", 1, 3).particles[0];
    if (!particle) throw new Error("no particle");
    let previous = 1;
    for (let step = 0; step < 100; step++) {
      const state = defined(CelebrationBurst.state(particle, particle.delay + (particle.lifetime * step) / 100));
      if (step / 100 <= 1 - CelebrationBurst.fadeShare) expect(state.opacity).toBe(1);
      expect(state.opacity).toBeLessThanOrEqual(previous);
      previous = state.opacity;
    }
  });

  it("caps the fall by air drag", () => {
    const particle = new CelebrationBurst("milestone", "confetti", 9, 3).particles[0];
    if (!particle) throw new Error("no particle");
    const terminal = CelebrationBurst.gravity / CelebrationBurst.drag;
    const dt = 0.01;
    const end = particle.delay + particle.lifetime - dt;
    const a = defined(CelebrationBurst.state(particle, end - dt));
    const b = defined(CelebrationBurst.state(particle, end));
    expect((b.y - a.y) / dt).toBeLessThan(terminal);
  });

  it("is finished once its last particle is gone", () => {
    const burst = new CelebrationBurst("burst", "pawPrints", 5, 4);
    expect(burst.isFinished(0)).toBe(false);
    expect(burst.isFinished(burst.duration)).toBe(true);
    expect(burst.particles.every((p) => CelebrationBurst.state(p, burst.duration) === undefined)).toBe(true);
  });
});

describe("CelebrationPacer", () => {
  it("allows one burst every ten minutes", () => {
    const pacer = new CelebrationPacer();
    const start = referenceDate(800_000_000);
    expect(pacer.admit("burst", start, "UTC")).toBe("burst");
    expect(pacer.admit("burst", start + 60, "UTC")).toBeUndefined();
    expect(pacer.admit("burst", start + 599, "UTC")).toBeUndefined();
    expect(pacer.admit("burst", start + 600, "UTC")).toBe("burst");
  });

  it("always plays the first milestone of a day and turns later ones into bursts", () => {
    const morning = referenceDate(800_000_000 - (800_000_000 % 86_400) + 9 * 3600);
    const pacer = new CelebrationPacer();
    expect(pacer.admit("burst", morning, "UTC")).toBe("burst");
    expect(pacer.admit("milestone", morning + 30, "UTC")).toBe("milestone");
    expect(pacer.admit("milestone", morning + 60, "UTC")).toBeUndefined();
    expect(pacer.admit("milestone", morning + 3600, "UTC")).toBe("burst");
    expect(pacer.admit("milestone", morning + 86_400, "UTC")).toBe("milestone");
  });

  it("tells days apart in the zone it is given", () => {
    /* 23:30 and 00:30 the next day in Tokyo are the same UTC day. */
    const late = Date.UTC(2026, 9, 5, 14, 30) / 1000;
    const tokyo = new CelebrationPacer();
    expect(tokyo.admit("milestone", late, "Asia/Tokyo")).toBe("milestone");
    expect(tokyo.admit("milestone", late + 3600, "Asia/Tokyo")).toBe("milestone");
    const utc = new CelebrationPacer();
    expect(utc.admit("milestone", late, "UTC")).toBe("milestone");
    expect(utc.admit("milestone", late + 3600, "UTC")).toBe("burst");
  });
});

/* Port of StreakMilestoneTests. */
describe("StreakMilestone", () => {
  it("counts only round lengths", () => {
    const firstYear = Array.from({ length: 366 }, (_, day) => day).filter(isStreakMilestone);
    expect(firstYear).toEqual([...STREAK_MILESTONE_DAYS]);
    expect(isStreakMilestone(-7)).toBe(false);
  });

  it("counts every hundred days and every year past a year", () => {
    expect(isStreakMilestone(400)).toBe(true);
    expect(isStreakMilestone(730)).toBe(true);
    expect(isStreakMilestone(366)).toBe(false);
    expect(isStreakMilestone(450)).toBe(false);
  });

  it("reaches a milestone when growing onto it", () => {
    expect(streakMilestoneReached(6, 7)).toBe(7);
    expect(streakMilestoneReached(364, 365)).toBe(365);
    expect(streakMilestoneReached(7, 8)).toBeUndefined();
  });

  it("reaches nothing without a baseline, holding or breaking", () => {
    expect(streakMilestoneReached(undefined, 7)).toBeUndefined();
    expect(streakMilestoneReached(7, 7)).toBeUndefined();
    expect(streakMilestoneReached(30, 0)).toBeUndefined();
  });

  it("counts the largest of several milestones jumped past, once", () => {
    expect(streakMilestoneReached(5, 16)).toBe(14);
    expect(streakMilestoneReached(0, 9)).toBe(7);
    expect(streakMilestoneReached(0, 6)).toBeUndefined();
  });
});
