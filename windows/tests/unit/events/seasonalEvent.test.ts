import Ajv2020 from "ajv/dist/2020";
import { beforeAll, describe, expect, it } from "vitest";
import { ACTIVITY_KINDS, ACTIVITY_UNITS, makeActivityRecord, type ActivityRecord } from "../../../src/core/activity/activityRecord";
import { instantOf } from "../../../src/core/calendar/zonedCalendar";
import { PetCloset, stateIsOwned } from "../../../src/core/closet/petCloset";
import { PET_LIMITED_EDITIONS, editionItem, editionSource, howToEarn, itemEffect, seasonalReward } from "../../../src/core/closet/petLimited";
import { limitedShelves, sameShelfKind, type PetLimitedShelf } from "../../../src/core/events/petLimitedShelf";
import {
  SeasonalEventProgress,
  SeasonalEventTally,
  eventDisplayName,
  eventDisplayTagline,
  eventHeadline,
  nextOccurrence,
  occurrenceContaining,
  occurrenceID,
  rewardGoalLabel,
  type SeasonalEvent,
} from "../../../src/core/events/seasonalEvent";
import { SeasonalEventCatalog, SeasonalEventCatalogError } from "../../../src/core/events/seasonalEventCatalog";
import { SEASONAL_EVENT_CALENDARS } from "../../../src/core/events/seasonalEventCalendar";
import { seasonalEventDemo } from "../../../src/core/events/seasonalEventDemo";
import { limitedProgressFraction } from "../../../src/core/closet/petLimited";
import { accessoryItem, outfitItem, type PetItem } from "../../../src/core/pets/petItem";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { PetSave } from "../../../src/core/pets/petSave";
import { macCatalog, switchLanguage } from "../../support/catalogs";
import { loadRepoJson } from "../../support/fixtures";

// Port of SeasonalEventTests.
const NEW_YORK = "America/New_York";

function date(year: number, month: number, day: number, hour = 0, minute = 0, zone = NEW_YORK): number {
  return instantOf({ year, month, day, hour, minute }, zone);
}

const halloween: SeasonalEvent = {
  id: "halloween",
  name: "Halloween",
  tagline: "Spooky season.",
  calendar: "gregorian",
  start: { month: 10, day: 17 },
  end: { month: 11, day: 2 },
  rewards: [
    { item: accessoryItem("witchHat"), focusMinutes: 90 },
    { item: accessoryItem("halo"), focusMinutes: 300 },
  ],
};

const winter: SeasonalEvent = {
  id: "winter",
  name: "Winter Holidays",
  tagline: "Warm drinks, cozy focus.",
  calendar: "gregorian",
  start: { month: 12, day: 14 },
  end: { month: 1, day: 3 },
  rewards: [{ item: accessoryItem("beanie"), focusMinutes: 240 }],
};

const lunarNewYear: SeasonalEvent = {
  id: "lunar-new-year",
  name: "Lunar New Year",
  tagline: "A fresh start.",
  calendar: "chinese",
  start: { month: 1, day: 1 },
  end: { month: 1, day: 15 },
  rewards: [{ item: accessoryItem("tinyCrown"), focusMinutes: 180 }],
};

let nextID = 0;

function focus(minutes: number, end: number, source = "focus"): ActivityRecord {
  nextID += 1;
  return makeActivityRecord({
    id: `00000000-0000-4000-8000-${String(nextID).padStart(12, "0")}`,
    source,
    kind: ACTIVITY_KINDS.focusCompleted,
    start: end - minutes * 60,
    end,
    quantity: minutes,
    unit: ACTIVITY_UNITS.minutes,
  });
}

function record(kind: string, start: number, end: number, quantity: number, unit: string, source: string): ActivityRecord {
  return makeActivityRecord({ source, kind, start, end, quantity, unit });
}

beforeAll(() => switchLanguage("en"));

