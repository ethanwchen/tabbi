import { describe, expect, it } from "vitest";
import { PartyClient, encodeSorted, profileBody } from "../../src/core/party/partyClient";
import type { PartyProfile } from "../../src/core/party/partyModels";
import { PARTY_COLOR_ROLES, partyPet, partyPetUpdate, wireAccessory, wireOutfit } from "../../src/core/party/partyPetAppearance";
import type { PartyHttpRequest, PartyTransport } from "../../src/core/party/partyTransport";
import { PROTOCOL_HEADER, PROTOCOL_VERSION } from "../../src/core/party/partyWire";
import { PET_ACCESSORIES, PET_OUTFITS, type PetAccessory, type PetOutfit } from "../../src/core/pets/petCostume";
import { PET_BREEDS, isOneOf } from "../../src/core/pets/petKinds";
import { colorFromHex, colorHex, isPetPaletteRole } from "../../src/core/pets/petPalette";
import { PetProfile } from "../../src/core/pets/petProfile";
import { loadFixture } from "../support/fixtures";

/*
 * Replays shared/fixtures/party (written by PartyProtocolGoldenTests on the
 * Mac): the Party wire protocol both apps speak. Every sample pet's profile
 * body, and how every sample reply (from this server, a protocol 1 server
 * and a newer one) reads, down to the pet drawn for each profile. Only the
 * inputs (`pet`, `json`) are read; every recorded output is compared.
 */

type JSONValue = null | boolean | number | string | JSONValue[] | { [key: string]: JSONValue };

/** A pet as the app draws it, in the app's own ids. */
interface FixturePet {
  species: string;
  breed: string;
  outfit: string;
  accessories: string[];
  colors: Record<string, string>;
}

interface PartyFixture {
  protocol: number;
  protocolHeader: string;
  colorRoles: string[];
  outfits: Record<string, string>;
  accessories: Record<string, string>;
  updates: { name: string; pet: FixturePet; body: Record<string, JSONValue> }[];
  replies: { name: string; schema: string; json: JSONValue; summary: Record<string, JSONValue>; pets: Record<string, FixturePet> }[];
}

const fixture = loadFixture<PartyFixture>("party/party.json");

const TOKEN = "ab".repeat(32);

/** Answers every request with one recorded reply, remembering what was sent. */
function fixtureTransport(reply: JSONValue): { transport: PartyTransport; sent: PartyHttpRequest[] } {
  const sent: PartyHttpRequest[] = [];
  return {
    sent,
    transport: async (request) => {
      sent.push(request);
      return { status: 200, body: JSON.stringify(reply) };
    },
  };
}

function drawn(pet: PetProfile): FixturePet {
  const palette = pet.palette;
  return {
    species: pet.species,
    breed: pet.breed,
    outfit: pet.outfit,
    accessories: [...pet.accessories],
    colors: Object.fromEntries(PARTY_COLOR_ROLES.map((role) => [role, colorHex(palette.color(role)).slice(0, 7)])),
  };
}

function petsOf(profiles: readonly PartyProfile[]): Record<string, FixturePet> {
  const pets: Record<string, FixturePet> = {};
  for (const profile of profiles) if (!(profile.code in pets)) pets[profile.code] = drawn(partyPet(profile));
  return pets;
}

