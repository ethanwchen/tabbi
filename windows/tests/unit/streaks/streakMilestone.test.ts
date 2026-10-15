import { describe, expect, it } from "vitest";
import { isStreakMilestone, streakMilestoneReached } from "../../../src/core/streaks/streakMilestone";

// Port of StreakMilestoneTests.
describe("StreakMilestone", () => {
  it("only round lengths are milestones", () => {
    const firstYear = Array.from({ length: 366 }, (_, day) => day).filter(isStreakMilestone);
    expect(firstYear).toEqual([7, 14, 30, 50, 100, 200, 365]);
    expect(isStreakMilestone(-7)).toBe(false);
  });

  it("past a year every hundred days and every year count", () => {
    expect(isStreakMilestone(400)).toBe(true);
    expect(isStreakMilestone(730)).toBe(true);
    expect(isStreakMilestone(366)).toBe(false);
    expect(isStreakMilestone(450)).toBe(false);
  });

  it("growing onto a milestone reaches it", () => {
    expect(streakMilestoneReached(6, 7)).toBe(7);
    expect(streakMilestoneReached(364, 365)).toBe(365);
    expect(streakMilestoneReached(7, 8)).toBeUndefined();
  });

  it("no baseline, holding or breaking reaches nothing", () => {
    expect(streakMilestoneReached(undefined, 7)).toBeUndefined();
    expect(streakMilestoneReached(7, 7)).toBeUndefined();
    expect(streakMilestoneReached(30, 0)).toBeUndefined();
  });

  it("a jump past several milestones counts the largest once", () => {
    expect(streakMilestoneReached(5, 16)).toBe(14);
    expect(streakMilestoneReached(0, 9)).toBe(7);
    expect(streakMilestoneReached(0, 6)).toBeUndefined();
  });
});