describe("date windows", () => {
  it("run from local midnight of the first day through the last day", () => {
    const occurrence = occurrenceContaining(halloween, date(2026, 10, 20, 15), NEW_YORK);
    expect(occurrence?.start).toBe(date(2026, 10, 17));
    expect(occurrence?.end).toBe(date(2026, 11, 3));
    expect(occurrenceContaining(halloween, date(2026, 10, 17), NEW_YORK)).toBeDefined();
    expect(occurrenceContaining(halloween, date(2026, 11, 2, 23, 59), NEW_YORK)).toBeDefined();
    expect(occurrenceContaining(halloween, date(2026, 10, 16, 23, 59), NEW_YORK)).toBeUndefined();
    expect(occurrenceContaining(halloween, date(2026, 11, 3), NEW_YORK)).toBeUndefined();
    expect(occurrenceContaining(halloween, date(2026, 7, 1), NEW_YORK)).toBeUndefined();
  });

  it("follow the local time zone", () => {
    /* 03:00 on October 17 in Berlin is still October 16 in New York. */
    const instant = date(2026, 10, 17, 3, 0, "Europe/Berlin");
    expect(occurrenceContaining(halloween, instant, "Europe/Berlin")).toBeDefined();
    expect(occurrenceContaining(halloween, instant, NEW_YORK)).toBeUndefined();
    expect(occurrenceContaining(halloween, date(2026, 10, 25, 0, 0, "Asia/Tokyo"), "Asia/Tokyo")?.start).toBe(
      date(2026, 10, 17, 0, 0, "Asia/Tokyo"),
    );
  });

  it("keep whole days across a daylight saving change", () => {
    /* New York falls back on November 1, 2026: that day is 25 hours long. */
    expect(occurrenceContaining(halloween, date(2026, 11, 1, 12), NEW_YORK)?.end).toBe(date(2026, 11, 3));
  });

  it("wrap over New Year", () => {
    const december = occurrenceContaining(winter, date(2026, 12, 31, 22), NEW_YORK);
    const january = occurrenceContaining(winter, date(2027, 1, 2), NEW_YORK);
    expect(december).toEqual(january);
    expect(january?.start).toBe(date(2026, 12, 14));
    expect(january?.end).toBe(date(2027, 1, 4));
    expect(january && occurrenceID(january, NEW_YORK)).toBe("winter-2026");
    expect(occurrenceContaining(winter, date(2027, 1, 4), NEW_YORK)).toBeUndefined();
    expect(occurrenceContaining(winter, date(2026, 12, 13, 23), NEW_YORK)).toBeUndefined();
  });

  it("put Lunar New Year on the Chinese calendar", () => {
    /* Lunar New Year: February 6, 2027 and January 26, 2028. */
    const first = occurrenceContaining(lunarNewYear, date(2027, 2, 10), NEW_YORK);
    expect(first?.start).toBe(date(2027, 2, 6));
    expect(first?.end).toBe(date(2027, 2, 21));
    expect(occurrenceContaining(lunarNewYear, date(2027, 2, 5), NEW_YORK)).toBeUndefined();
    expect(nextOccurrence(lunarNewYear, date(2027, 3, 1), NEW_YORK)?.start).toBe(date(2028, 1, 26));
    /* In January before the new year, the run is still a year away. */
    expect(occurrenceContaining(lunarNewYear, date(2028, 1, 10), NEW_YORK)).toBeUndefined();
    expect(nextOccurrence(lunarNewYear, date(2028, 1, 10), NEW_YORK)?.start).toBe(date(2028, 1, 26));
  });

  it("come back next year", () => {
    const next = nextOccurrence(halloween, date(2026, 10, 20), NEW_YORK);
    expect(next?.start).toBe(date(2027, 10, 17));
    expect(next && occurrenceID(next, NEW_YORK)).toBe("halloween-2027");
    /* At exactly the start, the next run is next year's. */
    expect(nextOccurrence(halloween, date(2026, 10, 17), NEW_YORK)?.start).toBe(date(2027, 10, 17));
  });

  it("put the event ending soonest first and find the next one", () => {
    const valentines: SeasonalEvent = {
      id: "valentines",
      name: "Valentine's",
      tagline: "Love what you learn.",
      calendar: "gregorian",
      start: { month: 2, day: 7 },
      end: { month: 2, day: 14 },
      rewards: [{ item: accessoryItem("roundGlasses"), focusMinutes: 60 }],
    };
    const catalog = new SeasonalEventCatalog([halloween, winter, lunarNewYear, valentines]);
    expect(catalog.active(date(2027, 2, 10), NEW_YORK).map((run) => run.event.id)).toEqual(["valentines", "lunar-new-year"]);
    expect(catalog.active(date(2027, 3, 10), NEW_YORK)).toEqual([]);
    expect(catalog.next(date(2027, 3, 10), NEW_YORK)?.event.id).toBe("halloween");
    expect(catalog.next(date(2026, 11, 10), NEW_YORK)?.event.id).toBe("winter");
    expect(catalog.eventOffering(accessoryItem("beanie"))?.id).toBe("winter");
    expect(catalog.eventOffering(accessoryItem("chefHat"))).toBeUndefined();
  });
});

