// Port of PetCheerTests.swift: the pet's cheer for a finished focus session,
// how long it holds the closed island and when the ticker shows it.
import { beforeAll, describe, expect, it } from "vitest";
import { PetCheer, tickerCheering } from "../../../src/core/motion/petCheer";
import { accessoryItem } from "../../../src/core/pets/petItem";
import { PetPresence } from "../../../src/core/pets/petPresence";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { ProvidedFocus } from "../../../src/core/providers/providedFocus";
import type { DayCalendar } from "../../../src/core/streaks/dayCalendar";
import { tickerPetSummary } from "../../../src/core/ticker/tickerFormat";
import { tickerPetIsSipping, type TickerItem, type TickerPet } from "../../../src/core/ticker/tickerItem";
import { TICKER_KINDS } from "../../../src/core/ticker/tickerKind";
import { TickerSources } from "../../../src/core/ticker/tickerSources";
import { switchLanguage } from "../../support/catalogs";

const start = 1_800_000_000;
const calendar: DayCalendar = { timeZone: "America/New_York", firstWeekday: 1 };
const all = () => true;

function cheer(id = 1): PetCheer {
  return new PetCheer("dance", id, start);
}

function sources(options: { pet?: boolean; focus?: ProvidedFocus } = {}): TickerSources {
  return new TickerSources({
    isMusicPlaying: true,
    focus: options.focus,
    pet: options.pet === false ? undefined : new PetPresence(PetProfile.starter("cat"), start, calendar),
  });
}

/* The pet an item shows, or undefined when it is not the pet. */
function petOf(item: TickerItem | undefined): TickerPet | undefined {
  return item?.type === "pet" ? item.pet : undefined;
}

beforeAll(() => {
  switchLanguage("en");
});

describe("PetCheer", () => {
  it("lasts about two seconds", () => {
    const value = cheer();
    expect(PetCheer.duration).toBeGreaterThanOrEqual(1.5);
    expect(PetCheer.duration).toBeLessThanOrEqual(2.5);
    expect(value.isShowing(start)).toBe(true);
    expect(value.isShowing(start + PetCheer.duration - 0.01)).toBe(true);
    expect(value.isShowing(value.endsAt)).toBe(false);
    // A clock set back before the start never shows an endless cheer.
    expect(value.isShowing(start - 60)).toBe(false);
  });

  it("lets the cheering pet take the island while the cheer lasts", () => {
    const ticker = sources();
    // Music would normally lead the rotation.
    expect(ticker.items(start)[0]).toEqual({ type: "nowPlaying" });

    const item = tickerCheering(ticker, cheer(), start + 0.5, all);
    const pet = petOf(item);
    expect(pet, `expected the pet, got ${JSON.stringify(item)}`).toBeDefined();
    if (pet === undefined) return;
    expect(pet.cheer).toEqual(cheer());
    expect(pet.profile.equals(PetProfile.starter("cat"))).toBe(true);
    expect(pet.mood).toBe("awake");

    expect(tickerCheering(ticker, cheer(), cheer().endsAt, all), "over: the rotation is back").toBeUndefined();
    expect(tickerCheering(ticker, undefined, start, all)).toBeUndefined();
  });

  it("keeps the cheering pet's mood", () => {
    const rest = new ProvidedFocus({ source: "focus", phase: "rest", clock: { kind: "countdown", endsAt: start + 300 }, phaseLength: 300 });
    const pet = petOf(tickerCheering(sources({ focus: rest }), cheer(), start, all));
    expect(pet, "expected the pet").toBeDefined();
    expect(pet?.mood, "the break that just began shows once the hops end").toBe("onBreak");
  });

  it("shows no cheer without a pet or with the pet preview off", () => {
    expect(tickerCheering(sources({ pet: false }), cheer(), start, all)).toBeUndefined();
    expect(tickerCheering(sources(), cheer(), start, (kind) => kind !== TICKER_KINDS.pet)).toBeUndefined();
  });

  it("puts a tiny crown on the pet for a crown cheer", () => {
    const hatted = PetProfile.starter("cat");
    hatted.wear("wizardHat");
    const ticker = new TickerSources({ isMusicPlaying: false, focus: undefined, pet: new PetPresence(hatted, start, calendar) });
    const crown = new PetCheer("crown", 1, start);
    const pet = petOf(tickerCheering(ticker, crown, start, all));
    expect(pet, "expected the pet").toBeDefined();
    if (pet === undefined) return;
    expect(pet.profile.isWearing(accessoryItem("tinyCrown"))).toBe(true);
    expect(pet.profile.isWearing(accessoryItem("wizardHat")), "the crown takes the hat's place for now").toBe(false);

    const dancing = petOf(tickerCheering(ticker, cheer(), start, all));
    expect(dancing, "expected the pet").toBeDefined();
    expect(dancing?.profile.equals(hatted), "a dance keeps the pet's own look").toBe(true);
    expect(tickerCheering(ticker, crown, crown.endsAt, all), "the crown comes off with the cheer").toBeUndefined();
  });

  it("holds the pet on a break long enough for a sip", () => {
    const sip = new PetCheer("sip", 1, start);
    expect(sip.length, "the hop, then the mug comes up").toBeGreaterThan(PetCheer.duration);
    expect(sip.length, "still brief").toBeLessThanOrEqual(5);
    const pet = petOf(tickerCheering(sources(), sip, start + 3, all));
    expect(pet, "expected the pet").toBeDefined();
    if (pet === undefined) return;
    expect(pet.mood, "on a break, the pet holds its mug").toBe("onBreak");
    expect(tickerPetIsSipping(pet)).toBe(true);
    expect(pet.profile.equals(PetProfile.starter("cat")), "a sip keeps the pet's own look").toBe(true);
    // The Mac says "Your Mac is charging"; the Windows port deliberately names the PC (see tickerFormat.ts).
    expect(tickerPetSummary(pet, start + 3)).toBe(`Your PC is charging, and ${pet.profile.name} is having a sip`);
    expect(tickerCheering(sources(), sip, sip.endsAt, all), "over: the rotation is back").toBeUndefined();
    expect(tickerCheering(sources(), sip, start, (kind) => kind !== TICKER_KINDS.pet), "no sip with the pet preview off").toBeUndefined();
  });
});
