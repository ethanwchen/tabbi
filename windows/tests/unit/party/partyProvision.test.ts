import { describe, expect, it } from "vitest";
import { partyProfile, type Party, type PartyMember, type PartyProfile } from "../../../src/core/party/partyModels";
import { partyPet } from "../../../src/core/party/partyPetAppearance";
import { partySettings } from "../../../src/core/party/partySettings";
import { PartyState } from "../../../src/core/party/partyState";

/*
 * The party a Party module shares with the rest of the app (`partyPets`,
 * which the module wiring maps onto the providers' ProvidedParty). The
 * snapshot, badge and ticker cases of the Swift file test core/providers
 * and core/ticker, which other ports own.
 */

const now = 1_790_000_000;

const profile = (code: string, name: string, breed = "tabby"): PartyProfile =>
  partyProfile({ code, name, petName: name, species: breed === "corgi" ? "dog" : "cat", breed });

const member = (code: string, name: string, options: { host?: boolean; online?: boolean; breed?: string } = {}): PartyMember => ({
  profile: profile(code, name, options.breed),
  joinedAt: now,
  host: options.host ?? false,
  presence: { status: "studying", method: undefined, phaseEndsAt: undefined, sessionMinutes: 0, todayMinutes: 0, streakDays: 0, day: "2026-09-21", lastSeen: now },
  online: options.online ?? true,
});

const party = (members: PartyMember[]): Party => ({
  code: "Q4RT8M",
  host: members.find((m) => m.host)?.profile.code ?? "",
  createdAt: now,
  lastActive: now,
  expiresAt: now + 3600,
  maxMembers: 8,
  session: undefined,
  members,
});

describe("Party provision", () => {
  it("provides my pet first, then the others, and offline members doze", () => {
    const state = PartyState.loaded(profile("ME0000", "Ana"), [], party([
      member("HOST00", "Zoe", { host: true, breed: "corgi" }),
      member("ME0000", "Ana"),
      member("AWAY00", "Bo", { online: false }),
    ]));
    const pets = state.partyPets ?? [];
    expect(pets.map((pet) => pet.name)).toEqual(["Ana", "Zoe", "Bo"]);
    expect(pets.map((pet) => pet.isAway)).toEqual([false, false, true]);
    expect(pets[1]?.pet.equals(partyPet(profile("HOST00", "Zoe", "corgi")))).toBe(true);
    expect(pets.length).toBe(3);
  });

  it("provides nothing outside a party", () => {
    expect(PartyState.loaded(profile("ME0000", "Ana"), [], undefined).partyPets).toBeUndefined();
    expect(new PartyState(partySettings(), now).partyPets).toBeUndefined();
  });
});