describe("earning", () => {
  it("counts only focus logged during the run", () => {
    const occurrence = occurrenceContaining(halloween, date(2026, 10, 20), NEW_YORK);
    if (!occurrence) throw new Error("no run");
    const inside = focus(50, date(2026, 10, 18, 10));
    const records = [
      inside,
      inside,
      focus(45, date(2026, 11, 2, 23)),
      focus(200, date(2026, 10, 16, 23)),
      focus(200, date(2026, 11, 3, 1)),
      focus(30, date(2025, 10, 20)),
      record(ACTIVITY_KINDS.breakTaken, date(2026, 10, 19), date(2026, 10, 19, 1), 60, ACTIVITY_UNITS.minutes, "focus"),
      record(ACTIVITY_KINDS.cardsReviewed, date(2026, 10, 19), date(2026, 10, 19), 80, ACTIVITY_UNITS.cards, "anki"),
    ];
    const progress = new SeasonalEventProgress(occurrence, records);
    expect(progress.focusMinutes).toBe(95);
    expect(progress.earned).toEqual([accessoryItem("witchHat")]);
    expect(progress.nextReward?.item).toBe(accessoryItem("halo"));
  });

  it("earns rewards in order, and progress reads", () => {
    const occurrence = occurrenceContaining(halloween, date(2026, 10, 20), NEW_YORK);
    if (!occurrence) throw new Error("no run");
    const [first, second] = halloween.rewards;
    if (!first || !second) throw new Error("no rewards");
    const progress = new SeasonalEventProgress(occurrence);
    expect(progress.earned).toEqual([]);
    expect(progress.nextReward?.item).toBe(accessoryItem("witchHat"));
    expect(progress.progress(first).label).toBe("0/90 min");

    progress.add(focus(75, date(2026, 10, 18, 9)));
    expect(progress.progress(first).label).toBe("75/90 min");
    expect(progress.progress(second).label).toBe("1/5 h");

    progress.add(focus(250, date(2026, 10, 25, 9)));
    expect(progress.earned).toEqual([accessoryItem("witchHat"), accessoryItem("halo")]);
    expect(progress.nextReward).toBeUndefined();
    const headline = progress.progress(second);
    expect(headline.label).toBe("5/5 h");
    expect(limitedProgressFraction(headline)).toBe(1);
    expect(eventHeadline(halloween)).toBe(accessoryItem("halo"));
  });

  it("starts a missed item over when the event returns", () => {
    const thisYear = occurrenceContaining(halloween, date(2026, 10, 20), NEW_YORK);
    if (!thisYear) throw new Error("no run");
    const nextYear = nextOccurrence(halloween, thisYear.start, NEW_YORK);
    if (!nextYear) throw new Error("no next run");
    const records = [focus(200, date(2026, 10, 20)), focus(60, date(2027, 10, 20))];
    expect(new SeasonalEventProgress(thisYear, records).focusMinutes).toBe(200);
    expect(new SeasonalEventProgress(nextYear, records).focusMinutes).toBe(60);
  });
});

