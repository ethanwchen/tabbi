import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { setLookup } from "../../../src/core/localization/tr";
import { partyDemoCelebration } from "../../../src/core/party/partyDemo";
import { PartySessionCompletion } from "../../../src/core/party/partySessionTracker";
import { PartyTeamCelebration } from "../../../src/core/party/partyTeamCelebration";
import { switchLanguage } from "../localization/catalogs";

/* The message shown when a shared session runs to its end. The English catalog supplies the plural forms. */

const start = 1_790_000_000;

const completion = (minutes = 25, friends = 2) =>
  new PartySessionCompletion({ method: "pomodoro", joinedAt: start, endedAt: start + minutes * 60, friendCount: friends, hostName: "Maya" });

describe("PartyTeamCelebration", () => {
  beforeAll(() => switchLanguage("en"));
  afterAll(() => setLookup(() => undefined));

  it("thanks the team with the points earned", () => {
    const celebration = new PartyTeamCelebration(completion(), 45, start, "Miso");
    expect(celebration.title).toBe("Great job, team!");
    expect(celebration.detail).toBe("+45 points for Miso · 25 min with 2 friends");
  });

  it("adapts to company and missing details", () => {
    const alone = new PartyTeamCelebration(completion(25, 0), 1, start, "  ");
    expect(alone.title).toBe("Great job!");
    expect(alone.detail).toBe("+1 point · 25 min on your own");
    const unpaid = new PartyTeamCelebration(completion(3, 1), 0, start, "Miso");
    expect(unpaid.detail, "no points line when nothing was earned").toBe("3 min with 1 friend");
  });

  it("shows for a few seconds only", () => {
    const celebration = new PartyTeamCelebration(completion(), 45, start);
    expect(celebration.isShowing(start)).toBe(true);
    expect(celebration.isShowing(start + PartyTeamCelebration.displayDuration - 1)).toBe(true);
    expect(celebration.isShowing(celebration.endsAt)).toBe(false);
    expect(celebration.isShowing(start - 1)).toBe(false);
  });

  it("celebrates the demo's 25 minutes with two friends", () => {
    const demo = partyDemoCelebration(start);
    expect(demo.detail).toBe("+45 points for Mochi · 25 min with 2 friends");
  });
});
