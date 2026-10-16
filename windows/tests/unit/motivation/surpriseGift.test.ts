import { describe, expect, it } from "vitest";
import { PetCloset } from "../../../src/core/closet/petCloset";
import type { PetStudyAward } from "../../../src/core/closet/petStudyCredit";
import { characterCount } from "../../../src/core/kits/kitSettingsSchema";
import {
  deliveryMessage,
  giftAdventureMessage,
  giftFromJSON,
  giftMessage,
  giftsEqual,
  giftToJSON,
  RARE_FURS,
  SurpriseGiftRules,
  SurpriseGiftState,
  type RareFur,
  type SurpriseGift,
} from "../../../src/core/motivation/surpriseGift";
import { colorHex } from "../../../src/core/pets/petPalette";
import { VersionedJSON } from "../../../src/core/persistence/versionedJson";
import { fixed, seeded } from "../coach/support";

const UTC = "UTC";
/* Noon UTC on the `day`th day after 2026-10-05, plus `minutes`. */
const time = (day: number, minutes = 0) => Date.UTC(2026, 9, 5 + day, 12, minutes) / 1000;
const award = (completedSessions: number, minutes: number, points: number): PetStudyAward => ({ completedSessions, minutes, points, unlocked: [] });

describe("SurpriseGiftState", () => {
  it("gives a gift on a winning roll and counts a losing one toward pity", () => {
    const state = new SurpriseGiftState();
    expect(state.roll(time(0), 25, UTC, fixed(0.9))).toBeUndefined();
    expect(state.dryRolls).toBe(1);
    expect(state.roll(time(1), 25, UTC, fixed(0))).toEqual({ kind: "bonusPoints", points: 10 });
    expect(state.dryRolls).toBe(0);
    expect(state.lastGiftDay).toBe("2026-10-06");
  });

  it("never rolls for short sessions", () => {
    const state = new SurpriseGiftState();
    expect(state.roll(time(0), 14, UTC, fixed(0))).toBeUndefined();
    expect(state.dryRolls).toBe(0);
    expect(state.roll(time(0, 30), 15, UTC, fixed(0))).toBeDefined();
  });

  it("gives at most one gift a day, and capped sessions don't count toward pity", () => {
    const state = new SurpriseGiftState();
    expect(state.roll(time(0), 25, UTC, fixed(0))).toBeDefined();
    for (let session = 1; session <= 5; session++) expect(state.roll(time(0, session * 30), 25, UTC, fixed(0))).toBeUndefined();
    expect(state.dryRolls).toBe(0);
    expect(state.roll(time(1), 25, UTC, fixed(0))).toBeDefined();
  });

  it("guarantees a gift after a dry spell", () => {
    const state = new SurpriseGiftState();
    for (let day = 0; day < SurpriseGiftRules.pityAfter; day++) expect(state.roll(time(day), 25, UTC, fixed(0.99))).toBeUndefined();
    expect(state.dryRolls).toBe(SurpriseGiftRules.pityAfter);
    expect(state.roll(time(SurpriseGiftRules.pityAfter), 25, UTC, fixed(0.99))).toBeDefined();
    expect(state.dryRolls).toBe(0);
  });

  it("never rolls the same session twice, even after a restart", () => {
    const state = new SurpriseGiftState();
    expect(state.roll(time(0), 25, UTC, fixed(0.9))).toBeUndefined();
    const restored = SurpriseGiftState.decode(state.encoded());
    expect(restored.toJSON()).toEqual(state.toJSON());
    expect(restored.roll(time(0), 25, UTC, fixed(0))).toBeUndefined();
    expect(restored.roll(time(0, -30), 25, UTC, fixed(0))).toBeUndefined();
    expect(restored.dryRolls).toBe(1);
  });

  it("brings a gift for about one qualifying session in five", () => {
    const state = new SurpriseGiftState();
    const random = seeded(11);
    let gifts = 0;
    const days = 4000;
    for (let day = 0; day < days; day++) if (state.roll(time(day), 25, UTC, random)) gifts += 1;
    const rate = gifts / days;
    expect(rate).toBeGreaterThan(0.19);
    expect(rate).toBeLessThan(0.27);
  });

  it("finds each rare fur once and gives seasonal minutes only during an event", () => {
    const state = new SurpriseGiftState();
    const random = seeded(3);
    const furs: RareFur[] = [];
    let seasonal = 0;
    for (let day = 0; day < 2000; day++) {
      const season = day % 2 === 0 ? "halloween" : undefined;
      const gift = state.roll(time(day), 25, UTC, random, season);
      if (gift?.kind === "rareFur") furs.push(gift.fur);
      if (gift?.kind === "seasonMinutes") {
        expect(gift.eventID).toBe("halloween");
        expect(gift.minutes).toBe(SurpriseGiftRules.seasonMinutes);
        expect(day % 2).toBe(0);
        seasonal += 1;
      }
      if (gift?.kind === "bonusPoints") expect(SurpriseGiftRules.bonusPoints).toContain(gift.points);
    }
    expect(furs).toEqual(RARE_FURS);
    expect(state.rareFurs).toEqual(RARE_FURS);
    expect(seasonal).toBeGreaterThan(0);
    expect(state.history.length).toBeLessThanOrEqual(SurpriseGiftRules.historyLimit);
  });

  it("keeps rare furs out of the Closet's swatches, and the Closet names them", () => {
    for (const fur of RARE_FURS) {
      expect(PetCloset.furSwatches.map(colorHex)).not.toContain(colorHex(fur.color));
      expect(PetCloset.swatchName(fur.color)).toBe(fur.name);
    }
  });

  it("rolls an award only for completed sessions, at one session's length", () => {
    const state = new SurpriseGiftState();
    expect(state.rollAfter(award(0, 40, 30), time(0), UTC, fixed(0))).toBeUndefined();
    expect(state.rollAfter(award(2, 20, 30), time(0), UTC, fixed(0))).toBeUndefined();
    expect(state.dryRolls).toBe(0);
    expect(state.rollAfter(award(1, 25, 35), time(0), UTC, fixed(0))).toBeDefined();
  });

  it("round-trips through its versioned file", () => {
    const state = new SurpriseGiftState();
    state.roll(1_800_000_000, 25, UTC, fixed(0));
    const text = state.encoded();
    expect(VersionedJSON.version(text)).toBe(SurpriseGiftState.schema.current);
    expect(SurpriseGiftState.decode(text).toJSON()).toEqual(state.toJSON());
    expect(JSON.parse(text).history[0].sessionEnd).toBe(1_800_000_000 - 978_307_200);
  });

  it("has rare furs but no history or pity in the demo", () => {
    const demo = SurpriseGiftState.demo();
    expect(demo.rareFurs).toHaveLength(2);
    expect(demo.history).toEqual([]);
    expect(demo.dryRolls).toBe(0);
  });
});