describe("tally and ownership", () => {
  it("keeps each run apart and earns across runs", () => {
    const inHalloween = focus(100, date(2026, 10, 20, 9));
    const records = [
      inHalloween,
      inHalloween,
      focus(200, date(2026, 11, 10)),
      focus(240, date(2027, 1, 2, 22)),
      record(ACTIVITY_KINDS.cardsReviewed, date(2026, 10, 21), date(2026, 10, 21, 1), 500, ACTIVITY_UNITS.minutes, "anki"),
    ];
    const tally = new SeasonalEventTally(new SeasonalEventCatalog([halloween, winter]), NEW_YORK, records);
    expect(new Set(tally.runs.keys())).toEqual(new Set(["halloween-2026", "winter-2026"]));
    expect(tally.runs.get("halloween-2026")?.focusMinutes).toBe(100);
    expect(tally.earned).toEqual([accessoryItem("witchHat"), accessoryItem("beanie")]);
    expect(tally.progress(accessoryItem("witchHat"), date(2026, 10, 30))?.label).toBe("90/90 min");
    expect(tally.progress(accessoryItem("halo"), date(2026, 10, 30))?.label).toBe("1/5 h");
    expect(tally.progress(accessoryItem("halo"), date(2026, 11, 10))).toBeUndefined();
    expect(tally.progress(accessoryItem("beanie"), date(2026, 10, 30))).toBeUndefined();

    /* Next year's run starts from zero. */
    const nextYear = tally.active(date(2027, 10, 20));
    expect(nextYear.map((run) => run.occurrence.event.id)).toEqual(["halloween"]);
    expect(nextYear[0]?.focusMinutes).toBe(0);
    expect(tally.progress(accessoryItem("witchHat"), date(2027, 10, 20))?.label).toBe("0/90 min");
  });

  it("grants earned seasonal items once, and they stay owned", () => {
    const closet = new PetCloset(new PetSave(PetProfile.starter("cat")));
    const witchHat = editionItem("halloweenWitchHat");
    const pumpkin = editionItem("halloweenPumpkin");

    const tally = new SeasonalEventTally(SeasonalEventCatalog.bundled, NEW_YORK);
    tally.add(focus(60, date(2026, 10, 18, 9)));
    expect(closet.unlockSeasonal(tally)).toEqual([]);
    expect(stateIsOwned(closet.state(witchHat))).toBe(false);

    tally.add(focus(45, date(2026, 10, 19, 9)));
    expect(closet.unlockSeasonal(tally)).toEqual([witchHat]);
    expect(closet.unlockSeasonal(tally)).toEqual([]);
    expect(stateIsOwned(closet.state(witchHat))).toBe(true);
    expect(stateIsOwned(closet.state(pumpkin))).toBe(false);

    const nextYear = new SeasonalEventTally(SeasonalEventCatalog.bundled, NEW_YORK);
    expect(closet.unlockSeasonal(nextYear)).toEqual([]);
    expect(stateIsOwned(closet.state(witchHat))).toBe(true);
    expect(nextYear.progress(pumpkin, date(2027, 10, 20))?.label).toBe("0/5 h");
  });
});

