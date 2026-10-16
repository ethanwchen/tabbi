import { beforeAll, describe, expect, it } from "vitest";
import { ACTIVITY_METADATA, makeActivityRecord, type ActivityRecord } from "../../src/core/activity/activityRecord";
import { PetCloset, type PetClosetItemState } from "../../src/core/closet/petCloset";
import { PET_PRICE_TIERS, PetEconomy, tierForCost, tierPriceRange } from "../../src/core/closet/petEconomy";
import {
  PET_MILESTONES,
  PetMilestoneProgress,
  editionEffect,
  editionMilestone,
  editionSource,
  limitedEditionOf,
  limitedProgressFraction,
  milestoneGoal,
  milestoneProgress,
  seasonalReward,
} from "../../src/core/closet/petLimited";
import {
  awardHeadline,
  awardIsLevelUp,
  awardPointsText,
  awardUnlockLine,
  creditPartySession,
  creditRecord,
  type PetStudyAward,
} from "../../src/core/closet/petStudyCredit";
import { occurrenceID, nextOccurrence, type SeasonalEventOccurrence } from "../../src/core/events/seasonalEvent";
import { SeasonalEventCatalog, SeasonalEventTally, type PetLimitedShelf } from "../../src/core/events/seasonalEventCatalog";
import { UnlockProgress } from "../../src/core/motivation/unlockProgress";
import { accessorySlot, coversEyes, type PetAccessory, type PetOutfit } from "../../src/core/pets/petCostume";
import { itemFromID, itemParts, type PetItem } from "../../src/core/pets/petItem";
import { LATEST_RELEASE, itemIsNew, itemRelease, itemTheme } from "../../src/core/pets/petItemTheme";
import type { PetBreed } from "../../src/core/pets/petKinds";
import { PetPointsRules } from "../../src/core/pets/petPointsRules";
import { PetProfile } from "../../src/core/pets/petProfile";
import { PetSave } from "../../src/core/pets/petSave";
import {
  ALL_ITEMS,
  PetPointsLedger,
  PetPurchaseError,
  SHOP_ITEMS,
  StreakFreezePurchaseError,
  isFree,
  itemCost,
  itemTier,
} from "../../src/core/pets/petUnlocks";
import type { DayCalendar } from "../../src/core/streaks/dayCalendar";
import { StreakFreezeRules, StudyStreak } from "../../src/core/streaks/studyStreak";
import { switchLanguage } from "../support/catalogs";
import { loadFixture } from "../support/fixtures";
import { goldenDiff } from "../support/goldenCompare";

/*
 * Replays shared/fixtures/closet (written by ClosetGoldenTests on the Mac):
 * every item's price, tier, shelf and unlock rule, the points rules and
 * typical pace, stored ledgers, the end-of-session unlock bar, Closet step
 * sequences (study, gifts, Party stays, logged records, taps, purchases and
 * server grants), milestones, extra streak freezes, seasonal event windows,
 * the Limited shelves and seasonal tallies. Only inputs are read; every
 * recorded output is compared.
 */

interface ClosetFixture {
  schema: string;
  version: number;
  rules: Record<string, unknown>;
  tiers: { tier: string; minPrice: number; maxPrice: number }[];
  items: Record<string, unknown>[];
  catalog: Record<string, unknown>;
  points: { minutes: number; completed: boolean; points: number }[];
  sharedPoints: { minutes: number; friends: number; finished: boolean; points: number }[];
  pace: { points: number }[];
  tierLookups: { cost: number; tier?: string }[];
  ledgers: { name: string; json: string; output?: unknown }[];
  unlockProgress: { name: string; input: UnlockInput; output?: unknown }[];
  closets: ClosetScenario[];
  milestones: { name: string; input: { timeZone: string; today: number; records: RecordJson[] }; output: unknown }[];
  freezes: { name: string; input: FreezeInput; output: unknown[] }[];
  windows: { timeZone: string; event: string; from: number; runs: unknown[] }[];
  moments: { timeZone: string; at: number }[];
  seasonalTallies: { name: string; input: { timeZone: string; records: RecordJson[]; queries: number[] }; output: unknown }[];
}

