import { describe, expect, it } from "vitest";
import { PARTY_DEMO_SCENARIOS, partyDemoScenario, partyDemoState, type PartyDemoScenario } from "../../../src/core/party/partyDemo";
import { PartyError } from "../../../src/core/party/partyError";
import {
  canJoin,
  isPartyFull,
  partyProfile,
  type Party,
  type PartyFriend,
  type PartyFriendRequest,
  type PartyProfile,
  type PartyStatus,
} from "../../../src/core/party/partyModels";
import { partyPet } from "../../../src/core/party/partyPetAppearance";
import { rosterStatus } from "../../../src/core/party/partyRoster";
import { partySettings } from "../../../src/core/party/partySettings";
import { PartyState } from "../../../src/core/party/partyState";

const now = 1_790_000_000;
const zone = "America/New_York";
const oldEnough = partySettings({ ageEligibleFrom: Number.NEGATIVE_INFINITY });

const profile = (code: string, name: string): PartyProfile => partyProfile({ code, name, petName: "Mochi", species: "cat", breed: "tabby" });
const friend = (code: string, name: string, online = true, status: PartyStatus = "idle"): PartyFriend => ({
  profile: profile(code, name),
  since: now,
  presence: { status, method: undefined, phaseEndsAt: undefined, sessionMinutes: 0, todayMinutes: 0, streakDays: 0, day: "2026-09-21", lastSeen: now },
  online,
  party: undefined,
});
const party = (host: string, members: [string, string][]): Party => ({
  code: "Q4RT8M",
  host,
  createdAt: now,
  lastActive: now,
  expiresAt: now + 3600,
  maxMembers: 8,
  session: undefined,
  members: members.map(([code, name]) => ({ profile: profile(code, name), joinedAt: now, host: code === host, presence: undefined, online: true })),
});
const request = (code: string, name: string): PartyFriendRequest => ({ profile: profile(code, name), since: now });
const ok = <T>(value: T) => ({ ok: true as const, value });
const fail = (error: PartyError) => ({ ok: false as const, error });