describe("the catalog file", () => {
  const file = (events: string, schema = "events.v1") => `{"schema": "${schema}", "events": [${events}]}`;
  const event = (
    options: { id?: string; calendar?: string; start?: string; end?: string; rewards?: string } = {},
  ): string =>
    `{"id": "${options.id ?? "halloween"}", "name": "Halloween", "tagline": "Spooky season.", "calendar": "${options.calendar ?? "gregorian"}", ` +
    `"start": ${options.start ?? `{"month": 10, "day": 17}`}, "end": ${options.end ?? `{"month": 11, "day": 2}`}, ` +
    `"rewards": ${options.rewards ?? `[{"item": "accessory.witchHat", "focusMinutes": 90}]`}}`;

  it("decodes a valid file", () => {
    const catalog = SeasonalEventCatalog.decode(
      file(
        event() +
          "," +
          event({
            id: "lunar-new-year",
            calendar: "chinese",
            start: `{"month": 1, "day": 1}`,
            end: `{"month": 1, "day": 15}`,
            rewards: `[{"item": "accessory.beanie", "focusMinutes": 60}, {"item": "accessory.halo", "focusMinutes": 180}]`,
          }),
      ),
    );
    expect(catalog.events.map((entry) => entry.id)).toEqual(["halloween", "lunar-new-year"]);
    expect(catalog.events[0]?.rewards).toEqual([{ item: accessoryItem("witchHat"), focusMinutes: 90 }]);
    expect(catalog.events[1]?.calendar).toBe("chinese");
    expect(catalog.events[1] && eventHeadline(catalog.events[1])).toBe(accessoryItem("halo"));
  });

  it("rejects bad files at the bad value", () => {
    const rejects = (text: string, path: string) => {
      let error: unknown;
      try {
        SeasonalEventCatalog.decode(text);
      } catch (thrown) {
        error = thrown;
      }
      expect(error, path).toBeInstanceOf(SeasonalEventCatalogError);
      expect((error as SeasonalEventCatalogError).kind, path).toBe("invalidValue");
      expect((error as SeasonalEventCatalogError).path).toBe(path);
    };
    let schemaError: unknown;
    try {
      SeasonalEventCatalog.decode(file(event(), "events.v2"));
    } catch (thrown) {
      schemaError = thrown;
    }
    expect(schemaError).toMatchObject({ kind: "unsupportedSchema", path: "events.v2" });
    rejects(file(event({ id: "Halloween" })), "events[0].id");
    rejects(file(event() + "," + event({ rewards: `[{"item": "accessory.beanie", "focusMinutes": 60}]` })), "events[1].id");
    rejects(file(event({ start: `{"month": 2, "day": 29}` })), "events[0].start");
    rejects(file(event({ end: `{"month": 13, "day": 1}` })), "events[0].end");
    rejects(file(event({ calendar: "chinese", end: `{"month": 1, "day": 30}` })), "events[0].end");
    rejects(file(event({ rewards: "[]" })), "events[0].rewards");
    rejects(file(event({ rewards: `[{"item": "accessory.nope", "focusMinutes": 60}]` })), "events[0].rewards[0].item");
    rejects(file(event({ rewards: `[{"item": "accessory.beanie", "focusMinutes": 0}]` })), "events[0].rewards[0].focusMinutes");
    rejects(file(event({ rewards: `[{"item": "accessory.beanie", "focusMinutes": 150}]` })), "events[0].rewards[0].focusMinutes");
    rejects(
      file(event({ rewards: `[{"item": "accessory.beanie", "focusMinutes": 60}, {"item": "accessory.halo", "focusMinutes": 60}]` })),
      "events[0].rewards[1].focusMinutes",
    );
    rejects(file(event() + "," + event({ id: "fall" })), "events[1].rewards[0].item");
  });
});

