import type { PetStudyAward } from "../closet/petStudyCredit";
import { tr } from "../localization/tr";
import type { JournalEntry } from "../pets/petAdventure";
import { colorFromHex, type PetColor } from "../pets/petPalette";
import { REFERENCE_DATE_OFFSET } from "../pets/petUnlocks";
import type { JSONObject } from "../persistence/json";
import { VersionedJSON } from "../persistence/versionedJson";
import { isPlannerDayKey, plannerDayKeyOf, type PlannerDayKey } from "../planner/plannerDayKey";
import type { Instant } from "../time";
import { randomElement, randomUnit, type RandomSource } from "./randomSource";

/*
 * Port of SurpriseGift.swift: what the cat brings back. Gifts are earned by
 * finishing focus sessions only: never sold, never tied to payment, and
 * nothing is ever spent to roll.
 */

/** A fur color only a surprise gift brings, on top of the Closet's swatches. Port of RareFur. */
export interface RareFur {
  readonly id: string;
  /** The English name, which is also its catalog key. */
  readonly name: string;
  readonly color: PetColor;
}

function rareFur(id: string, name: string, hex: string): RareFur {
  const color = colorFromHex(hex);
  if (color === undefined) throw new Error(`Invalid rare fur color ${hex}`);
  return { id, name, color };
}

/**
 * The rare colors, in the order a collector would find them listed. Soft
 * enough to keep every breed's face readable, and none of them pink, which
 * would swallow the nose and cheeks.
 */
export const RARE_FURS: readonly RareFur[] = [
  rareFur("mint", "Mint", "#A9DCC4"),
  rareFur("honey", "Honey", "#E6C36A"),
  rareFur("midnight", "Midnight", "#5C6A8E"),
  rareFur("moonstone", "Moonstone", "#D7DCE8"),
];

export function rareFurNamed(id: string): RareFur | undefined {
  return RARE_FURS.find((fur) => fur.id === id);
}

/** The rare fur's name in the user's language. */
export function rareFurDisplayName(fur: RareFur): string {
  return tr(fur.name);
}

export type SurpriseGift =
  /** A few bonus points for the Closet. */
  | { readonly kind: "bonusPoints"; readonly points: number }
  /** A rare fur color to keep. */
  | { readonly kind: "rareFur"; readonly fur: RareFur }
  /** Focused minutes added toward the seasonal event running now. */
  | { readonly kind: "seasonMinutes"; readonly eventID: string; readonly minutes: number };

/** The gift on its own, e.g. "15 bonus points" or "the rare Mint fur". */
export function giftName(gift: SurpriseGift): string {
  switch (gift.kind) {
    case "bonusPoints":
      return tr("%lld bonus points", gift.points);
    case "rareFur":
      return tr("the rare %@ fur", rareFurDisplayName(gift.fur));
    case "seasonMinutes":
      return tr("%lld min toward the event", gift.minutes);
  }
}

/** What the gift is, short enough for one line in the coach's bubble; whole sentences so each language words them its own way. */
export function giftMessage(gift: SurpriseGift): string {
  switch (gift.kind) {
    case "bonusPoints":
      return tr("A gift: %lld bonus points", gift.points);
    case "rareFur":
      return tr("A gift: the rare %@ fur", rareFurDisplayName(gift.fur));
    case "seasonMinutes":
      return tr("A gift: %lld min toward the event", gift.minutes);
  }
}

/** The bubble's line for a gift the pet carried home from its adventure, e.g. "Found: 15 bonus points". */
export function giftAdventureMessage(gift: SurpriseGift): string {
  switch (gift.kind) {
    case "bonusPoints":
      return tr("Found: %lld bonus points", gift.points);
    case "rareFur":
      return tr("Found: the rare %@ fur", rareFurDisplayName(gift.fur));
    case "seasonMinutes":
      return tr("Found: %lld min toward the event", gift.minutes);
  }
}