describe("PartyState", () => {
  it("starts connecting or reports a bad server", () => {
    expect(new PartyState(oldEnough, now).connection).toEqual({ kind: "connecting" });
    const bad = new PartyState(partySettings({ serverText: "http://example.com" }), now);
    const connection = bad.connection;
    expect(connection.kind === "invalidServer" && connection.message.length > 0).toBe(true);
    bad.didFailToConnect(PartyError.of("unreachable"));
    expect(bad.connection, "a bad server isn't masked by network errors").toBe(connection);
  });

  it("is unreachable after a first failure and connects after a retry", () => {
    const state = new PartyState(oldEnough, now);
    state.didFailToConnect(PartyError.of("timedOut"));
    expect(state.connection.kind === "unreachable" && state.connection.error.kind).toBe("timedOut");
    state.willReconnect();
    expect(state.connection).toEqual({ kind: "connecting" });
    state.didConnect(profile("K7QW2MZD", "Sam"));
    expect(state.connection).toEqual({ kind: "connected" });
    expect(state.friendCode).toBe("K7QW2MZD");
  });

  it("keeps loaded data after a failure and marks it stale", () => {
    const state = new PartyState(oldEnough, now);
    state.didConnect(profile("K7QW2MZD", "Sam"));
    expect(state.friendsLoaded, "no empty state before the first list arrives").toBe(false);
    state.didFetchFriends(ok([friend("B", "Ben")]));
    state.didFetchFriends(fail(PartyError.of("unreachable")));
    state.didFailToConnect(PartyError.of("serverUnavailable"));
    expect(state.connection).toEqual({ kind: "connected" });
    expect(state.friends.map((f) => f.profile.name)).toEqual(["Ben"]);
    expect(state.staleError?.kind).toBe("serverUnavailable");
    state.didFetchFriends(ok([]));
    expect(state.staleError).toBeUndefined();
    expect(state.friendsLoaded).toBe(true);
    expect(state.friends).toEqual([]);
  });

  it("sorts friends and edits them locally", () => {
    const state = new PartyState(oldEnough, now);
    state.didFetchFriends(ok([friend("O", "Olive", false), friend("S", "Sky", true, "studying"), friend("A", "Ash")]));
    expect(state.friends.map((f) => f.profile.name)).toEqual(["Sky", "Ash", "Olive"]);
    state.didAddFriend(profile("B", "Bea"), now);
    state.didAddFriend(profile("B", "Bea"), now);
    expect(state.friends.map((f) => f.profile.name), "a new friend shows once, offline until the next refresh").toEqual(["Sky", "Ash", "Bea", "Olive"]);
    state.didRemoveFriend("S");
    expect(state.friends.map((f) => f.profile.name)).toEqual(["Ash", "Bea", "Olive"]);
  });

  it("hides a blocked user from friends and the party", () => {
    const state = new PartyState(oldEnough, now);
    state.didConnect(profile("ME", "Sam"));
    state.didFetchFriends(ok([friend("A", "Ash"), friend("Z", "Zoe")]));
    state.didFetchParty(ok(party("ME", [["Z", "Zoe"], ["ME", "Sam"], ["A", "Ash"]])));
    state.didBlock("Z");
    expect(state.friends.map((f) => f.profile.name)).toEqual(["Ash"]);
    expect(state.party?.members.map((m) => m.profile.name)).toEqual(["Sam", "Ash"]);
    expect(state.isHost).toBe(true);
  });

  it("follows membership, the host and companions", () => {
    const state = new PartyState(oldEnough, now);
    state.didConnect(profile("ME", "Sam"));
    state.didFetchParty(ok(party("ME", [["Z", "Zoe"], ["ME", "Sam"], ["A", "Ash"]])));
    expect(state.inParty).toBe(true);
    expect(state.isHost).toBe(true);
    expect(state.party?.members.map((m) => m.profile.name), "host first, then by name").toEqual(["Sam", "Ash", "Zoe"]);
    expect(state.companions.map((m) => m.profile.name)).toEqual(["Ash", "Zoe"]);
    state.didFetchParty(ok(party("Z", [["Z", "Zoe"], ["ME", "Sam"]])));
    expect(state.isHost).toBe(false);
    state.didFetchParty(fail(PartyError.of("unreachable")));
    expect(state.inParty, "a network blip keeps the party").toBe(true);
    state.didFetchParty(fail(PartyError.of("notInParty")));
    expect(state.inParty).toBe(false);
    expect(state.companions).toEqual([]);
  });

  it("drops the old server's data on reset", () => {
    const state = new PartyState(oldEnough, now);
    state.didConnect(profile("ME", "Sam"));
    state.didFetchFriends(ok([friend("B", "Ben")]));
    state.reset(partySettings({ serverText: "http://localhost:8787", ageEligibleFrom: Number.NEGATIVE_INFINITY }), now);
    expect(state.connection).toEqual({ kind: "connecting" });
    expect(state.friendCode).toBeUndefined();
    expect(state.friends).toEqual([]);
  });

  it("leaves the original untouched when a clone changes", () => {
    const state = PartyState.loaded(profile("ME", "Sam"), [friend("B", "Ben")], undefined);
    const copy = state.clone();
    copy.didRemoveFriend("B");
    expect(state.friends.length).toBe(1);
    expect(copy.friends.length).toBe(0);
  });

  it("covers every status and a joinable party in the demo", () => {
    const state = partyDemoState(now, zone);
    expect(state.connection).toEqual({ kind: "connected" });
    expect(state.isHost).toBe(true);
    expect(state.companions.length).toBe(2);
    expect(state.party?.session).toBeDefined();
    expect(new Set(state.friends.map((f) => rosterStatus(f.presence, f.online)))).toEqual(new Set(["studying", "onBreak", "offline"]));
    expect(state.friends.some((f) => canJoin(f) && f.party?.code !== state.party?.code), "one friend is in another party, to show Join").toBe(true);
    for (const member of state.party?.members ?? []) expect(partyPet(member.profile).name).toBe(member.profile.petName);
    for (const member of state.party?.members ?? []) {
      expect(partyPet(member.profile).outfit, "no capes in demo art").not.toBe("superheroCape");
      expect(partyPet(member.profile).accessories).not.toContain("kingsCape");
    }
  });

  it("covers every screen in the demo scenarios", () => {
    const demo = (scenario: PartyDemoScenario) => partyDemoScenario(scenario, now, zone);
    expect(PARTY_DEMO_SCENARIOS.length).toBe(16);
    expect(demo("hosting").friends).toEqual(partyDemoState(now, zone).friends);
    const guest = demo("guest");
    expect(guest.isHost).toBe(false);
    expect(guest.party?.session).toBeUndefined();
    expect(guest.party?.members[0]?.host, "the host stands first").toBe(true);
    expect(guest.party?.members.filter((m) => m.host).length).toBe(1);
    const member = demo("member");
    expect(member.isHost).toBe(false);
    expect(member.session(now)?.hostName).toBe("Maya");
    expect(member.session(now)?.friendCount).toBe(2);
    const crowded = demo("crowded");
    expect(crowded.isHost).toBe(true);
    expect(crowded.party && isPartyFull(crowded.party)).toBe(true);
    expect(new Set(crowded.party?.members.map((m) => m.profile.code)).size).toBe(8);
    expect(demo("lobby").inParty).toBe(false);
    expect(demo("lobby").friends.length).toBeGreaterThan(0);
    const noFriends = demo("noFriends");
    expect(noFriends.friendsLoaded).toBe(true);
    expect(noFriends.friends).toEqual([]);
    expect(noFriends.friendCode).toBeDefined();
    expect(demo("hosting").incomingRequests.map((r) => r.profile.name)).toEqual(["Noor"]);
    expect(demo("hosting").waitingRequestCount).toBe(1);
    expect(demo("requests").friends).toEqual([]);
    expect(demo("requests").outgoingRequests.length).toBe(1);
    expect(demo("requests").hasPeople).toBe(true);
    expect(demo("noFriends").hasPeople).toBe(false);
    expect(demo("connecting").connection).toEqual({ kind: "connecting" });
    expect(demo("unreachable").connection.kind).toBe("unreachable");
    expect(demo("invalidServer").connection.kind).toBe("invalidServer");
    expect(demo("ageCheck").connection).toEqual({ kind: "ageCheck", tooYoungUntil: undefined });
    expect(demo("tooYoung").connection).toEqual({ kind: "ageCheck", tooYoungUntil: now + 540 * 86_400 });
  });

  it("loads and settles friend requests", () => {
    const state = new PartyState(oldEnough, now);
    state.didConnect(profile("K7QW2MZD", "Sam"));
    state.didFetchFriendList(ok({ friends: [friend("B", "Ben")], incoming: [request("N", "Noor"), request("O", "Omar")], outgoing: [request("K", "Kai")] }));
    expect(state.incomingRequests.map((r) => r.profile.code)).toEqual(["N", "O"]);
    expect(state.waitingRequestCount).toBe(2);
    state.didAddFriend(profile("N", "Noor"), now);
    expect(state.incomingRequests.map((r) => r.profile.code), "accepting settles the request").toEqual(["O"]);
    expect(state.waitingRequestCount).toBe(1);
    expect(state.friends.map((f) => f.profile.name)).toEqual(["Ben", "Noor"]);
    state.didRemoveFriend("O");
    expect(state.incomingRequests, "declining drops it").toEqual([]);
    expect(state.waitingRequestCount).toBe(0);
    state.didRemoveFriend("K");
    expect(state.outgoingRequests, "cancelling drops mine").toEqual([]);
    expect(state.friends.length).toBe(2);
  });

  it("shows the request or the friend at once when asking", () => {
    const state = PartyState.loaded(profile("K7QW2MZD", "Sam"), [], undefined);
    state.didAsk({ kind: "requested", profile: profile("K", "Kai") }, now);
    state.didAsk({ kind: "requested", profile: profile("K", "Kai") }, now);
    expect(state.outgoingRequests.map((r) => r.profile.code), "asking twice keeps one row").toEqual(["K"]);
    expect(state.hasPeople).toBe(true);
    state.didAsk({ kind: "friends", profile: profile("K", "Kai") }, now);
    expect(state.outgoingRequests).toEqual([]);
    expect(state.friends.map((f) => f.profile.code)).toEqual(["K"]);
  });

  it("counts waiting requests from a heartbeat for the badge", () => {
    const state = PartyState.loaded(profile("K7QW2MZD", "Sam"), [], undefined);
    expect(state.waitingRequestCount).toBe(0);
    state.didCountWaitingRequests(3);
    expect(state.waitingRequestCount).toBe(3);
    state.didFetchFriendList(ok({ friends: [], incoming: [request("N", "Noor")], outgoing: [] }));
    expect(state.waitingRequestCount, "the list, once loaded, is the truth").toBe(1);
    state.didFetchFriends(ok([]));
    expect(state.waitingRequestCount, "a server without requests has none").toBe(0);
  });

  it("drops their request when blocking", () => {
    const state = PartyState.loaded(profile("K7QW2MZD", "Sam"), [], undefined, [request("N", "Noor")]);
    state.didBlock("N");
    expect(state.incomingRequests).toEqual([]);
    expect(state.waitingRequestCount).toBe(0);
  });
});