describe("the bundled year", () => {
  const catalog = SeasonalEventCatalog.bundled;

  it("validates against events.v1", () => {
    const schema = loadRepoJson<Record<string, unknown>>("shared/schemas/events.v1.schema.json");
    const validate = new Ajv2020({ allErrors: true }).compile(schema);
    const bundled = loadRepoJson("Sources/TabbiKitCore/Events/events.json");
    expect(validate(bundled), JSON.stringify(validate.errors)).toBe(true);
  });

  it("names the same calendars as the schema, and its ids and items match the schema's patterns", () => {
    const schema = loadRepoJson<{ $defs: Record<string, { properties: Record<string, { enum?: string[]; pattern?: string }> }> }>(
      "shared/schemas/events.v1.schema.json",
    );
    expect(schema.$defs.event?.properties.calendar?.enum).toEqual([...SEASONAL_EVENT_CALENDARS]);
    const idPattern = new RegExp(schema.$defs.event?.properties.id?.pattern ?? "^$");
    const itemPattern = new RegExp(schema.$defs.reward?.properties.item?.pattern ?? "^$");
    for (const entry of catalog.events) {
      expect(entry.id).toMatch(idPattern);
      for (const reward of entry.rewards) expect(reward.item).toMatch(itemPattern);
    }
  });

  it("offers every seasonal item once, with an effect only on each headline item", () => {
    expect(new Set(catalog.events.map((entry) => entry.id))).toEqual(
      new Set(["lunar-new-year", "valentines", "spring", "exam-season", "summer", "halloween", "winter-holidays"]),
    );
    const seasonal = PET_LIMITED_EDITIONS.filter((edition) => editionSource(edition).kind === "season");
    for (const edition of seasonal) {
      const source = editionSource(edition);
      expect(catalog.eventOffering(editionItem(edition))?.id, edition).toBe(source.kind === "season" ? source.id : undefined);
      expect(seasonalReward(edition), edition).toBeDefined();
    }
    const offered = catalog.events.flatMap((entry) => entry.rewards.map((reward) => reward.item));
    expect(new Set(offered)).toEqual(new Set(seasonal.map(editionItem)));
    for (const entry of catalog.events) {
      for (const reward of entry.rewards) {
        expect(itemEffect(reward.item) !== undefined, `${entry.id} ${reward.item}`).toBe(reward.item === eventHeadline(entry));
      }
    }
    expect(seasonalReward("streakFlame")).toBeUndefined();
  });

  it("runs on the expected local days", () => {
    const active = (year: number, month: number, day: number, hour = 12) =>
      catalog.active(date(year, month, day, hour), NEW_YORK).map((run) => run.event.id);
    expect(active(2026, 10, 10)).toEqual([]);
    expect(active(2026, 10, 17, 0)).toEqual(["halloween"]);
    expect(catalog.active(date(2026, 10, 31, 23, 59), NEW_YORK).map((run) => run.event.id)).toEqual(["halloween"]);
    expect(active(2026, 11, 1, 0)).toEqual([]);
    expect(active(2027, 1, 6)).toEqual(["winter-holidays"]);
    expect(active(2027, 1, 7)).toEqual([]);
    expect(active(2027, 2, 6)).toEqual(["lunar-new-year"]);
    expect(active(2027, 2, 10)).toEqual(["valentines", "lunar-new-year"]);
    expect(active(2027, 5, 15)).toEqual(["exam-season"]);
    expect(active(2027, 7, 15)).toEqual(["summer"]);
    const next = catalog.next(date(2026, 10, 10), NEW_YORK);
    expect(next && occurrenceID(next, NEW_YORK)).toBe("halloween-2026");
  });

  it("finds Lunar New Year across the years, a leap month included", () => {
    /* 2025 has a leap sixth month; 2023 a leap second month. */
    const starts: [number, number, number][] = [
      [2023, 1, 22],
      [2024, 2, 10],
      [2025, 1, 29],
      [2026, 2, 17],
      [2027, 2, 6],
      [2028, 1, 26],
      [2029, 2, 13],
      [2030, 2, 3],
    ];
    for (const [year, month, day] of starts) {
      const run = occurrenceContaining(lunarNewYear, date(year, month, day, 12), NEW_YORK);
      expect(run?.start, `${year}`).toBe(date(year, month, day));
    }
  });

  it("features the current or next event, then the year ahead", () => {
    const shelves = (year: number, month: number, day: number): PetLimitedShelf[] =>
      limitedShelves(catalog, date(year, month, day, 12), NEW_YORK);
    const milestones: PetItem[] = ["backwardsCap", "flameHeadband", "goldenLaurel", "teamMedal", "foundersPin"].map((name) =>
      accessoryItem(name as Parameters<typeof accessoryItem>[0]),
    );
    for (const list of [shelves(2026, 10, 10), shelves(2026, 10, 20), shelves(2027, 2, 10)]) {
      expect(list.flatMap((shelf) => shelf.items).sort()).toEqual([...PetCloset.limitedShelf].sort());
      expect(list).toHaveLength(3);
      expect(list[1]?.kind.kind).toBe("milestones");
      expect(list[1]?.items).toEqual(milestones);
    }

    const october = shelves(2026, 10, 10);
    const upcoming = october[0]?.kind;
    if (upcoming?.kind !== "event") throw new Error("no featured event");
    expect(occurrenceID(upcoming.occurrence, NEW_YORK)).toBe("halloween-2026");
    expect(upcoming.isActive).toBe(false);
    expect(october[0]?.items).toEqual([accessoryItem("moonlitWitchHat"), accessoryItem("pumpkinHat")]);
    expect(october[2]?.kind).toEqual({ kind: "laterEvents" });
    expect(october[2]?.items).toEqual([
      accessoryItem("reindeerAntlers"),
      accessoryItem("snowScarf"),
      accessoryItem("lionDanceHat"),
      accessoryItem("heartGlasses"),
      accessoryItem("sakuraSprig"),
      outfitItem("studyHoodie"),
      accessoryItem("summerShades"),
    ]);

    const running = shelves(2026, 10, 20)[0]?.kind;
    expect(running?.kind === "event" && running.isActive && running.occurrence.event.id).toBe("halloween");

    const february = shelves(2027, 2, 10);
    const valentines = february[0]?.kind;
    expect(valentines?.kind === "event" && valentines.isActive && valentines.occurrence.event.id).toBe("valentines");
    expect(february[2]?.items[0]).toBe(accessoryItem("lionDanceHat"));
    expect(february[2]?.items.slice(-2)).toEqual([accessoryItem("reindeerAntlers"), accessoryItem("snowScarf")]);
    expect(february[0] && valentines && sameShelfKind(valentines, february[0].kind)).toBe(true);
  });

  it("runs the demo season part way through the featured event", () => {
    const october = seasonalEventDemo(date(2026, 10, 10), NEW_YORK);
    if (!october) throw new Error("no demo");
    expect(october.moment).toBe(date(2026, 10, 19, 12));
    const run = october.tally.active(october.moment)[0];
    expect(run && occurrenceID(run.occurrence, NEW_YORK)).toBe("halloween-2026");
    expect(run?.focusMinutes).toBe(60);
    expect(run?.nextReward?.item).toBe(accessoryItem("moonlitWitchHat"));
    expect(october.tally.progress(accessoryItem("moonlitWitchHat"), october.moment)?.label).toBe("60/90 min");
    expect(october.tally.earned).toEqual([]);

    const winterDemo = seasonalEventDemo(date(2027, 1, 3), NEW_YORK);
    expect(winterDemo?.moment).toBe(date(2026, 12, 16, 12));
    expect(winterDemo && winterDemo.tally.active(winterDemo.moment)[0]?.focusMinutes).toBe(60);
  });
});

