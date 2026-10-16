import { isLimited } from "../closet/petLimited";
import { VersionedJSON } from "../persistence/versionedJson";
import { itemFromID, type PetItem } from "../pets/petItem";
import { PetProfile } from "../pets/petProfile";
import { PetSave } from "../pets/petSave";
import { PetPointsLedger } from "../pets/petUnlocks";
import type { Instant } from "../time";

/*
 * Port of SyncTally, SyncedPet, SyncDocument and SyncDays: the one document
 * Sign in with Apple keeps per account: the pet, its points and unlocks,
 * and the study days behind the streak. Calendar data, activity details,
 * AI data and settings never go in here.
 *
 * Merging is a join: commutative, associative and idempotent, so devices
 * that merge in any order end up with the same document and no device's
 * progress is lost. Points are a per-device tally (max of each counter),
 * unlocks and study days are unions, the longest streak is a maximum, and
 * the pet's look is last-writer-wins by its timestamp.
 *
 * The JSON is the Mac's byte for byte (sorted keys, ISO 8601 dates in whole
 * seconds, the same `schemaVersion`), since both apps read and write the
 * same server copy.
 */

/** Port of SyncTally: what one device added to the shared points, lifetime earned and spent. */
export interface SyncTally {
  readonly earned: number;
  readonly spent: number;
}

export function syncTally(earned = 0, spent = 0): SyncTally {
  return { earned: Math.max(0, earned), spent: Math.max(0, spent) };
}

/** The larger of each counter, so a merge never loses points. */
export function mergeTallies(a: SyncTally, b: SyncTally): SyncTally {
  return syncTally(Math.max(a.earned, b.earned), Math.max(a.spent, b.spent));
}

/* MARK: Dates and days */

/** `instant` as Foundation's `.iso8601` writes it: `2027-01-15T08:00:00Z`. */
export function iso8601(instant: Instant): string {
  return new Date(Math.floor(instant) * 1000).toISOString().replace(/\.\d{3}Z$/, "Z");
}

const ISO8601 = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(\.\d+)?(Z|[+-]\d{2}:?\d{2})$/;

/**
 * Reads an ISO 8601 date-time as the Mac's sync reader does: a zone (`Z` or
 * an offset) is required, and fractional seconds are cut off (towards
 * earlier), so two looks set in the same second tie. Undefined otherwise.
 */
export function parseISO8601(text: string): Instant | undefined {
  const match = ISO8601.exec(text);
  if (match === null) return undefined;
  const zone = (match[3] ?? "").replace(/^([+-]\d{2})(\d{2})$/, "$1:$2");
  const millis = Date.parse(`${match[1] ?? ""}${zone}`);
  return Number.isNaN(millis) ? undefined : millis / 1000;
}

/** Port of SyncDays: day arithmetic on `YYYY-MM-DD` strings, compared as plain dates in UTC. */
export const SyncDays = {
  /** Midnight UTC of a valid day, or undefined. */
  date(day: string): Instant | undefined {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(day);
    if (match === null) return undefined;
    const millis = Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
    const date = millis / 1000;
    return SyncDays.string(date) === day ? date : undefined;
  },

  string(date: Instant): string {
    const d = new Date(date * 1000);
    return `${String(d.getUTCFullYear()).padStart(4, "0")}-${String(d.getUTCMonth() + 1).padStart(2, "0")}-${String(d.getUTCDate()).padStart(2, "0")}`;
  },

  previous(day: string): string | undefined {
    const date = SyncDays.date(day);
    return date === undefined ? undefined : SyncDays.string(date - 86_400);
  },

  /** The run of consecutive days ending on `today`, or on the day before. */
  currentRun(days: ReadonlySet<string>, today: string): number {
    let day = days.has(today) ? today : SyncDays.previous(today);
    if (day === undefined || !days.has(day)) return 0;
    let run = 0;
    while (day !== undefined && days.has(day)) {
      run += 1;
      day = SyncDays.previous(day);
    }
    return run;
  },

  /** The longest run of consecutive days. */
  longestRun(days: ReadonlySet<string>): number {
    let longest = 0;
    let run = 0;
    let last: string | undefined;
    for (const day of [...days].sort()) {
      run = last !== undefined && SyncDays.previous(day) === last ? run + 1 : 1;
      longest = Math.max(longest, run);
      last = day;
    }
    return longest;
  },
} as const;

