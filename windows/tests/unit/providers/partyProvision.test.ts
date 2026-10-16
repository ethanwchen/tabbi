// Port of PartyProvisionTests.swift, the parts about ProvidedParty, ModuleProvision
// and ProviderSnapshot. The PartyState.provided tests need the Party area
// (PartyState, PartyMember, PartyPetAppearance), which has no Windows port yet.
import { beforeAll, describe, expect, it } from "vitest";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { moduleProvision } from "../../../src/core/providers/moduleProvision";
import { ProvidedParty, type ProvidedPartyPet } from "../../../src/core/providers/providedParty";
import { ProviderSnapshot } from "../../../src/core/providers/providerSnapshot";
import { tickerPartySize } from "../../../src/core/ticker/tickerFormat";
import { MAX_PARTY_PETS, tickerItemKind } from "../../../src/core/ticker/tickerItem";
import { tickerKindModule, TICKER_KINDS } from "../../../src/core/ticker/tickerKind";
import { TickerSources } from "../../../src/core/ticker/tickerSources";
import { switchLanguage } from "../../support/catalogs";

const now = 1_790_000_000;

function pet(id: string): ProvidedPartyPet {
  return { id, name: id, pet: PetProfile.starter("cat"), isAway: false };
}

beforeAll(() => {
  switchLanguage("en");
});

describe("PartyProvision", () => {
  it("keeps the first party in tab order in the snapshot", () => {
    const first = new ProvidedParty([pet("a"), pet("b")]);
    const snapshot = new ProviderSnapshot([
      { module: "planner", provision: moduleProvision() },
      { module: "party", provision: moduleProvision({ party: first }) },
      { module: "other", provision: moduleProvision({ party: new ProvidedParty([pet("c")]) }) },
    ]);
    expect(snapshot.party).toBe(first);
  });

  it("keeps each module's badge count in the snapshot", () => {
    const snapshot = new ProviderSnapshot([
      { module: "planner", provision: moduleProvision() },
      { module: "party", provision: moduleProvision({ badge: 2 }) },
      { module: "other", provision: moduleProvision({ badge: 0 }) },
    ]);
    expect(snapshot.badges, "a zero count shows no badge").toEqual(new Map([["party", 2]]));
  });

  it("shows party pets in the ticker only with company", () => {
    const alone = new TickerSources({ party: new ProvidedParty([pet("me")]) });
    expect(alone.items(now), "a party of one has no pets to show beside mine").toEqual([]);

    const pair = new TickerSources({ party: new ProvidedParty([pet("me"), pet("zoe")]) });
    expect(pair.items(now)).toEqual([{ type: "party", party: { pets: [pet("me"), pet("zoe")], memberCount: 2 } }]);
    const first = pair.items(now)[0];
    expect(first === undefined ? undefined : tickerKindModule(tickerItemKind(first))).toBe("party");
    expect(pair.items(now, new Set([TICKER_KINDS.focus]))).toEqual([]);
    expect(pair.nextChange(now), "party pets never need a clock").toBeUndefined();
  });

  it("caps the ticker's pets but counts everyone", () => {
    const ids = Array.from({ length: 8 }, (_, index) => `m${index}`);
    const sources = new TickerSources({ party: new ProvidedParty(ids.map(pet)) });
    const first = sources.items(now)[0];
    expect(first?.type).toBe("party");
    if (first?.type !== "party") return;
    expect(first.party.pets.map((p) => p.id)).toEqual(ids.slice(0, MAX_PARTY_PETS));
    expect(first.party.memberCount).toBe(8);
    expect(tickerPartySize(first.party.memberCount)).toBe("8 in party");
  });
});
