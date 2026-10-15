import { describe, expect, it } from "vitest";
import { PartyError, partyErrorMessage } from "../../../src/core/party/partyError";
import { PartyInviteFlow } from "../../../src/core/party/partyInviteFlow";
import { partyProfile, type Party, type PartyProfile } from "../../../src/core/party/partyModels";
import { partySettings } from "../../../src/core/party/partySettings";
import { PartyState } from "../../../src/core/party/partyState";

const now = 1_790_000_000;
const me = "K7QW2MZD";
const maya = "M4YA8PET";
const oldEnough = partySettings({ ageEligibleFrom: Number.NEGATIVE_INFINITY });
const profile = (code: string, name: string, pet = "Mochi"): PartyProfile =>
  partyProfile({ code, name, petName: pet, species: "cat", breed: "tabby" });

function party(code: string, members: number): Party {
  return {
    code,
    host: me,
    createdAt: now,
    lastActive: now,
    expiresAt: now + 3600,
    maxMembers: 8,
    session: undefined,
    members: Array.from({ length: members }, (_, index) => ({
      profile: profile(index === 0 ? me : `F${index}AAAAAA`, `Friend ${index}`),
      joinedAt: now,
      host: index === 0,
      presence: undefined,
      online: true,
    })),
  };
}

/** A connected state with the friends list loaded. */
function connected(friends: PartyProfile[] = [], inParty?: Party, incoming: PartyProfile[] = []): PartyState {
  const state = new PartyState(oldEnough, now);
  state.didConnect(profile(me, "Sam"));
  state.didFetchFriendList({
    ok: true,
    value: {
      friends: friends.map((p) => ({ profile: p, since: now, presence: undefined, online: true, party: undefined })),
      incoming: incoming.map((p) => ({ profile: p, since: now })),
      outgoing: [],
    },
  });
  if (inParty !== undefined) state.didFetchParty({ ok: true, value: inParty });
  return state;
}