interface UnlockInput {
  balance: number;
  earned: number;
  purchased: string[];
  pointsPerSession?: number;
}

interface ClosetStart {
  breed: string;
  outfit: string;
  accessories: string[];
  earned: number;
  spent: number;
  purchased: string[];
  granted: string[];
}

interface ClosetOp {
  op: string;
  item?: string;
  minutes?: number;
  completed?: boolean;
  friends?: number;
  finished?: boolean;
  points?: number;
  ids?: string[];
  recordID?: string;
  source?: string;
  outcome?: string;
  quantity?: number;
  at?: number;
}

interface ClosetScenario {
  name: string;
  start: ClosetStart;
  initial: unknown;
  steps: { op: ClosetOp; outcome: unknown; after: unknown }[];
}

interface RecordJson {
  id: string;
  source: string;
  kind: string;
  unit: string;
  start: number;
  end: number;
  quantity?: number;
  outcome?: string;
}

interface FreezeInput {
  timeZone: string;
  firstWeekday: number;
  earned: number;
  studyDays: string[];
  buys: number[];
}

const fixture = loadFixture<ClosetFixture>("closet/closet.json");

function expectGolden(actual: unknown, expected: unknown, label: string): void {
  const difference = goldenDiff(actual, expected);
  expect(difference, `${label}: ${difference ?? ""}`).toBeUndefined();
}

function item(id: string): PetItem {
  const parsed = itemFromID(id);
  if (!parsed) throw new Error(`Unknown item ${id}`);
  return parsed;
}

function calendar(timeZone: string, firstWeekday = 1): DayCalendar {
  return { timeZone, firstWeekday };
}

function activityRecord(json: RecordJson): ActivityRecord {
  return makeActivityRecord({
    id: json.id,
    source: json.source,
    kind: json.kind,
    start: json.start,
    end: json.end,
    ...(json.quantity !== undefined ? { quantity: json.quantity } : {}),
    unit: json.unit,
    metadata: json.outcome !== undefined ? { [ACTIVITY_METADATA.outcome]: json.outcome } : {},
  });
}

function unlockOutput(progress: UnlockProgress): Record<string, unknown> {
  return {
    item: progress.item,
    cost: progress.cost,
    balanceBefore: progress.balanceBefore,
    balance: progress.balance,
    pointsPerSession: progress.pointsPerSession,
    missing: progress.missing,
    isReady: progress.isReady,
    fractionBefore: progress.fractionBefore,
    fraction: progress.fraction,
    sessionsLeft: progress.sessionsLeft,
    isNear: progress.isNear,
    line: progress.line,
  };
}

function awardOutput(award: PetStudyAward): Record<string, unknown> {
  return {
    completedSessions: award.completedSessions,
    minutes: award.minutes,
    points: award.points,
    unlocked: [...award.unlocked],
    isLevelUp: awardIsLevelUp(award),
    headline: awardHeadline(award),
    unlockLine: awardUnlockLine(award),
    pointsText: awardPointsText(award),
  };
}

function stateName(state: PetClosetItemState): string {
  return state.kind;
}

function snapshot(closet: PetCloset): Record<string, unknown> {
  const ledger = closet.save.ledger;
  const states: Record<string, string> = {};
  for (const each of ALL_ITEMS) states[each] = stateName(closet.state(each));
  const next = closet.nextUnlock;
  return {
    earned: ledger.earned,
    spent: ledger.spent,
    balance: ledger.balance,
    purchased: [...ledger.purchased].sort(),
    granted: [...ledger.granted].sort(),
    outfit: closet.profile.outfit,
    accessories: [...closet.profile.accessories],
    nextUnlock: next?.item,
    nextUnlockMissing: next?.missing,
    states,
  };
}