/** The gift as a kind and a value, the way saves store it. */
export function storedGift(gift: SurpriseGift): { kind: string; value: string } {
  switch (gift.kind) {
    case "bonusPoints":
      return { kind: "bonusPoints", value: String(gift.points) };
    case "rareFur":
      return { kind: "rareFur", value: gift.fur.id };
    case "seasonMinutes":
      return { kind: "seasonMinutes", value: `${gift.eventID}:${gift.minutes}` };
  }
}

/* Swift's Int(String): an optional sign and digits, nothing else. */
function parseInt64(text: string): number | undefined {
  return /^[+-]?\d+$/.test(text) ? Number(text) : undefined;
}

/** The gift a save stored, or undefined for one this build doesn't know (a rare fur since removed, say). */
export function giftFromStored(kind: string, value: string): SurpriseGift | undefined {
  switch (kind) {
    case "bonusPoints": {
      const points = parseInt64(value);
      return points === undefined ? undefined : { kind, points };
    }
    case "rareFur": {
      const fur = rareFurNamed(value);
      return fur === undefined ? undefined : { kind, fur };
    }
    case "seasonMinutes": {
      const split = value.lastIndexOf(":");
      const minutes = split < 0 ? undefined : parseInt64(value.slice(split + 1));
      return minutes === undefined ? undefined : { kind, eventID: value.slice(0, split), minutes };
    }
    default:
      return undefined;
  }
}

/** The gift's Codable shape, `{ kind, value }`. */
export function giftToJSON(gift: SurpriseGift): JSONObject {
  return storedGift(gift);
}

/** Reads `giftToJSON`'s shape; throws on a malformed or unknown gift, as the Mac's decoder does. */
export function giftFromJSON(json: unknown): SurpriseGift {
  const { kind, value } = (typeof json === "object" && json !== null ? json : {}) as { kind?: unknown; value?: unknown };
  if (typeof kind !== "string" || typeof value !== "string") throw new TypeError("Invalid gift");
  const gift = giftFromStored(kind, value);
  if (gift === undefined) throw new TypeError(`Unknown gift ${kind}: ${value}`);
  return gift;
}

export function giftsEqual(a: SurpriseGift, b: SurpriseGift): boolean {
  const left = storedGift(a);
  const right = storedGift(b);
  return left.kind === right.kind && left.value === right.value;
}

/**
 * A gift as the cat hands it over, with the moment it came back: what the
 * app publishes, so whatever shows the pet can show what it carries.
 */
export interface SurpriseGiftDelivery {
  readonly gift: SurpriseGift;
  readonly date: Instant;
  /** The adventure the pet carried the gift home from, as its journal entry, or undefined when it stayed home. */
  readonly adventure?: JournalEntry;
}

/** The bubble's line: "Found: ..." after an adventure, otherwise "A gift: ...". */
export function deliveryMessage(delivery: SurpriseGiftDelivery): string {
  return delivery.adventure === undefined ? giftMessage(delivery.gift) : giftAdventureMessage(delivery.gift);
}

/** A gift given, kept so the same session can never pay twice. Port of SurpriseGiftRecord. */
export interface SurpriseGiftRecord {
  readonly day: PlannerDayKey;
  /** When the session that earned it ended. */
  readonly sessionEnd: Instant;
  /** `bonusPoints`, `rareFur` or `seasonMinutes`. */
  readonly kind: string;
  /** The points or minutes, or the rare fur's id. */
  readonly value: string;
}

/** The odds and sizes of surprise gifts, in one place for the tests and docs. */
export const SurpriseGiftRules = {
  /** Shorter sessions never roll. */
  minimumMinutes: 15,
  /** About one qualifying session in five brings a gift. */
  chance: 0.2,
  /** After this many qualifying sessions in a row without a gift, the next one always brings one. */
  pityAfter: 7,
  /** Bonus point sizes: a small treat next to a block's 35 points. */
  bonusPoints: [10, 15, 20] as readonly number[],
  /** Minutes a seasonal gift adds toward the event's items. */
  seasonMinutes: 15,
  /** How many records the history keeps. */
  historyLimit: 60,
} as const;