/* MARK: The pet */

/*
 * The profile's JSON the way the Mac's encoder writes it with sorted keys
 * (slashes escaped), so a tie between equal timestamps picks the same side
 * on every device.
 */
function sortedJSON(value: unknown): string {
  const sort = (item: unknown): unknown => {
    if (Array.isArray(item)) return item.map(sort);
    if (typeof item !== "object" || item === null) return item;
    const object = item as Record<string, unknown>;
    return Object.fromEntries(
      Object.keys(object)
        .filter((key) => object[key] !== undefined)
        .sort()
        .map((key) => [key, sort(object[key])]),
    );
  };
  return JSON.stringify(sort(value)).replaceAll("/", "\\/");
}

/** Port of SyncedPet: the pet's look as last chosen on any device, with when, so the newest choice wins. */
export class SyncedPet {
  readonly profile: PetProfile;
  /** Whole seconds, as the stored ISO 8601 date holds it, so a copy that went through the server compares equal. */
  readonly updatedAt: Instant;

  constructor(profile: PetProfile, updatedAt: Instant) {
    this.profile = profile;
    this.updatedAt = Math.floor(updatedAt);
  }

  /** The later of the two; equal times pick the same side on every device (by the profile's JSON). */
  merged(other: SyncedPet): SyncedPet {
    if (this.updatedAt !== other.updatedAt) return this.updatedAt > other.updatedAt ? this : other;
    return this.sortKey >= other.sortKey ? this : other;
  }

  private get sortKey(): string {
    return sortedJSON(this.profile.toJSON());
  }

  equals(other: SyncedPet): boolean {
    return this.updatedAt === other.updatedAt && this.profile.equals(other.profile);
  }

  toJSON(): Record<string, unknown> {
    return { profile: this.profile.toJSON(), updatedAt: iso8601(this.updatedAt) };
  }

  /** Throws when the profile or the date can't be read, as the Mac's decoding does. */
  static fromJSON(raw: unknown): SyncedPet {
    if (typeof raw !== "object" || raw === null || Array.isArray(raw)) throw new Error("A synced pet must be an object");
    const object = raw as Record<string, unknown>;
    const updatedAt = typeof object.updatedAt === "string" ? parseISO8601(object.updatedAt) : undefined;
    if (updatedAt === undefined) throw new Error("A synced pet needs updatedAt");
    return new SyncedPet(PetProfile.fromJSON(object.profile), updatedAt);
  }
}

/* MARK: The document */

export interface SyncDocumentInit {
  pet?: SyncedPet;
  tallies?: Readonly<Record<string, SyncTally>>;
  unlocks?: Iterable<string>;
  studyDays?: Iterable<string>;
  longestStreak?: number;
}

export class SyncDocument {
  /** The stored format. Bump with a migration step when it changes. */
  static readonly schema = new VersionedJSON(1);
  /** How many recent study days are kept: enough for any current streak over a year long. */
  static readonly keptStudyDays = 400;

  /** Undefined until a device with a pet has synced. */
  readonly pet: SyncedPet | undefined;
  /** Points per device, keyed by each device's sync id. */
  readonly tallies: ReadonlyMap<string, SyncTally>;
  /** Item ids bought on any device, kept as strings so a newer build's item survives an older one. */
  readonly unlocks: ReadonlySet<string>;
  private days: Set<string>;
  private longest: number;

  constructor(init: SyncDocumentInit = {}) {
    this.pet = init.pet;
    this.tallies = new Map(Object.entries(init.tallies ?? {}));
    this.unlocks = new Set(init.unlocks ?? []);
    this.days = new Set([...(init.studyDays ?? [])].filter((day) => SyncDays.date(day) !== undefined));
    this.longest = Math.max(0, init.longestStreak ?? 0, SyncDays.longestRun(this.days));
    this.trimStudyDays();
  }

  /** An empty document, as the server holds before any device pushed. */
  static readonly empty = new SyncDocument();