/** Reads `json` the way the app reads a reply of that kind, as the Mac's `PartyProtocolFixture.read`. */
async function readReply(json: JSONValue, schema: string): Promise<{ summary: Record<string, JSONValue>; pets: Record<string, FixturePet> }> {
  const client = new PartyClient(fixtureTransport(json).transport, TOKEN);
  switch (schema) {
    case "friendList": {
      const list = await client.friendList();
      return {
        summary: {
          friends: list.friends.map((friend) => friend.profile.code),
          incoming: list.incoming.map((request) => request.profile.code),
          outgoing: list.outgoing.map((request) => request.profile.code),
          badges: Object.fromEntries(list.friends.map((friend) => [friend.profile.code, [...friend.profile.badges]])),
        },
        pets: petsOf([...list.friends, ...list.incoming, ...list.outgoing].map((entry) => entry.profile)),
      };
    }
    case "addFriendReply": {
      const addition = await client.addFriend("B3NX9QRT");
      return { summary: { result: addition.kind }, pets: petsOf([addition.profile]) };
    }
    case "heartbeatReply": {
      const reply = await client.heartbeat({ status: "idle" });
      return {
        summary: {
          status: reply.presence.status === "onBreak" ? "break" : reply.presence.status,
          nextHeartbeat: reply.nextHeartbeat === undefined ? null : Math.trunc(reply.nextHeartbeat),
          incomingRequests: reply.incomingRequests ?? null,
        },
        pets: {},
      };
    }
    case "partyReply": {
      const party = await client.party();
      if (party === undefined) throw new Error("no party");
      return {
        summary: {
          members: party.members.map((member) => member.profile.code),
          host: party.host,
          session: party.session?.method ?? null,
        },
        pets: petsOf(party.members.map((member) => member.profile)),
      };
    }
    default:
      throw new Error(`no reader for ${schema}`);
  }
}

/**
 * The sample pet from its recorded look. The fixture does not record the
 * pet's name, so the name the body sent is the one input taken from it.
 */
function petFrom(input: FixturePet, name: string): PetProfile {
  if (!isOneOf(PET_BREEDS, input.breed)) throw new Error(`unknown breed ${input.breed}`);
  if (!isOneOf(PET_OUTFITS, input.outfit)) throw new Error(`unknown outfit ${input.outfit}`);
  const accessories = input.accessories.map((id) => {
    if (!isOneOf(PET_ACCESSORIES, id)) throw new Error(`unknown accessory ${id}`);
    return id;
  });
  const pet = new PetProfile(name, input.breed, { outfit: input.outfit, accessories });
  for (const [role, hex] of Object.entries(input.colors)) {
    const color = colorFromHex(hex);
    if (color === undefined || !isPetPaletteRole(role)) throw new Error(`bad color ${role}`);
    pet.setColor(color, role);
  }
  return pet;
}

describe("party fixture", () => {
  it("speaks the recorded protocol on every request", async () => {
    expect(PROTOCOL_VERSION).toBe(fixture.protocol);
    expect(PROTOCOL_HEADER).toBe(fixture.protocolHeader);
    const { transport, sent } = fixtureTransport({ ok: true, friends: [] });
    await new PartyClient(transport, TOKEN).friendList();
    expect(sent[0]?.headers?.[fixture.protocolHeader]).toBe(String(fixture.protocol));
  });

  it("sends colors in the recorded role order", () => {
    expect([...PARTY_COLOR_ROLES]).toEqual(fixture.colorRoles);
  });

  it("gives every outfit and accessory its recorded server id", () => {
    expect(Object.keys(fixture.outfits).sort()).toEqual([...PET_OUTFITS].sort());
    for (const [outfit, wire] of Object.entries(fixture.outfits)) expect(wireOutfit(outfit as PetOutfit), outfit).toBe(wire);
    expect(Object.keys(fixture.accessories).sort()).toEqual([...PET_ACCESSORIES].sort());
    for (const [accessory, wire] of Object.entries(fixture.accessories)) expect(wireAccessory(accessory as PetAccessory), accessory).toBe(wire);
  });

  describe("profile bodies", () => {
    it.each(fixture.updates.map((update) => [update.name, update] as const))("%s", (_, update) => {
      const name = update.body.petName;
      expect(typeof name).toBe("string");
      const pet = petFrom(update.pet, String(name));
      expect(drawn(pet)).toEqual(update.pet);
      const body = JSON.parse(encodeSorted(profileBody(partyPetUpdate(pet)))) as unknown;
      expect(body).toEqual(update.body);
    });
  });

  describe("replies", () => {
    it.each(fixture.replies.map((reply) => [reply.name, reply] as const))("%s", async (_, reply) => {
      const reading = await readReply(reply.json, reply.schema);
      expect(reading.summary).toEqual(reply.summary);
      expect(reading.pets).toEqual(reply.pets);
    });
  });

  it("covers every update and reply the fixture records", () => {
    expect(fixture.updates.length).toBeGreaterThan(0);
    expect(fixture.replies.length).toBeGreaterThan(0);
  });
});