function itemRow(each: PetItem): Record<string, unknown> {
  const parts = itemParts(each);
  const row: Record<string, unknown> = {
    id: each,
    kind: parts.kind,
    cost: itemCost(each),
    tier: itemTier(each),
    theme: itemTheme(each),
    release: itemRelease(each),
    isFree: isFree(each),
    isLimited: limitedEditionOf(each) !== undefined,
    isNew: itemIsNew(each),
  };
  if (parts.kind === "accessory") {
    row.slot = accessorySlot(parts.accessory);
    row.coversEyes = coversEyes(parts.accessory);
  }
  const edition = limitedEditionOf(each);
  if (edition) {
    const source = editionSource(edition);
    const milestone = editionMilestone(edition);
    row.limited = {
      edition,
      source: source.kind,
      sourceID: source.kind === "milestone" ? source.milestone : source.id,
      milestoneGoal: milestone ? milestoneGoal(milestone) : undefined,
      seasonFocusMinutes: seasonalReward(edition)?.focusMinutes,
      effect: editionEffect(edition),
    };
  }
  return row;
}

function runCloset(scenario: ClosetScenario): { initial: unknown; steps: unknown[] } {
  const { start } = scenario;
  const profile = new PetProfile("Kit", start.breed as PetBreed, {
    outfit: start.outfit as PetOutfit,
    accessories: start.accessories as PetAccessory[],
  });
  const ledger = new PetPointsLedger({
    earned: start.earned,
    spent: start.spent,
    purchased: start.purchased.map(item),
    granted: start.granted.map(item),
  });
  let closet = new PetCloset(new PetSave(profile, ledger));
  const initial = snapshot(closet);
  const steps = scenario.steps.map(({ op }) => {
    const outcome: Record<string, unknown> = {};
    const credited = (award: PetStudyAward | undefined) => {
      if (!award) return;
      outcome.award = awardOutput(award);
      const progress = UnlockProgress.after(award, closet);
      outcome.progress = progress ? unlockOutput(progress) : undefined;
    };
    switch (op.op) {
      case "study":
        outcome.points = closet.recordStudy(op.minutes ?? 0, op.completed ?? false);
        break;
      case "gift":
        closet.receiveGift(op.points ?? 0);
        break;
      case "party":
        credited(
          creditPartySession(closet, { minutes: op.minutes ?? 0, friendCount: op.friends ?? 0, finished: op.finished ?? false }),
        );
        break;
      case "record": {
        const end = op.at ?? 0;
        const quantity = op.quantity ?? 0;
        const record = makeActivityRecord({
          id: op.recordID ?? "",
          source: op.source ?? "",
          kind: "focus.completed",
          start: end - quantity * 60,
          end,
          quantity,
          unit: "min",
          metadata: op.outcome !== undefined ? { [ACTIVITY_METADATA.outcome]: op.outcome } : {},
        });
        credited(creditRecord(closet, record));
        break;
      }
      case "tap": {
        const result = closet.tap(item(op.item ?? ""));
        outcome.tap = result.kind;
        if (result.kind === "needsPoints") outcome.missing = result.missing;
        break;
      }
      case "buy": {
        const save = closet.save;
        try {
          save.ledger.buy(item(op.item ?? ""));
          outcome.purchase = "bought";
        } catch (error) {
          if (!(error instanceof PetPurchaseError)) throw error;
          outcome.purchase = error.reason;
          if (error.reason === "notEnoughPoints") outcome.missing = error.missing;
        }
        closet = new PetCloset(save);
        break;
      }
      case "grant":
        outcome.granted = closet.applyGrants(op.ids ?? []);
        break;
      default:
        throw new Error(`Unknown closet op ${op.op}`);
    }
    return { op, outcome, after: snapshot(closet) };
  });
  return { initial, steps };
}

