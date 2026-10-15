import { describe, expect, it } from "vitest";
import { parseAppLink } from "../../../src/core/links/appLink";
import { PartyCode } from "../../../src/core/party/partyModels";
import { inviteAppURL, inviteWebURL, parseInvite, type PartyInvite } from "../../../src/core/party/partyInvite";

const add = (code: string): PartyInvite => ({ kind: "addFriend", code });
const join = (code: string): PartyInvite => ({ kind: "joinParty", code });

describe("PartyInvite", () => {
  it("parses app links", () => {
    expect(parseInvite("tabbi://add/K7QW2MZD")).toEqual(add("K7QW2MZD"));
    expect(parseInvite("tabbi://join/AB3CDE")).toEqual(join("AB3CDE"));
    expect(parseInvite("tabbi://add/K7QW2MZD/")).toEqual(add("K7QW2MZD"));
  });

  it("parses web links", () => {
    expect(parseInvite("https://tabbinotch.com/add/K7QW2MZD")).toEqual(add("K7QW2MZD"));
    expect(parseInvite("https://www.tabbinotch.com/join/AB3CDE/")).toEqual(join("AB3CDE"));
    expect(parseInvite("https://TabbiNotch.com/ADD/K7QW2MZD?utm=x#top")).toEqual(add("K7QW2MZD"));
  });

  it("normalizes hand-typed codes", () => {
    expect(parseInvite("tabbi://add/k7qw-2mzd")).toEqual(add("K7QW2MZD"));
    expect(parseInvite("TABBI://JOIN/ab3-cde")).toEqual(join("AB3CDE"));
  });

  it("rejects invalid codes", () => {
    expect(parseInvite("tabbi://add/AB3CDE"), "a party code is too short for a friend").toBeUndefined();
    expect(parseInvite("tabbi://join/K7QW2MZD"), "a friend code is too long for a party").toBeUndefined();
    expect(parseInvite("tabbi://add/K7QW2MZ0"), "0 is not in the code alphabet").toBeUndefined();
    expect(parseInvite("tabbi://add/K7QW%202MZD"), "percent-encoded codes are not handed out").toBeUndefined();
    expect(parseInvite("tabbi://add/")).toBeUndefined();
    expect(parseInvite("tabbi://add/K7QW2MZD/extra")).toBeUndefined();
  });

  it("rejects other hosts, schemes and actions", () => {
    for (const url of [
      "http://tabbinotch.com/add/K7QW2MZD",
      "https://tabbinotch.com.evil.example/add/K7QW2MZD",
      "https://evil.example/add/K7QW2MZD",
      "https://tabbinotch.com:8443/add/K7QW2MZD",
      "https://tabbinotch.com/add/K7QW2MZD/more",
      "https://user@tabbinotch.com/add/K7QW2MZD",
      "tabbi://remove/K7QW2MZD",
      "tabbi://open",
      "notabbi://add/K7QW2MZD",
      "not a link",
    ]) {
      expect(parseInvite(url), url).toBeUndefined();
    }
  });

  it("builds links that round-trip", () => {
    const friend = add("K7QW2MZD");
    expect(inviteWebURL(friend)).toBe("https://tabbinotch.com/add/K7QW2MZD");
    expect(inviteAppURL(friend)).toBe("tabbi://add/K7QW2MZD");
    const party = join("AB3CDE");
    expect(inviteWebURL(party)).toBe("https://tabbinotch.com/join/AB3CDE");
    for (const invite of [friend, party]) {
      expect(parseInvite(inviteWebURL(invite))).toEqual(invite);
      expect(parseInvite(inviteAppURL(invite))).toEqual(invite);
    }
  });

  it("yields the code of a shared link pasted into a code field", () => {
    for (const url of [inviteWebURL(add("K7QW2MZD")), inviteAppURL(add("K7QW2MZD"))]) {
      expect(PartyCode.find(`Add me on Tabbi: ${url}`, PartyCode.friendCodeLength)).toBe("K7QW2MZD");
    }
    for (const url of [inviteWebURL(join("AB3CDE")), inviteAppURL(join("AB3CDE"))]) {
      expect(PartyCode.find(url, PartyCode.partyCodeLength)).toBe("AB3CDE");
    }
  });

  it("plugs into the app link parser", () => {
    expect(parseAppLink("tabbi://add/K7QW2MZD", parseInvite)).toEqual({ kind: "invite", invite: add("K7QW2MZD") });
  });
});
