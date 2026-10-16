import { beforeAll, describe, expect, it } from "vitest";
import {
  calendarSourceSituation,
  grantedSituation,
  grantedSituationOn,
  upNextEmptyState,
} from "../../../src/core/planner/upNextEmptyState";
import { switchLanguage } from "../../support/catalogs";

/* Port of UpNextEmptyStateTests, plus the Windows calendar source's situations. */

beforeAll(() => {
  switchLanguage("en");
});

describe("UpNextEmptyState choosing a state", () => {
  it("needs no empty state with events ahead", () => {
    expect(grantedSituation(2, 4, false)).toBeUndefined();
  });

  it("says the rest is yours on a finished day", () => {
    expect(grantedSituation(0, 3, false)).toBe("dayDone");
  });

  it("calls an empty day with an account a free day", () => {
    expect(grantedSituation(0, 0, true)).toBe("freeDay");
  });

  it("suggests adding an account with only local calendars", () => {
    expect(grantedSituation(0, 0, false)).toBe("noAccounts");
  });
});

describe("UpNextEmptyState wording and actions", () => {
  it("explains Google calendars in the kit's words on first run", () => {
    const state = upNextEmptyState("notAsked", "lectures, labs, and shifts", "Tabbi");
    expect(state.action).toBe("requestAccess");
    expect(state.detail).toContain("lectures, labs, and shifts");
    expect(state.detail).toContain("Google");
    expect(state.detail).toContain("Internet Accounts");
    expect(state.actionHelp).toContain("Tabbi");
  });

  it("opens Internet Accounts without accounts", () => {
    const state = upNextEmptyState("noAccounts", "meetings and calls", "Tabbi");
    expect(state.action).toBe("openInternetAccounts");
    expect(state.actionTitle).toBe("Internet Accounts");
    expect(state.detail).toContain("meetings and calls");
    expect(state.detail).toContain("Google");
  });

  it("links to privacy settings when denied", () => {
    const state = upNextEmptyState("denied", "meetings and calls", "Tabbi");
    expect(state.action).toBe("openPrivacySettings");
    expect(state.detail).toContain("Tabbi");
  });

  it("sends the user to Connections when no calendar is available", () => {
    const state = upNextEmptyState("unavailable", "meetings and calls", "Tabbi");
    expect(state.action).toBe("openConnections");
    expect(state.actionTitle).toBe("Connect calendar");
    expect(state.detail).toContain("meetings and calls");
    /* The user is already in the app; never tell them to open it. */
    expect(state.detail).not.toContain("Open the");
  });

  it("gives informational states no button", () => {
    for (const situation of ["freeDay", "dayDone"] as const) {
      const state = upNextEmptyState(situation, "meetings and calls", "Tabbi");
      expect(state.action, situation).toBeUndefined();
      expect(state.actionTitle, situation).toBe("");
      expect(state.title, situation).not.toBe("");
    }
  });

  it("finds another day empty only without any timed event", () => {
    expect(grantedSituationOn("tomorrow", 2, 2, true)).toBeUndefined();
    expect(grantedSituationOn("tomorrow", 0, 0, true)).toBe("freeTomorrow");
    expect(grantedSituationOn("yesterday", 0, 0, true)).toBe("freeYesterday");
    /* Yesterday's events are all over, but that's no "day done" there: they're listed. */
    expect(grantedSituationOn("yesterday", 3, 3, true)).toBeUndefined();
    expect(grantedSituationOn("tomorrow", 0, 0, false)).toBe("noAccounts");
  });

  it("still means what is left today", () => {
    expect(grantedSituationOn("today", 0, 4, true)).toBe("dayDone");
    expect(grantedSituationOn("today", 0, 0, true)).toBe("freeDay");
  });

  it("names the day in other days' empty states", () => {
    const tomorrow = upNextEmptyState("freeTomorrow", "meetings and calls", "Tabbi");
    const yesterday = upNextEmptyState("freeYesterday", "meetings and calls", "Tabbi");
    expect(tomorrow.detail).toContain("tomorrow");
    expect(yesterday.detail).toContain("yesterday");
    expect(tomorrow.action).toBeUndefined();
    expect(yesterday.action).toBeUndefined();
  });
});

describe("UpNextEmptyState for a Windows calendar source", () => {
  it("asks to connect a calendar without any feed", () => {
    expect(calendarSourceSituation("today", false, 0, 0)).toBe("unavailable");
    expect(calendarSourceSituation("tomorrow", false, 2, 2)).toBe("unavailable");
  });

  it("treats every feed as an online account", () => {
    expect(calendarSourceSituation("today", true, 0, 0)).toBe("freeDay");
    expect(calendarSourceSituation("today", true, 0, 2)).toBe("dayDone");
    expect(calendarSourceSituation("tomorrow", true, 0, 0)).toBe("freeTomorrow");
    expect(calendarSourceSituation("today", true, 1, 1)).toBeUndefined();
  });
});