function eventRun(occurrence: SeasonalEventOccurrence, timeZone: string): Record<string, unknown> {
  return {
    event: occurrence.event.id,
    id: occurrenceID(occurrence, timeZone),
    start: occurrence.start,
    end: occurrence.end,
  };
}

function shelfRow(shelf: PetLimitedShelf, timeZone: string): Record<string, unknown> {
  const items = [...shelf.items];
  if (shelf.kind.kind === "event") {
    return { kind: "event", run: eventRun(shelf.kind.occurrence, timeZone), isActive: shelf.kind.isActive, items };
  }
  return { kind: shelf.kind.kind, items };
}

const catalog = SeasonalEventCatalog.bundled;

describe("closet golden fixture", () => {
  beforeAll(() => switchLanguage("en"));

  it("reads the fixture it expects", () => {
    expect(fixture.schema).toBe("tabbi.closet.golden");
    expect(fixture.version).toBe(1);
  });

  it("has the same points rules and typical habit", () => {
    expectGolden(
      {
        pointsPerMinute: PetPointsRules.pointsPerMinute,
        minimumMinutes: PetPointsRules.minimumMinutes,
        completionBonus: PetPointsRules.completionBonus,
        bonusMinutes: PetPointsRules.bonusMinutes,
        sharedBonusPerFriend: PetPointsRules.sharedBonusPerFriend,
        maxSharedBonus: PetPointsRules.maxSharedBonus,
        typicalBlocksPerDay: PetEconomy.typicalBlocksPerDay,
        typicalBlockMinutes: PetEconomy.typicalBlockMinutes,
        typicalStudyDaysPerWeek: PetEconomy.typicalStudyDaysPerWeek,
        pointsPerTypicalBlock: PetEconomy.pointsPerTypicalBlock(),
        pointsPerTypicalDay: PetEconomy.pointsPerTypicalDay(),
        pointsPerTypicalWeek: PetEconomy.pointsPerTypicalWeek(),
        streakFreezeFreePerWeek: StreakFreezeRules.freePerWeek,
        streakFreezePrice: StreakFreezeRules.price(),
        streakFreezeMaxHeld: StreakFreezeRules.maxHeld,
        unlockNearSessions: UnlockProgress.nearSessions,
        minutesForStudyDay: PetMilestoneProgress.minutesForStudyDay,
        latestRelease: LATEST_RELEASE,
        milestoneGoals: Object.fromEntries(PET_MILESTONES.map((milestone) => [milestone, milestoneGoal(milestone)])),
      },
      fixture.rules,
      "rules",
    );
  });

  it("has the same price tiers", () => {
    expectGolden(
      PET_PRICE_TIERS.map((tier) => {
        const range = tierPriceRange(tier);
        return { tier, minPrice: range.lower, maxPrice: range.upper };
      }),
      fixture.tiers,
      "tiers",
    );
  });

  it("prices, tiers, shelves and unlocks every item in the same order", () => {
    expect(ALL_ITEMS.map(String)).toEqual(fixture.items.map((row) => row.id));
    for (const [index, row] of fixture.items.entries()) {
      const each = ALL_ITEMS[index];
      if (!each) throw new Error(`Missing item ${index}`);
      expectGolden(itemRow(each), row, `item ${String(row.id)}`);
    }
  });

  it("has the same shop order, wardrobe, limited shelf and themed shelves", () => {
    expectGolden(
      {
        shopOrder: [...SHOP_ITEMS],
        wardrobe: [...PetCloset.wardrobe],
        limitedShelf: [...PetCloset.limitedShelf],
        shelves: PetCloset.shelves.map((shelf) => ({ theme: shelf.theme, items: [...shelf.items] })),
      },
      fixture.catalog,
      "catalog",
    );
  });

  it("pays the same points for solo sessions and Party stays", () => {
    for (const row of fixture.points) {
      expect(PetPointsRules.points(row.minutes, row.completed), JSON.stringify(row)).toBe(row.points);
    }
    for (const row of fixture.sharedPoints) {
      expect(PetPointsRules.sharedPoints(row.minutes, row.friends, row.finished), JSON.stringify(row)).toBe(row.points);
    }
  });

  it("paces points in typical blocks, days and weeks", () => {
    for (const row of fixture.pace) {
      expectGolden(
        {
          points: row.points,
          typicalBlocks: PetEconomy.typicalBlocks(row.points),
          typicalDays: PetEconomy.typicalDays(row.points),
          typicalWeeks: PetEconomy.typicalWeeks(row.points),
          studyToEarn: PetEconomy.studyToEarn(row.points),
        },
        row,
        `pace ${row.points}`,
      );
    }
  });

  it("looks up the tier of every sample price", () => {
    for (const row of fixture.tierLookups) {
      expectGolden({ cost: row.cost, tier: tierForCost(row.cost) }, row, `tier of ${row.cost}`);
    }
  });

  it("decodes, cleans up and re-encodes stored ledgers", () => {
    for (const row of fixture.ledgers) {
      let output: unknown;
      try {
        const ledger = PetPointsLedger.fromJSON(JSON.parse(row.json));
        output = {
          earned: ledger.earned,
          spent: ledger.spent,
          balance: ledger.balance,
          purchased: [...ledger.purchased].sort(),
          granted: [...ledger.granted].sort(),
          nextUnlock: ledger.nextUnlock,
          encoded: JSON.stringify(sortKeys(ledger.toJSON())),
        };
      } catch {
        output = undefined;
      }
      if (row.output === undefined) expect(output, row.name).toBeUndefined();
      else expectGolden(output, row.output, `ledger ${row.name}`);
    }
  });

  it("fills the end-of-session unlock bar", () => {
    for (const row of fixture.unlockProgress) {
      const ledger = new PetPointsLedger({ earned: row.input.balance, purchased: row.input.purchased.map(item) });
      const progress = UnlockProgress.make(row.input.balance, ledger, row.input.earned, row.input.pointsPerSession);
      if (row.output === undefined) expect(progress, row.name).toBeUndefined();
      else expectGolden(progress ? unlockOutput(progress) : undefined, row.output, `unlock ${row.name}`);
    }
  });

  for (const scenario of fixture.closets) {
    it(`replays the closet "${scenario.name}" step by step`, () => {
      const replayed = runCloset(scenario);
      expectGolden(replayed.initial, scenario.initial, `${scenario.name} initial`);
      expect(replayed.steps.length).toBe(scenario.steps.length);
      scenario.steps.forEach((step, index) => {
        expectGolden(replayed.steps[index], step, `${scenario.name} step ${index} (${step.op.op})`);
      });
    });
  }

  it("reads milestones from the activity log", () => {
    for (const row of fixture.milestones) {
      const zone = calendar(row.input.timeZone);
      const today = row.input.today;
      const progress = new PetMilestoneProgress(row.input.records.map(activityRecord), zone);
      const closet = new PetCloset(new PetSave(new PetProfile("Kit", "tuxedo")));
      const unlocked = closet.unlockMilestones(progress);
      expectGolden(
        {
          focusMinutes: progress.focusMinutes,
          studyDays: progress.studyDays,
          finishedPartySessions: progress.finishedPartySessions,
          longestStreak: progress.longestStreak(),
          currentStreak: progress.currentStreak(today, zone),
          milestones: PET_MILESTONES.map((milestone) => {
            const value = progress.value(milestone, today, zone);
            const shelf = milestoneProgress(milestone, value);
            return {
              milestone,
              value,
              isReached: progress.isReached(milestone),
              progress: { ...shelf, fraction: limitedProgressFraction(shelf) },
            };
          }),
          unlocked,
        },
        row.output,
        `milestones ${row.name}`,
      );
    }
  });

  it("buys extra streak freezes", () => {
    for (const row of fixture.freezes) {
      const zone = calendar(row.input.timeZone, row.input.firstWeekday);
      const ledger = new PetPointsLedger({ earned: row.input.earned });
      const output = row.input.buys.map((at) => {
        const streak = new StudyStreak(row.input.studyDays, ledger.streakFreezes, at, zone);
        let result = "bought";
        let missing: number | undefined;
        try {
          ledger.buyStreakFreeze(streak, at);
        } catch (error) {
          if (!(error instanceof StreakFreezePurchaseError)) throw error;
          result = error.reason;
          if (error.reason === "notEnoughPoints") missing = error.missing;
        }
        const after = new StudyStreak(row.input.studyDays, ledger.streakFreezes, at, zone);
        return {
          at,
          result,
          missing,
          balance: ledger.balance,
          extraFreezes: after.extraFreezes,
          freezesReady: after.freezesReady,
        };
      });
      expectGolden(output, row.output, `freezes ${row.name}`);
    }
  });

  it("finds the next runs of every seasonal event in each zone", () => {
    for (const row of fixture.windows) {
      const event = catalog.event(row.event);
      if (!event) throw new Error(`Unknown event ${row.event}`);
      const runs: unknown[] = [];
      let after = row.from;
      for (let index = 0; index < row.runs.length; index++) {
        const occurrence = nextOccurrence(event, after, row.timeZone);
        if (!occurrence) break;
        runs.push(eventRun(occurrence, row.timeZone));
        after = occurrence.start;
      }
      expectGolden({ ...row, runs }, row, `${row.event} in ${row.timeZone}`);
    }
  });

  it("features events and builds the Limited shelves", () => {
    for (const row of fixture.moments) {
      const { timeZone, at } = row;
      const featured = catalog.featured(at, timeZone);
      expectGolden(
        {
          timeZone,
          at,
          active: catalog.active(at, timeZone).map((occurrence) => eventRun(occurrence, timeZone)),
          next: (() => {
            const next = catalog.next(at, timeZone);
            return next ? eventRun(next, timeZone) : undefined;
          })(),
          featured: featured ? { run: eventRun(featured.occurrence, timeZone), isActive: featured.isActive } : undefined,
          shelves: catalog.limitedShelves(at, timeZone).map((shelf) => shelfRow(shelf, timeZone)),
        },
        row,
        `moment ${timeZone} at ${at}`,
      );
    }
  });

  it("tallies focus per seasonal event run", () => {
    const seasonalItems = catalog.events.flatMap((event) => event.rewards.map((reward) => reward.item));
    for (const row of fixture.seasonalTallies) {
      const tally = new SeasonalEventTally(catalog, row.input.timeZone, row.input.records.map(activityRecord));
      const closet = new PetCloset(new PetSave(new PetProfile("Kit", "tuxedo")));
      const unlocked = closet.unlockSeasonal(tally);
      expectGolden(
        {
          earned: tally.earned,
          runs: [...tally.runs.entries()]
            .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
            .map(([id, run]) => ({
              id,
              focusMinutes: run.focusMinutes,
              earned: run.earned,
              nextReward: run.nextReward?.item,
            })),
          progress: row.input.queries.map((at) => ({
            at,
            items: seasonalItems.flatMap((each) => {
              const progress = tally.progress(each, at);
              return progress ? [{ item: each, value: progress.value, goal: progress.goal, label: progress.label }] : [];
            }),
          })),
          unlocked,
        },
        row.output,
        `tally ${row.name}`,
      );
    }
  });
});

/** The value with object keys sorted, as the Mac's `.sortedKeys` encoder writes them. */
function sortKeys(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (typeof value !== "object" || value === null) return value;
  return Object.fromEntries(
    Object.keys(value)
      .sort()
      .map((key) => [key, sortKeys((value as Record<string, unknown>)[key])]),
  );
}
