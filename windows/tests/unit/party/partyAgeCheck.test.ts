import { describe, expect, it } from "vitest";
import { ageStatus, birthYears, eligibleFrom, monthNames, opensText } from "../../../src/core/party/partyAgeCheck";
import { PartyError } from "../../../src/core/party/partyError";
import { PartyInviteFlow } from "../../../src/core/party/partyInviteFlow";
import { decodePartySettings, encodePartySettings, partyAgeStatus, partyServerIssue, partySettings } from "../../../src/core/party/partySettings";
import { PartyState } from "../../../src/core/party/partyState";

const date = (year: number, month: number, day: number) => Date.UTC(year, month - 1, day) / 1000;

describe("PartyAgeCheck", () => {
  it("starts eligibility the month after the thirteenth birthday month", () => {
    expect(eligibleFrom({ month: 3, year: 2013 }, "UTC")).toBe(date(2026, 4, 1));
    expect(eligibleFrom({ month: 12, year: 2013 }, "UTC")).toBe(date(2027, 1, 1));
    expect(eligibleFrom({ month: 13, year: 2013 }, "UTC")).toBeUndefined();
    expect(eligibleFrom({ month: 0, year: 2013 }, "UTC")).toBeUndefined();
    expect(eligibleFrom({ month: 3, year: 1900 }, "UTC")).toBeUndefined();
  });

  it("counts from local midnight in the named zone", () => {
    expect(eligibleFrom({ month: 3, year: 2013 }, "America/New_York")).toBe(date(2026, 4, 1) + 4 * 3600);
  });

  it("follows the saved day", () => {
    const eligible = date(2026, 4, 1);
    expect(ageStatus(undefined, date(2026, 1, 1))).toEqual({ kind: "unanswered" });
    expect(ageStatus(eligible, date(2026, 3, 31))).toEqual({ kind: "tooYoung", until: eligible });
    expect(ageStatus(eligible, eligible)).toEqual({ kind: "passed" });
  });

  it("offers a century of years and suggests no answer", () => {
    const years = birthYears(date(2026, 10, 9), "UTC");
    expect(years[0]).toBe(2026);
    expect(years[years.length - 1]).toBe(1926);
    expect(years.length).toBe(101);
  });

  it("asks in the Gregorian calendar whatever the locale's", () => {
    expect(monthNames("he-IL-u-ca-hebrew").length).toBe(12);
    expect(monthNames("en-US-u-ca-japanese")[0]).toBe("January");
  });

  it("names the month and year Party opens", () => {
    expect(opensText(date(2028, 5, 1), "en-US", "UTC")).toBe("May 2028");
  });

  it("makes Party wait for the age check before connecting", () => {
    const now = date(2026, 10, 9);
    expect(new PartyState(partySettings(), now).connection).toEqual({ kind: "ageCheck", tooYoungUntil: undefined });
    const young = partySettings({ ageEligibleFrom: date(2028, 5, 1) });
    expect(new PartyState(young, now).connection).toEqual({ kind: "ageCheck", tooYoungUntil: date(2028, 5, 1) });
    expect(new PartyState(young, date(2028, 5, 1)).connection).toEqual({ kind: "connecting" });
    const bad = partySettings({ serverText: "http://example.com" });
    expect(new PartyState(bad, now).connection).toEqual({ kind: "invalidServer", message: partyServerIssue(bad) });
  });

  it("never hides the age check after a failed connect", () => {
    const state = new PartyState(partySettings(), date(2026, 1, 1));
    state.didFailToConnect(PartyError.of("unreachable"));
    expect(state.awaitsAgeCheck).toBe(true);
  });

  it("saves the answer, and older settings ask again", () => {
    const settings = partySettings({ name: "Ana", ageEligibleFrom: date(2020, 1, 1) });
    expect(decodePartySettings(encodePartySettings(settings))).toEqual(settings);
    const older = decodePartySettings('{"name":"Ana","invisible":false}');
    expect(older.ageEligibleFrom).toBeUndefined();
    expect(partyAgeStatus(older, date(2026, 1, 1))).toEqual({ kind: "unanswered" });
  });

  it("makes invites say Party waits for the age check", () => {
    const flow = new PartyInviteFlow({ kind: "addFriend", code: "AVA7K3RN" }, true);
    flow.update(new PartyState(partySettings(), date(2026, 1, 1)), undefined);
    expect(flow.stage).toEqual({ kind: "ageCheck", tooYoungUntil: undefined });
    expect(flow.primaryTitle).toBe("Open Party");
    expect(flow.isDone).toBe(false);

    const until = date(2028, 5, 1);
    const young = new PartyInviteFlow({ kind: "joinParty", code: "ZX7M2P" }, true);
    young.update(new PartyState(partySettings({ ageEligibleFrom: until }), date(2026, 1, 1)), undefined);
    expect(young.stage).toEqual({ kind: "ageCheck", tooYoungUntil: until });
    expect(young.primaryTitle).toBeUndefined();
    expect(young.isDone).toBe(true);
    expect(young.title).toBe("Party isn't available");
  });
});
