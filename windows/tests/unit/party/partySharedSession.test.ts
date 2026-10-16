import { describe, expect, it } from "vitest";
import { partyProfile, type Party, type PartyMember, type PartySession } from "../../../src/core/party/partyModels";
import { partySettings } from "../../../src/core/party/partySettings";
import { PartyState } from "../../../src/core/party/partyState";

/*
 * The host's shared session as each member sees it (`PartyState.session`).
 * The Swift cases about ProvidedPartySession's method name, company line,
 * length and focus clock test core/providers, which another port owns.
 */

const now = 1_790_000_000;

const member = (code: string, name: string, host = false, online = true): PartyMember => ({
  profile: partyProfile({ code, name, petName: name, species: "cat", breed: "tabby" }),
  joinedAt: now,
  host,
  presence: { status: online ? "studying" : "offline", method: undefined, phaseEndsAt: undefined, sessionMinutes: 0, todayMinutes: 0, streakDays: 0, day: "2026-09-21", lastSeen: now },
  online,
});

const running: PartySession = { method: "pomodoro", phaseEndsAt: now + 20 * 60, startedAt: now - 5 * 60 };

/** I am ME0000; Zoe hosts unless `iHost`, and Bo is offline. */
function state(session: PartySession | undefined, iHost = false): PartyState {
  const members = [member("HOST00", "Zoe", !iHost), member("ME0000", "Ana", iHost), member("FRND00", "Kai"), member("AWAY00", "Bo", false, false)];
  const party: Party = { code: "Q4RT8M", host: iHost ? "ME0000" : "HOST00", createdAt: now, lastActive: now, expiresAt: now + 3600, maxMembers: 8, session, members };
  const me = members[1];
  if (me === undefined) throw new Error("no me");
  return PartyState.loaded(me.profile, [], party);
}

describe("Party shared session", () => {
  it("shows a member the host's session with the friends online", () => {
    const session = state(running).session(now);
    expect(session).toEqual({ method: "pomodoro", startedAt: running.startedAt, endsAt: running.phaseEndsAt, friendCount: 2, hostName: "Zoe" });
  });

  it("shows the host their own session", () => {
    expect(state(running, true).session(now)?.hostName).toBeUndefined();
  });

  it("has no session when none runs or it ran out", () => {
    expect(state(undefined).session(now)).toBeUndefined();
    expect(state(running).session(now + 20 * 60)).toBeUndefined();
    expect(new PartyState(partySettings(), now).session(now)).toBeUndefined();
  });

  it("drops the session only for me when I step out", () => {
    const s = state(running);
    s.leaveSession();
    expect(s.session(now)).toBeUndefined();
    expect(s.hasLeftSession(now)).toBe(true);
    expect(s.party?.session, "the session goes on for the others").toEqual(running);
    expect(s.partyPets, "still in the party").toBeDefined();
    s.rejoinSession();
    expect(s.session(now)).toBeDefined();
  });

  it("includes a member who stepped out of the last session in a new one", () => {
    const s = state(running);
    s.leaveSession();
    const current = s.party;
    if (current === undefined) throw new Error("no party");
    s.didFetchParty({ ok: true, value: { ...current, session: { method: "pomodoro", phaseEndsAt: now + 50 * 60, startedAt: now } } });
    expect(s.session(now)).toBeDefined();
    expect(s.hasLeftSession(now)).toBe(false);
  });
});