/**
 * The persisted state behind surprise gifts: the pity counter, the daily
 * cap, the rare furs found and the last session rolled, so a restart or a
 * replayed session can never roll again.
 */
export class SurpriseGiftState {
  static readonly schema = new VersionedJSON(1);

  /** Qualifying sessions since the last gift. */
  dryRolls = 0;
  /** When the last rolled session ended; older or equal sessions don't roll. */
  lastRolledSessionEnd: Instant | undefined;
  /** Rare fur ids found so far. */
  rareFursFound: string[] = [];
  /** Gifts given, newest last, capped at `SurpriseGiftRules.historyLimit`. */
  history: SurpriseGiftRecord[] = [];

  /** Two rare furs found, so a demo shows the Closet's Rare row. */
  static demo(): SurpriseGiftState {
    const state = new SurpriseGiftState();
    state.rareFursFound = RARE_FURS.slice(0, 2).map((fur) => fur.id);
    return state;
  }

  /** The day of the last gift, for the daily cap. */
  get lastGiftDay(): PlannerDayKey | undefined {
    return this.history[this.history.length - 1]?.day;
  }

  /** The rare furs found so far, in catalog order. */
  get rareFurs(): RareFur[] {
    return RARE_FURS.filter((fur) => this.rareFursFound.includes(fur.id));
  }

  /**
   * Rolls for a gift for a focus session that ran to its end at
   * `sessionEnd` after `focusMinutes` of focus. Sessions shorter than the
   * minimum, sessions no newer than the last one rolled, and sessions on a
   * day that already had a gift don't roll and don't move the pity counter.
   * A seasonal gift is only possible while `activeSeasonID` names an event.
   */
  roll(
    sessionEnd: Instant,
    focusMinutes: number,
    timeZone: string,
    random: RandomSource,
    activeSeasonID?: string,
  ): SurpriseGift | undefined {
    if (focusMinutes < SurpriseGiftRules.minimumMinutes) return undefined;
    if (this.lastRolledSessionEnd !== undefined && !(sessionEnd > this.lastRolledSessionEnd)) return undefined;
    this.lastRolledSessionEnd = sessionEnd;
    const day = plannerDayKeyOf(sessionEnd, timeZone);
    if (this.lastGiftDay === day) return undefined;

    const wins = this.dryRolls >= SurpriseGiftRules.pityAfter || randomUnit(random) < SurpriseGiftRules.chance;
    if (!wins) {
      this.dryRolls += 1;
      return undefined;
    }
    const gift = this.pickGift(random, activeSeasonID);
    this.dryRolls = 0;
    if (gift.kind === "rareFur") this.rareFursFound.push(gift.fur.id);
    this.history.push({ day, sessionEnd, ...storedGift(gift) });
    if (this.history.length > SurpriseGiftRules.historyLimit) {
      this.history.splice(0, this.history.length - SurpriseGiftRules.historyLimit);
    }
    return gift;
  }

  /**
   * Rolls for the focus session behind `award`, credited at `date`. Only an
   * award for sessions that ran to their end rolls (an early Stop never
   * does), at the length of one of those sessions.
   */
  rollAfter(award: PetStudyAward, date: Instant, timeZone: string, random: RandomSource, activeSeasonID?: string): SurpriseGift | undefined {
    if (!(award.completedSessions > 0)) return undefined;
    return this.roll(date, Math.trunc(award.minutes / award.completedSessions), timeZone, random, activeSeasonID);
  }