  /** Local days (`YYYY-MM-DD`) with focus time on any device. */
  get studyDays(): ReadonlySet<string> {
    return this.days;
  }

  /** The longest streak ever reached, including days since trimmed. */
  get longestStreak(): number {
    return this.longest;
  }

  private with(changes: SyncDocumentInit): SyncDocument {
    return new SyncDocument({
      ...(this.pet === undefined ? {} : { pet: this.pet }),
      tallies: Object.fromEntries(this.tallies),
      unlocks: this.unlocks,
      studyDays: this.days,
      longestStreak: this.longest,
      ...changes,
    });
  }

  /** A copy with another pet (or none). */
  withPet(pet: SyncedPet | undefined): SyncDocument {
    return new SyncDocument({
      ...(pet === undefined ? {} : { pet }),
      tallies: Object.fromEntries(this.tallies),
      unlocks: this.unlocks,
      studyDays: this.days,
      longestStreak: this.longest,
    });
  }

  /* MARK: Merge */

  merged(other: SyncDocument): SyncDocument {
    const pet = this.pet !== undefined && other.pet !== undefined ? this.pet.merged(other.pet) : (this.pet ?? other.pet);
    const tallies = new Map(this.tallies);
    for (const [device, tally] of other.tallies) {
      const mine = tallies.get(device);
      tallies.set(device, mine === undefined ? tally : mergeTallies(mine, tally));
    }
    return new SyncDocument({
      ...(pet === undefined ? {} : { pet }),
      tallies: Object.fromEntries(tallies),
      unlocks: [...this.unlocks, ...other.unlocks],
      studyDays: [...this.days, ...other.days],
      longestStreak: Math.max(this.longest, other.longest),
    });
  }

  /* MARK: Points */

  /** Earned points over all devices. */
  get earned(): number {
    return [...this.tallies.values()].reduce((sum, tally) => sum + tally.earned, 0);
  }

  /** Spent points over all devices. */
  get spent(): number {
    return [...this.tallies.values()].reduce((sum, tally) => sum + tally.spent, 0);
  }

  /**
   * The account's ledger: every device's points and every unlock this build
   * knows. Limited edition items come back as granted, not bought.
   */
  get ledger(): PetPointsLedger {
    const items = new Set([...this.unlocks].flatMap((id) => itemFromID(id) ?? []));
    return new PetPointsLedger({
      earned: this.earned,
      spent: this.spent,
      purchased: [...items].filter((item) => !isLimited(item)),
      granted: [...items].filter(isLimited),
    });
  }

  /* MARK: Streak */

  /** Days in a row with focus time, ending on `today` or the day before. */
  currentStreak(today: string): number {
    return SyncDays.currentRun(this.days, today);
  }

  /** Adds days with focus time. */
  addingStudyDays(days: Iterable<string>): SyncDocument {
    return this.with({ studyDays: [...this.days, ...days] });
  }

  private trimStudyDays(): void {
    if (this.days.size <= SyncDocument.keptStudyDays) return;
    this.days = new Set([...this.days].sort().slice(-SyncDocument.keptStudyDays));
  }

  /* MARK: Local state */

  /**
   * This document with one device's local pet folded in: its look (when it
   * changed after the synced one), its share of the points and its unlocks.
   * Call it on the document the save last adopted (`empty` before the first
   * sync); merge the result with the server's copy afterwards, never before.
   */
  recording(save: PetSave, changedAt: Instant | undefined, device: string): SyncDocument {
    let othersEarned = 0;
    let othersSpent = 0;
    for (const [key, tally] of this.tallies) {
      if (key === device) continue;
      othersEarned += tally.earned;
      othersSpent += tally.spent;
    }
    const mine = syncTally(save.ledger.earned - othersEarned, save.ledger.spent - othersSpent);
    const unlocks: PetItem[] = [...save.ledger.purchased, ...save.ledger.granted];
    const local = new SyncDocument({
      ...(changedAt === undefined ? {} : { pet: new SyncedPet(save.profile, changedAt) }),
      tallies: { [device]: mine },
      unlocks,
    });
    return this.merged(local);
  }

