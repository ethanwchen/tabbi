import { describe, expect, it } from "vitest";
import { parseAppLink, type PartyInvite } from "../../../src/core/links/appLink";

/* A stand-in for the party port's parser, enough to route invites. */
function parseInvite(url: string): PartyInvite | undefined {
  const match = /^(?:tabbi:\/\/(add|join)|https:\/\/tabbinotch\.com\/(add|join))\/([A-Za-z0-9-]+)$/i.exec(url);
  if (!match) return undefined;
  const action = (match[1] ?? match[2] ?? "").toLowerCase();
  const code = (match[3] ?? "").replace(/-/g, "").toUpperCase();
  if (action === "add") return code.length === 8 && /^[A-Z0-9]+$/.test(code) && code !== "NOTACODE" ? { kind: "addFriend", code } : undefined;
  return code.length === 6 ? { kind: "joinParty", code } : undefined;
}

const link = (text: string) => parseAppLink(text, parseInvite);

describe("AppLink", () => {
  it("opens the panel", () => {
    expect(link("tabbi://open")).toEqual({ kind: "open" });
    expect(link("TABBI://Open/")).toEqual({ kind: "open" });
    expect(parseAppLink("tabbi://open")).toEqual({ kind: "open" });
  });

  it("reads invites through the party parser", () => {
    expect(link("tabbi://add/k7qw-2mzd")).toEqual({ kind: "invite", invite: { kind: "addFriend", code: "K7QW2MZD" } });
    expect(link("tabbi://join/AB3CDE")).toEqual({ kind: "invite", invite: { kind: "joinParty", code: "AB3CDE" } });
    expect(link("https://tabbinotch.com/add/K7QW2MZD")).toEqual({
      kind: "invite",
      invite: { kind: "addFriend", code: "K7QW2MZD" },
    });
  });

  it("ignores everything else", () => {
    expect(link("tabbi://open/settings")).toBeUndefined();
    expect(link("tabbi://settings")).toBeUndefined();
    expect(link("tabbi://add/NOTACODE0")).toBeUndefined();
    expect(link("tabbi:open")).toBeUndefined();
    expect(link("https://tabbinotch.com/open")).toBeUndefined();
    expect(link("notabbi://open")).toBeUndefined();
    expect(link("not a url")).toBeUndefined();
  });

  it("leaves the web sign-in callback to its own flow", () => {
    const code = "ab".repeat(32);
    expect(link(`tabbi://auth/apple?code=${code}`)).toBeUndefined();
    expect(link("tabbi://auth/apple?error=cancelled")).toBeUndefined();
  });
});