  /* Bonus points most of the time; a rare fur (while any is left) or seasonal minutes (while an event runs) now and then. */
  private pickGift(random: RandomSource, activeSeasonID: string | undefined): SurpriseGift {
    const points = randomElement(SurpriseGiftRules.bonusPoints, random);
    const options: { weight: number; gift: SurpriseGift }[] = [{ weight: 0.6, gift: { kind: "bonusPoints", points } }];
    const fur = RARE_FURS.find((candidate) => !this.rareFursFound.includes(candidate.id));
    if (fur !== undefined) options.push({ weight: 0.2, gift: { kind: "rareFur", fur } });
    if (activeSeasonID !== undefined) {
      options.push({ weight: 0.2, gift: { kind: "seasonMinutes", eventID: activeSeasonID, minutes: SurpriseGiftRules.seasonMinutes } });
    }
    let draw = randomUnit(random) * options.reduce((sum, option) => sum + option.weight, 0);
    for (const option of options) {
      if (draw < option.weight) return option.gift;
      draw -= option.weight;
    }
    return options[0]?.gift ?? { kind: "bonusPoints", points };
  }

  /** The Mac's Codable shape, dates as seconds since 2001. */
  toJSON(): JSONObject {
    const json: JSONObject = {
      dryRolls: this.dryRolls,
      rareFursFound: [...this.rareFursFound],
      history: this.history.map((record) => ({
        day: record.day,
        sessionEnd: record.sessionEnd - REFERENCE_DATE_OFFSET,
        kind: record.kind,
        value: record.value,
      })),
    };
    if (this.lastRolledSessionEnd !== undefined) json.lastRolledSessionEnd = this.lastRolledSessionEnd - REFERENCE_DATE_OFFSET;
    return json;
  }

  /** Reads `toJSON`'s shape, defaulting missing fields as the Mac does; throws on a malformed one. */
  static fromJSON(json: unknown): SurpriseGiftState {
    if (typeof json !== "object" || json === null || Array.isArray(json)) throw new TypeError("Invalid gift state");
    const object = json as Record<string, unknown>;
    const state = new SurpriseGiftState();
    const dry = object.dryRolls;
    if (dry !== undefined && dry !== null) {
      if (!Number.isInteger(dry)) throw new TypeError("Invalid dryRolls");
      state.dryRolls = dry as number;
    }
    const last = object.lastRolledSessionEnd;
    if (last !== undefined && last !== null) state.lastRolledSessionEnd = finiteNumber(last, "lastRolledSessionEnd") + REFERENCE_DATE_OFFSET;
    const furs = object.rareFursFound;
    if (furs !== undefined && furs !== null) {
      if (!Array.isArray(furs) || !furs.every((id): id is string => typeof id === "string")) throw new TypeError("Invalid rareFursFound");
      state.rareFursFound = [...furs];
    }
    const history = object.history;
    if (history !== undefined && history !== null) {
      if (!Array.isArray(history)) throw new TypeError("Invalid history");
      state.history = history.map(readRecord);
    }
    return state;
  }

  /** The state as its versioned JSON file (`schemaVersion` stamped). */
  encoded(): string {
    return SurpriseGiftState.schema.encode(this.toJSON(), { pretty: true, sortedKeys: true });
  }

  /** Reads a file written by `encoded`, running any migrations. */
  static decode(text: string): SurpriseGiftState {
    return SurpriseGiftState.schema.decode(text, (document) => SurpriseGiftState.fromJSON(document));
  }
}

function finiteNumber(value: unknown, key: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) throw new TypeError(`Invalid ${key}`);
  return value;
}

function readRecord(json: unknown): SurpriseGiftRecord {
  if (typeof json !== "object" || json === null || Array.isArray(json)) throw new TypeError("Invalid gift record");
  const { day, sessionEnd, kind, value } = json as Record<string, unknown>;
  if (typeof day !== "string" || !isPlannerDayKey(day)) throw new TypeError("Invalid day");
  if (typeof kind !== "string" || typeof value !== "string") throw new TypeError("Invalid gift record");
  return { day, sessionEnd: finiteNumber(sessionEnd, "sessionEnd") + REFERENCE_DATE_OFFSET, kind, value };
}