describe("PartyInviteFlow", () => {
  it("asks before adding, then names the friend and their pet", () => {
    const flow = new PartyInviteFlow({ kind: "addFriend", code: maya }, true);
    expect(flow.stage).toEqual({ kind: "connecting" });
    expect(flow.primaryTitle, "nothing to click while connecting").toBeUndefined();

    flow.update(connected(), []);
    expect(flow.stage).toEqual({ kind: "confirming" });
    expect(flow.title).toBe("Add a friend?");
    expect(flow.message).toContain("M4YA-8PET");
    expect(flow.primaryTitle).toBe("Add Friend");
    expect(flow.dismissTitle).toBe("Not Now");

    expect(flow.begin()).toBe(true);
    expect(flow.begin(), "a second click sends nothing").toBe(false);
    flow.didAsk({ kind: "friends", profile: profile(maya, "Maya", "Biscuit") });

    expect(flow.title).toBe("Maya is now your friend");
    expect(flow.message).toContain("Biscuit");
    expect(flow.person?.name).toBe("Maya");
    expect(flow.isDone).toBe(true);
    expect(flow.primaryTitle).toBeUndefined();
    expect(flow.dismissTitle).toBe("Done");
  });

  it("accepts someone who asked first, and says a request was sent", () => {
    const asked = new PartyInviteFlow({ kind: "addFriend", code: maya }, true);
    asked.update(connected([], undefined, [profile(maya, "Maya")]), []);
    expect(asked.title).toBe("Maya wants to be friends");
    expect(asked.primaryTitle).toBe("Accept");
    expect(asked.message).toContain("Accept to see");

    const flow = new PartyInviteFlow({ kind: "addFriend", code: maya }, true);
    flow.update(connected(), []);
    flow.begin();
    flow.didAsk({ kind: "requested", profile: profile(maya, "Maya") });
    expect(flow.title).toBe("Request sent to Maya");
    expect(flow.message).toBe("You'll be friends once they accept.");
  });

  it("offers to turn Party on first", () => {
    const flow = new PartyInviteFlow({ kind: "joinParty", code: "Q4RT8M" }, false);
    expect(flow.stage).toEqual({ kind: "needsParty" });
    expect(flow.primaryTitle).toBe("Turn On Party");
    expect(flow.begin(), "nothing is sent before Party is on").toBe(false);
    flow.update(connected(), undefined);
    expect(flow.stage, "state updates wait for the switch").toEqual({ kind: "needsParty" });
    flow.partyTurnedOn();
    expect(flow.stage).toEqual({ kind: "connecting" });
    flow.update(connected(), undefined);
    expect(flow.title).toBe("Join this party?");
    expect(flow.primaryTitle).toBe("Join Party");
  });

  it("waits for the friends list before asking", () => {
    const flow = new PartyInviteFlow({ kind: "addFriend", code: maya }, true);
    const state = new PartyState(oldEnough, now);
    state.didConnect(profile(me, "Sam"));
    flow.update(state, undefined);
    expect(flow.stage).toEqual({ kind: "connecting" });
  });

  it("answers locally for my own code, friends and blocks", () => {
    const own = new PartyInviteFlow({ kind: "addFriend", code: me }, true);
    own.update(connected(), undefined);
    expect(own.stage).toEqual({ kind: "refused", refusal: { kind: "ownCode" } });
    expect(own.isDone).toBe(true);

    const friend = new PartyInviteFlow({ kind: "addFriend", code: maya }, true);
    friend.update(connected([profile(maya, "Maya")]), undefined);
    expect(friend.title).toBe("Maya is already your friend");
    expect(friend.begin()).toBe(false);

    const blocked = new PartyInviteFlow({ kind: "addFriend", code: maya }, true);
    blocked.update(connected(), [{ code: maya, name: "Maya", petName: "Biscuit", since: undefined }]);
    expect(blocked.stage).toEqual({ kind: "refused", refusal: { kind: "blocked", name: "Maya" } });
    expect(blocked.message).toContain("Unblock");
    expect(blocked.begin(), "a block is respected").toBe(false);
  });

  it("says joining leaves the current party and skips the same one", () => {
    const other = new PartyInviteFlow({ kind: "joinParty", code: "Q4RT8M" }, true);
    other.update(connected([], party("ZZ3XYW", 1)), undefined);
    expect(other.message).toContain("leave your current party");
    expect(other.begin()).toBe(true);
    other.didJoin(party("Q4RT8M", 3));
    expect(other.title).toBe("You joined the party");
    expect(other.message).toBe("2 friends are here with you.");

    const same = new PartyInviteFlow({ kind: "joinParty", code: "Q4RT8M" }, true);
    same.update(connected([], party("Q4RT8M", 2)), undefined);
    expect(same.stage).toEqual({ kind: "finished", outcome: { kind: "alreadyInParty" } });
  });

  it("ends expired codes and moderation with a friendly sentence", () => {
    const expired = new PartyInviteFlow({ kind: "joinParty", code: "Q4RT8M" }, true);
    expired.update(connected(), undefined);
    expired.begin();
    expired.didFail(PartyError.of("partyNotFound"));
    expect(expired.title).toBe("Couldn't join this party");
    expect(expired.message).toBe("That party has ended. Ask for a new link.");
    expect(expired.isDone).toBe(true);
    expect(expired.primaryTitle).toBeUndefined();

    const unknown = new PartyInviteFlow({ kind: "addFriend", code: maya }, true);
    unknown.update(connected(), undefined);
    unknown.begin();
    unknown.didFail(PartyError.of("unknownCode"));
    expect(unknown.message).toContain("new one");

    const banned = new PartyInviteFlow({ kind: "addFriend", code: maya }, true);
    banned.update(connected(), undefined);
    banned.begin();
    banned.didFail(PartyError.of("banned"));
    expect(banned.message).toBe(partyErrorMessage(PartyError.of("banned")));
    expect(banned.begin()).toBe(false);
  });

  it("lets rate limits and network failures be retried", () => {
    const flow = new PartyInviteFlow({ kind: "addFriend", code: maya }, true);
    flow.update(connected(), undefined);
    flow.begin();
    flow.didFail(PartyError.rateLimited(30));
    expect(flow.message).toContain("Wait a minute");
    expect(flow.primaryTitle).toBe("Try Again");
    expect(flow.isDone).toBe(false);
    expect(flow.begin()).toBe(true);
    flow.didAsk({ kind: "alreadyFriends", profile: profile(maya, "Maya") });
    expect(flow.stage).toEqual({ kind: "finished", outcome: { kind: "alreadyFriends", profile: profile(maya, "Maya") } });
  });

  it("shows connection problems and retries connecting", () => {
    const flow = new PartyInviteFlow({ kind: "addFriend", code: maya }, true);
    const state = new PartyState(oldEnough, now);
    state.didFailToConnect(PartyError.of("unreachable"));
    flow.update(state, undefined);
    const stage = flow.stage;
    expect(stage.kind === "unavailable" ? stage.error.kind : stage.kind).toBe("unreachable");
    expect(flow.primaryTitle).toBe("Try Again");
    flow.retryConnecting();
    expect(flow.stage).toEqual({ kind: "connecting" });
    flow.update(connected(), undefined);
    expect(flow.stage).toEqual({ kind: "confirming" });

    const badServer = new PartyInviteFlow({ kind: "addFriend", code: maya }, true);
    badServer.update(new PartyState(partySettings({ serverText: "http://example.com" }), now), undefined);
    expect(badServer.primaryTitle).toBeUndefined();
    expect(badServer.message).toContain("Party options");
  });

  it("ignores replies that do not fit the step", () => {
    const flow = new PartyInviteFlow({ kind: "addFriend", code: maya }, true);
    flow.didAsk({ kind: "friends", profile: profile(maya, "Maya") });
    expect(flow.stage, "no reply before a request").toEqual({ kind: "connecting" });
    flow.update(connected(), undefined);
    flow.begin();
    flow.didJoin(party("Q4RT8M", 2));
    expect(flow.stage, "a join reply doesn't finish a friend link").toEqual({ kind: "working" });
  });
});
