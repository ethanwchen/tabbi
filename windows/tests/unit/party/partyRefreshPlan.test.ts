import { describe, expect, it } from "vitest";
import { PartyRefreshPlan } from "../../../src/core/party/partyRefreshPlan";

const t0 = 1_790_000_123;

function opened(inParty = false): PartyRefreshPlan {
  const plan = new PartyRefreshPlan();
  plan.inParty = inParty;
  plan.setVisible(true);
  plan.didFetch("friends", t0);
  plan.didFetch("party", t0);
  return plan;
}

describe("PartyRefreshPlan", () => {
  it("fetches nothing while hidden", () => {
    const plan = new PartyRefreshPlan();
    expect(plan.due(t0)).toEqual([]);
    expect(plan.nextDue()).toBeUndefined();
  });

  it("fetches friends and the party once on opening", () => {
    const plan = new PartyRefreshPlan();
    plan.setVisible(true);
    expect(plan.due(t0)).toEqual(["friends", "party"]);
    plan.didFetch("friends", t0);
    plan.didFetch("party", t0);
    expect(plan.due(t0 + 59)).toEqual([]);
    // Not in a party: the party is not polled again, friends every 60 s.
    expect(plan.due(t0 + 60)).toEqual(["friends"]);
    expect(plan.nextDue()).toBe(t0 + 60);
  });

  it("polls the party every 30 s while in one", () => {
    const plan = opened(true);
    expect(plan.nextDue()).toBe(t0 + 30);
    expect(plan.due(t0 + 30)).toEqual(["party"]);
    expect(plan.due(t0 + 60)).toEqual(["friends", "party"]);
  });

  it("stops when hidden and refreshes at once when reopened", () => {
    const plan = opened(true);
    plan.setVisible(false);
    expect(plan.due(t0 + 600)).toEqual([]);
    expect(plan.nextDue()).toBeUndefined();
    plan.setVisible(true);
    expect(plan.due(t0 + 5)).toEqual(["friends", "party"]);
  });

  it("keeps the schedule on a redundant show", () => {
    const plan = opened();
    plan.setVisible(true);
    expect(plan.due(t0 + 1)).toEqual([]);
  });

  it("makes an invalidated feed due now", () => {
    const plan = opened();
    plan.invalidate("party");
    expect(plan.due(t0 + 1)).toEqual(["party"]);
  });

  it("fetches the leaderboard once per opening of its view, never on a timer", () => {
    const plan = opened();
    expect(plan.due(t0 + 1), "not before its view opens").toEqual([]);
    plan.setLeaderboardVisible(true);
    expect(plan.due(t0 + 1)).toEqual(["leaderboard"]);
    plan.didFetch("leaderboard", t0 + 1);
    expect(plan.due(t0 + 3600)).toEqual(["friends"]);
    expect(plan.nextDue()).toBe(t0 + 60);
    plan.setLeaderboardVisible(true);
    expect(plan.due(t0 + 2), "showing it again while open is no new opening").toEqual([]);
    plan.setLeaderboardVisible(false);
    plan.setLeaderboardVisible(true);
    expect(plan.due(t0 + 2)).toEqual(["leaderboard"]);
  });

  it("fetches no leaderboard while the panel is hidden", () => {
    const plan = new PartyRefreshPlan();
    plan.setLeaderboardVisible(true);
    expect(plan.due(t0)).toEqual([]);
    plan.setVisible(true);
    plan.setLeaderboardVisible(true);
    plan.setVisible(false);
    expect(plan.isLeaderboardVisible, "hiding the panel hides the leaderboard").toBe(false);
    expect(plan.due(t0)).toEqual([]);
  });

  it("polls the party on a timer only while in a party and visible", () => {
    const plan = opened(false);
    expect(plan.due(t0 + 3600)).toEqual(["friends"]);
    plan.inParty = true;
    expect(plan.due(t0 + 30)).toEqual(["party"]);
    plan.setVisible(false);
    expect(plan.due(t0 + 3600)).toEqual([]);
  });
});