describe("SurpriseGift", () => {
  const gifts: SurpriseGift[] = [
    ...SurpriseGiftRules.bonusPoints.map((points): SurpriseGift => ({ kind: "bonusPoints", points })),
    ...RARE_FURS.map((fur): SurpriseGift => ({ kind: "rareFur", fur })),
    { kind: "seasonMinutes", eventID: "halloween", minutes: 15 },
  ];

  it("says every gift in one short line", () => {
    for (const gift of gifts) {
      expect(characterCount(giftMessage(gift))).toBeLessThanOrEqual(40);
      expect(characterCount(giftAdventureMessage(gift))).toBeLessThanOrEqual(characterCount(giftMessage(gift)));
    }
  });

  it("says a gift from an adventure was found", () => {
    const gift: SurpriseGift = { kind: "bonusPoints", points: 15 };
    expect(deliveryMessage({ gift, date: 0 })).toBe("A gift: 15 bonus points");
    expect(deliveryMessage({ gift, date: 0, adventure: { line: "leaf", date: 0, gift: { kind: "bonusPoints", points: 15 } } })).toBe(
      "Found: 15 bonus points",
    );
  });

  it("round-trips every gift as JSON and rejects unknown ones", () => {
    const samples: SurpriseGift[] = [
      { kind: "bonusPoints", points: 20 },
      { kind: "rareFur", fur: RARE_FURS[2] ?? (RARE_FURS[0] as RareFur) },
      { kind: "seasonMinutes", eventID: "lunar:new-year", minutes: 15 },
    ];
    for (const gift of samples) expect(giftsEqual(giftFromJSON(JSON.parse(JSON.stringify(giftToJSON(gift)))), gift)).toBe(true);
    expect(() => giftFromJSON({ kind: "crown", value: "1" })).toThrow();
    expect(() => giftFromJSON({ kind: "rareFur", value: "gold" })).toThrow();
  });
});