describe("copy", () => {
  it("labels reward goals in the progress units", () => {
    expect(rewardGoalLabel({ item: accessoryItem("halo"), focusMinutes: 90 })).toBe("90 min");
    expect(rewardGoalLabel({ item: accessoryItem("halo"), focusMinutes: 300 })).toBe("5 h");
  });

  it("states the catalog goal in the seasonal copy", () => {
    expect(howToEarn("halloweenWitchHat")).toBe("Focus for 90 minutes during Halloween.");
    expect(howToEarn("halloweenPumpkin")).toBe("Focus for 5 hours during Halloween.");
    expect(howToEarn("valentinesGlasses")).toBe("Focus for 3 hours during Valentine's Week.");
  });

  it("translates every event name and tagline through the Mac's catalog", () => {
    for (const entry of SeasonalEventCatalog.bundled.events) {
      expect(macCatalog.strings[entry.name], entry.name).toBeDefined();
      expect(macCatalog.strings[entry.tagline], entry.tagline).toBeDefined();
    }
    for (const key of ["%lld min", "%lld h", "%lld/%lld min", "%lld/%lld h"]) expect(macCatalog.strings[key], key).toBeDefined();
    switchLanguage("de");
    const halloweenEvent = SeasonalEventCatalog.bundled.event("halloween");
    if (!halloweenEvent) throw new Error("no Halloween");
    expect(eventDisplayTagline(halloweenEvent)).not.toBe(halloweenEvent.tagline);
    expect(eventDisplayName(halloweenEvent)).toBe(macCatalog.strings.Halloween?.localizations?.de?.stringUnit?.value);
    switchLanguage("en");
  });
});