  /**
   * The local pet save updated to this document: the synced look (or the
   * local one when nothing synced yet), the account's ledger, and the local
   * focus credit bookkeeping kept. Limited items this device holds stay,
   * since a grant is never taken back, and so do its streak freezes.
   */
  applied(save: PetSave): PetSave {
    const ledger = this.ledger;
    for (const item of save.ledger.granted) ledger.grant(item);
    ledger.keepStreakFreezes(save.ledger);
    const updated = new PetSave((this.pet?.profile ?? save.profile).copy(), ledger);
    updated.version = save.version;
    updated.creditedFocusCount = save.creditedFocusCount;
    updated.creditedFocusSource = save.creditedFocusSource;
    return updated;
  }

  /* MARK: Equality and coding */

  equals(other: SyncDocument | undefined): boolean {
    if (other === undefined) return false;
    const samePet = this.pet === undefined || other.pet === undefined ? this.pet === other.pet : this.pet.equals(other.pet);
    const sameSet = (a: ReadonlySet<string>, b: ReadonlySet<string>) => a.size === b.size && [...a].every((x) => b.has(x));
    const sameTallies =
      this.tallies.size === other.tallies.size &&
      [...this.tallies].every(([key, tally]) => {
        const theirs = other.tallies.get(key);
        return theirs !== undefined && theirs.earned === tally.earned && theirs.spent === tally.spent;
      });
    return samePet && sameTallies && sameSet(this.unlocks, other.unlocks) && sameSet(this.days, other.days) && this.longest === other.longest;
  }

  /** The document's keys as the Mac's `encode(to:)` writes them (no `schemaVersion`). */
  toJSON(): Record<string, unknown> {
    const tallies: Record<string, SyncTally> = {};
    for (const [key, tally] of this.tallies) tallies[key] = { earned: tally.earned, spent: tally.spent };
    return {
      ...(this.pet === undefined ? {} : { pet: this.pet.toJSON() }),
      tallies,
      unlocks: [...this.unlocks].sort(),
      studyDays: [...this.days].sort(),
      longestStreak: this.longest,
    };
  }

  /** The document as stored on the server, with its `schemaVersion`, keys sorted. */
  encoded(): string {
    return sortedJSON({ ...this.toJSON(), [VersionedJSON.versionKey]: SyncDocument.schema.current });
  }

  /**
   * Reads a stored document leniently: a missing or unreadable field falls
   * back to empty, so one bad value never throws away the rest. Throws only
   * when the text is not a JSON object.
   */
  static decode(text: string): SyncDocument {
    return SyncDocument.schema.decode(text, (object) => SyncDocument.fromJSON(object));
  }

  /** Reads an already parsed document object (no migrations; see `decode`). */
  static fromJSON(object: Readonly<Record<string, unknown>>): SyncDocument {
    const strings = (value: unknown) =>
      Array.isArray(value) && value.every((item) => typeof item === "string") ? (value as string[]) : undefined;
    let pet: SyncedPet | undefined;
    try {
      pet = object.pet === undefined || object.pet === null ? undefined : SyncedPet.fromJSON(object.pet);
    } catch {
      pet = undefined;
    }
    const longest = object.longestStreak;
    return new SyncDocument({
      ...(pet === undefined ? {} : { pet }),
      tallies: readTallies(object.tallies) ?? {},
      unlocks: strings(object.unlocks) ?? [],
      studyDays: strings(object.studyDays) ?? [],
      longestStreak: typeof longest === "number" && Number.isInteger(longest) ? longest : 0,
    });
  }
}

/* The Mac decodes the tallies as one dictionary: one bad entry drops them all. */
function readTallies(value: unknown): Record<string, SyncTally> | undefined {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return undefined;
  const tallies: Record<string, SyncTally> = {};
  for (const [key, raw] of Object.entries(value as Record<string, unknown>)) {
    if (typeof raw !== "object" || raw === null) return undefined;
    const { earned, spent } = raw as Record<string, unknown>;
    if (typeof earned !== "number" || !Number.isInteger(earned) || typeof spent !== "number" || !Number.isInteger(spent)) return undefined;
    tallies[key] = { earned, spent };
  }
  return tallies;
}
