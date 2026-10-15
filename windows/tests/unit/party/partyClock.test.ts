import { describe, expect, it } from "vitest";
import { partyProfile, type Party, type PartyFriend, type PartyMember, type PartyPresence, type PartyStatus } from "../../../src/core/party/partyModels";
import { compactStatusLine } from "../../../src/core/party/partyRoster";
import { PartyState } from "../../../src/core/party/partyState";

/* PartyState.nextClockChange lets the Party panel redraw only when a countdown on it changes. */

const now = 1_790_000_000;
const profile = (code: string) => partyProfile({ code, name: code, petName: "Mochi", species: "cat", breed: "tabby" });
const presence = (status: PartyStatus, endsIn?: number): PartyPresence => ({
  status,
  method: undefined,
  phaseEndsAt: endsIn === undefined ? undefined : now + endsIn,
  sessionMinutes: 0,
  todayMinutes: 0,
  streakDays: 0,
  day: "2026-09-21",
  lastSeen: now,
});
const friend = (code: string, p: PartyPresence, online = true): PartyFriend => ({ profile: profile(code), since: now, presence: p, online, party: undefined });

function state(friends: PartyFriend[] = [], members: PartyMember[] = [], sessionEndsIn?: number): PartyState {
  const party: Party = {
    code: "Q4RT8M",
    host: "ME",
    createdAt: now,
    lastActive: now,
    expiresAt: now + 3600,
    maxMembers: 8,
    session: sessionEndsIn === undefined ? undefined : { method: "pomodoro", phaseEndsAt: now + sessionEndsIn, startedAt: now - 60 },
    members: [{ profile: profile("ME"), joinedAt: now, host: true, presence: undefined, online: true }, ...members],
  };
  return PartyState.loaded(profile("ME"), friends, party);
}

describe("PartyState clock", () => {
  it("needs no clock when nothing counts down", () => {
    const quiet = state([friend("A", presence("idle")), friend("B", presence("studying", 600), false), friend("C", presence("studying", -5))]);
    expect(quiet.nextClockChange(now), "idle, offline and finished phases show no countdown").toBeUndefined();
  });

  it("wakes for a friend's countdown only when its minutes change", () => {
    const p = presence("studying", 150);
    const s = state([friend("A", p)]);
    const label = (at: number) => compactStatusLine(p, true, at);
    const changes: number[] = [];
    let date = now;
    for (let next = s.nextClockChange(date); next !== undefined; next = s.nextClockChange(date)) {
      expect(next).toBeGreaterThan(date);
      expect(label(next - 0.01), "nothing changes before the wakeup").toBe(label(date));
      expect(label(next), "the wakeup lands on a change").not.toBe(label(date));
      changes.push(next - now);
      date = next;
    }
    expect(changes).toEqual([30, 90, 150]);
  });

  it("ticks every second for a shared session, which wins over minutes", () => {
    const member: PartyMember = { profile: profile("B"), joinedAt: now, host: false, presence: presence("studying", 600), online: true };
    const s = state([], [member], 90.4);
    expect((s.nextClockChange(now) ?? 0) - now).toBeCloseTo(0.4, 3);
    const later = now + 0.4;
    expect((s.nextClockChange(later) ?? 0) - later).toBeCloseTo(1, 3);
    expect((s.nextClockChange(now + 91) ?? 0) - now).toBeCloseTo(120, 3);
  });
});
