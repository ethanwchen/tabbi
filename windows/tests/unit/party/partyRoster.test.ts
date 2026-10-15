import { describe, expect, it } from "vitest";
import { partyProfile, type PartyFriend, type PartyMember, type PartyPresence, type PartyStatus } from "../../../src/core/party/partyModels";
import { compactStatusLine, compactStatusWord, rosterDuration, rosterStatus, rosterTimeLeft, sortedFriends, sortedMembers, statusLine } from "../../../src/core/party/partyRoster";

const now = 1_790_000_123;

const presence = (status: PartyStatus, endsIn?: number): PartyPresence => ({
  status,
  method: status === "idle" ? undefined : "pomodoro",
  phaseEndsAt: endsIn === undefined ? undefined : now + endsIn,
  sessionMinutes: 0,
  todayMinutes: 40,
  streakDays: 0,
  day: "2026-09-21",
  lastSeen: now,
});

const friend = (name: string, code: string, p: PartyPresence | undefined, online: boolean): PartyFriend => ({
  profile: partyProfile({ code, name, petName: "Pip", species: "cat", breed: "tabby" }),
  since: now,
  presence: p,
  online,
  party: undefined,
});

describe("PartyRoster", () => {
  it("is offline when not online or never seen", () => {
    expect(rosterStatus(presence("studying"), false)).toBe("offline");
    expect(rosterStatus(undefined, true)).toBe("offline");
    expect(rosterStatus(presence("onBreak"), true)).toBe("onBreak");
  });

  it("counts the status line down locally", () => {
    expect(statusLine(presence("studying", 17 * 60 + 5), true, now)).toBe("Studying · 18 min left");
    expect(statusLine(presence("onBreak", 30), true, now)).toBe("On a break · 1 min left");
    expect(statusLine(presence("studying", -10), true, now)).toBe("Studying · ending");
    expect(statusLine(presence("studying"), true, now)).toBe("Studying");
    expect(statusLine(presence("idle"), true, now)).toBe("Online");
    expect(statusLine(presence("studying", 600), false, now)).toBe("Offline");
  });

  it("fits the compact line into a narrow row", () => {
    expect(compactStatusLine(presence("studying", 40 * 60 + 1), true, now)).toBe("Studying · 41m");
    expect(compactStatusLine(presence("onBreak", 200), true, now)).toBe("Break · 4m");
    expect(compactStatusLine(presence("studying", -5), true, now)).toBe("Studying");
    expect(compactStatusLine(presence("onBreak"), true, now)).toBe("Break");
    expect(compactStatusLine(presence("idle"), true, now)).toBe("Online");
    expect(compactStatusLine(undefined, true, now)).toBe("Offline");
    expect(compactStatusWord(presence("onBreak", 200), true)).toBe("Break");
  });

  it("has time left only for running phases", () => {
    expect(rosterTimeLeft(presence("studying", 90), true, now)).toBe(90);
    expect(rosterTimeLeft(presence("idle", 90), true, now)).toBeUndefined();
    expect(rosterTimeLeft(presence("studying", 90), false, now)).toBeUndefined();
  });

  it("formats durations", () => {
    expect(rosterDuration(0)).toBe("0m");
    expect(rosterDuration(45)).toBe("45m");
    expect(rosterDuration(60)).toBe("1h");
    expect(rosterDuration(80)).toBe("1h 20m");
  });

  it("sorts friends active first, then by name", () => {
    const friends = [
      friend("zoe", "AAAAAAA1", undefined, false),
      friend("Mia", "AAAAAAA2", presence("idle"), true),
      friend("ben", "AAAAAAA3", presence("onBreak"), true),
      friend("Ava", "AAAAAAA4", presence("studying"), true),
      friend("Cal", "AAAAAAA5", presence("studying"), true),
      friend("Ann", "AAAAAAA6", presence("studying"), false),
    ];
    expect(sortedFriends(friends).map((f) => f.profile.name)).toEqual(["Ava", "Cal", "ben", "Mia", "Ann", "zoe"]);
  });

  it("sorts members host first", () => {
    const member = (name: string, host: boolean): PartyMember => ({
      profile: partyProfile({ code: name.toUpperCase(), name, petName: "Pip", species: "dog", breed: "corgi" }),
      joinedAt: now,
      host,
      presence: undefined,
      online: true,
    });
    expect(sortedMembers([member("bo", false), member("Zed", true), member("al", false)]).map((m) => m.profile.name)).toEqual(["Zed", "al", "bo"]);
  });
});
