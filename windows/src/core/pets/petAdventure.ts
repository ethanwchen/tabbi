import { tr } from "../localization/tr";
import type { DocumentStore } from "../persistence/documentStore";
import { VersionedJSON } from "../persistence/versionedJson";
import type { Instant } from "../time";
import type { ProvidedFocus } from "../providers/providedFocus";
import { REFERENCE_DATE_OFFSET } from "./petUnlocks";

/*
 * Port of PetAdventure.swift: the pet's little adventure during a long focus
 * block (it trots off partway through and comes back as the block ends) and
 * its adventure journal. Everything is a pure function of the shared focus
 * clock, so the island, the snapshots and the tests all agree.
 */

const MASK = (1n << 64n) - 1n;

/** SplitMix64's finalizer: spreads a seed into well mixed bits. */
export function mix64(value: bigint): bigint {
  let z = (value + 0x9e3779b97f4a7c15n) & MASK;
  z = ((z ^ (z >> 30n)) * 0xbf58476d1ce4e5b9n) & MASK;
  z = ((z ^ (z >> 27n)) * 0x94d049bb133111ebn) & MASK;
  return z ^ (z >> 31n);
}

/** Swift's `.rounded()`: half away from zero. */
function roundHalfAway(value: number): number {
  return value < 0 ? -Math.round(-value) : Math.round(value);
}

/** Where the pet is during an adventure. */
export type AdventurePhase =
  | { readonly kind: "home" }
  | { readonly kind: "leaving"; readonly progress: number }
  | { readonly kind: "away" }
  | { readonly kind: "returning"; readonly progress: number };

/** Whether the pet is out of its usual spot (walking or away). */
export function phaseIsOut(phase: AdventurePhase): boolean {
  return phase.kind !== "home";
}

/** How far along the path out the pet is: 0 at home, 1 out of sight. */
export function phaseDistance(phase: AdventurePhase): number {
  switch (phase.kind) {
    case "home":
      return 0;
    case "leaving":
      return phase.progress;
    case "away":
      return 1;
    case "returning":
      return 1 - phase.progress;
  }
}

const HOME: AdventurePhase = { kind: "home" };

export class PetAdventure {
  /** Focus blocks shorter than this keep the pet home. */
  static readonly minimumFocus = 15 * 60;
  /** How long the walk off (and back) takes. */
  static readonly walkDuration = 3;
  /** The part of the block that passes before the pet leaves, picked per block. */
  static readonly departureRange = { lower: 0.3, upper: 0.5 } as const;

  constructor(
    /** When the pet starts walking off. */
    readonly departsAt: Instant,
    /** When it starts walking back; it is home as the block ends. */
    readonly returnsAt: Instant,
    /** When the block ends. */
    readonly endsAt: Instant,
  ) {}

  /**
   * The adventure for a focus clock, or undefined when the pet stays home:
   * not a running focus countdown, a block shorter than `minimumFocus`, or
   * Reduce Motion on.
   */
  static plan(focus: ProvidedFocus | undefined, reduceMotion: boolean): PetAdventure | undefined {
    if (reduceMotion || !focus || focus.phase !== "focus" || focus.clock.kind !== "countdown") return undefined;
    const length = focus.phaseLength;
    if (length === undefined || length < PetAdventure.minimumFocus) return undefined;
    const endsAt = focus.clock.endsAt;
    const start = endsAt - length;
    const fraction = PetAdventure.departureFraction(endsAt);
    return new PetAdventure(start + length * fraction, endsAt - PetAdventure.walkDuration, endsAt);
  }

  /** Where the pet is at `now` for a focus clock. */
  static phaseFor(focus: ProvidedFocus | undefined, now: Instant, reduceMotion: boolean): AdventurePhase {
    return PetAdventure.plan(focus, reduceMotion)?.phase(now) ?? HOME;
  }

  /** Where the pet is at `now` in this adventure. */
  phase(now: Instant): AdventurePhase {
    const walk = PetAdventure.walkDuration;
    if (now < this.departsAt || now >= this.endsAt) return HOME;
    if (now < this.departsAt + walk) return { kind: "leaving", progress: (now - this.departsAt) / walk };
    if (now < this.returnsAt) return { kind: "away" };
    return { kind: "returning", progress: Math.min(1, (now - this.returnsAt) / walk) };
  }

  /** Whether the closed island says the pet is out exploring: from setting off until it starts back. */
  isExploring(now: Instant): boolean {
    const phase = this.phase(now).kind;
    return phase === "leaving" || phase === "away";
  }

  /** The next moment the phase changes after `now`, or undefined once the adventure is over. */
  nextChange(now: Instant): Instant | undefined {
    return [this.departsAt, this.departsAt + PetAdventure.walkDuration, this.returnsAt, this.endsAt].find(
      (date) => date > now,
    );
  }

  /**
   * The adventure that just came to its end as the clock moved from `old` to
   * `new`: the same clock finished the block with the pet already on its
   * way back.
   */
  static finished(
    old: ProvidedFocus | undefined,
    next: ProvidedFocus | undefined,
    now: Instant,
    reduceMotion: boolean,
  ): PetAdventure | undefined {
    if (!old || !next || old.source !== next.source || !(next.completedFocusCount > old.completedFocusCount)) {
      return undefined;
    }
    const adventure = PetAdventure.plan(old, reduceMotion);
    return adventure && now >= adventure.returnsAt ? adventure : undefined;
  }

  /** A stable fraction in `departureRange` for a block, from its end time. */
  static departureFraction(seed: Instant): number {
    const seconds = BigInt(roundHalfAway(seed - REFERENCE_DATE_OFFSET));
    const bits = mix64(BigInt.asUintN(64, seconds));
    const unit = Number(bits >> 11n) / 2 ** 53;
    const { lower, upper } = PetAdventure.departureRange;
    return lower + unit * (upper - lower);
  }
}

/** A surprise gift a pet carried home, as the journal stores it (a narrow copy of the Mac's SurpriseGift). */
export type JournalGift =
  | { readonly kind: "bonusPoints"; readonly points: number }
  | { readonly kind: "rareFur"; readonly id: string; readonly name: string }
  | { readonly kind: "seasonMinutes"; readonly eventID: string; readonly minutes: number };

/** The gift's short name, such as "15 bonus points". */
export function giftName(gift: JournalGift): string {
  switch (gift.kind) {
    case "bonusPoints":
      return tr("%lld bonus points", gift.points);
    case "rareFur":
      return tr("the rare %@ fur", tr(gift.name));
    case "seasonMinutes":
      return tr("%lld min toward the event", gift.minutes);
  }
}

const RARE_FURS: Record<string, string> = { mint: "Mint", honey: "Honey", midnight: "Midnight", moonstone: "Moonstone" };

function giftToJSON(gift: JournalGift): { kind: string; value: string } {
  switch (gift.kind) {
    case "bonusPoints":
      return { kind: "bonusPoints", value: String(gift.points) };
    case "rareFur":
      return { kind: "rareFur", value: gift.id };
    case "seasonMinutes":
      return { kind: "seasonMinutes", value: `${gift.eventID}:${gift.minutes}` };
  }
}

function giftFromJSON(raw: unknown): JournalGift | undefined {
  if (typeof raw !== "object" || raw === null) return undefined;
  const { kind, value } = raw as { kind?: unknown; value?: unknown };
  if (typeof kind !== "string" || typeof value !== "string") return undefined;
  switch (kind) {
    case "bonusPoints":
      return /^[+-]?\d+$/.test(value) ? { kind, points: Number(value) } : undefined;
    case "rareFur": {
      const name = RARE_FURS[value];
      return name ? { kind, id: value, name } : undefined;
    }
    case "seasonMinutes": {
      const split = value.lastIndexOf(":");
      const minutes = value.slice(split + 1);
      return split >= 0 && /^[+-]?\d+$/.test(minutes)
        ? { kind, eventID: value.slice(0, split), minutes: Number(minutes) }
        : undefined;
    }
    default:
      return undefined;
  }
}

/** One adventure in the journal; `line` is the stable id of its line. */
export interface JournalEntry {
  readonly line: string;
  readonly date: Instant;
  readonly gift?: JournalGift;
}

/** Every line, by stable id: places, small finds and friends made. */
export const JOURNAL_LINES: readonly { readonly id: string; readonly phrase: string }[] = [
  { id: "bookshelf", phrase: "explored the bookshelf" },
  { id: "windowsill", phrase: "napped on a sunny windowsill" },
  { id: "butterfly", phrase: "chased a butterfly" },
  { id: "leaf", phrase: "found a perfect leaf" },
  { id: "pigeon", phrase: "made friends with a pigeon" },
  { id: "puddle", phrase: "splashed in a puddle" },
  { id: "cloud", phrase: "watched a cloud shaped like a fish" },
  { id: "garden", phrase: "sniffed every flower in the garden" },
  { id: "sock", phrase: "rescued a lost sock" },
  { id: "acorn", phrase: "brought back a shiny acorn" },
  { id: "library", phrase: "snuck into the library" },
  { id: "snail", phrase: "raced a snail and let it win" },
  { id: "pebble", phrase: "collected a smooth pebble" },
  { id: "rooftop", phrase: "climbed onto the rooftop" },
  { id: "bakery", phrase: "visited the bakery" },
  { id: "rainbow", phrase: "spotted a tiny rainbow" },
  { id: "box", phrase: "explored a cardboard box" },
  { id: "bird", phrase: "learned a song from a bird" },
  { id: "park", phrase: "went around the park twice" },
  { id: "feather", phrase: "found a soft feather" },
];

/** The line `id` as a whole sentence with the pet's name, or undefined for a line this build doesn't know. */
export function journalSentence(id: string, petName: string): string | undefined {
  const line = JOURNAL_LINES.find((candidate) => candidate.id === id);
  /* One catalog key per line ("%@ explored the bookshelf"), so each language places the name where it reads best. */
  return line ? tr(`%@ ${line.phrase}`, petName) : undefined;
}

/** The entry's line with the pet's name. */
export function entryText(entry: JournalEntry, petName: string): string | undefined {
  return journalSentence(entry.line, petName);
}

/** The entry's line with the gift it brought home, for tooltips. */
export function entryDetail(entry: JournalEntry, petName: string): string | undefined {
  const sentence = entryText(entry, petName);
  if (sentence === undefined) return undefined;
  return entry.gift ? tr("%@ and brought back %@", sentence, giftName(entry.gift)) : sentence;
}

/**
 * The pet's adventure journal. Lines rotate like a shuffled deck: none
 * repeats until every line was used, decks are seeded, and a new deck
 * never starts with the line the last one ended on. Port of PetJournal.
 */
/* Stands in for the seed while the journal is written, so its exact digits can go in after. */
const SEED_PLACEHOLDER = "@seed@";

export class PetJournal {
  /** The most entries kept; older ones fall off. */
  static readonly maxEntries = 30;
  /** The journal's file format; version 1 is the first. */
  static readonly schema = new VersionedJSON(1);
  /** The journal's file format version, written as `schemaVersion`. */
  static readonly schemaVersion = PetJournal.schema.current;

  entries: JournalEntry[] = [];
  /** The line ids used in the current deck, in order. */
  deck: string[] = [];
  /** How many decks were finished, which reshuffles the next one. */
  decksFinished = 0;
  /** Seeds the order; set once per pet. */
  readonly seed: bigint;

  constructor(seed: bigint | number = 0) {
    this.seed = BigInt.asUintN(64, BigInt(seed));
  }

  /** The line id the next adventure gets. */
  get nextLine(): string {
    const ids = JOURNAL_LINES.map((line) => line.id);
    let remaining = ids.filter((id) => !this.deck.includes(id));
    if (remaining.length === 0) remaining = ids;
    const last = this.entries[this.entries.length - 1]?.line;
    if (this.deck.length === 0 && last !== undefined && remaining.length > 1) {
      remaining = remaining.filter((id) => id !== last);
    }
    const roll = mix64(
      (this.seed + ((BigInt(this.decksFinished) * 0x9e3779b9n) & MASK) + BigInt(this.deck.length)) & MASK,
    );
    return remaining[Number(roll % BigInt(remaining.length))] ?? ids[0] ?? "";
  }

  /** Writes the next adventure into the journal and returns it. */
  record(date: Instant): JournalEntry {
    const entry: JournalEntry = { line: this.nextLine, date };
    this.deck.push(entry.line);
    if (this.deck.length === JOURNAL_LINES.length) {
      this.deck = [];
      this.decksFinished += 1;
    }
    this.entries.push(entry);
    if (this.entries.length > PetJournal.maxEntries) this.entries.splice(0, this.entries.length - PetJournal.maxEntries);
    return entry;
  }

  /** The newest adventure. */
  get latest(): JournalEntry | undefined {
    return this.entries[this.entries.length - 1];
  }

  /** Notes the gift the pet carried home on `entry`; undefined when the entry is gone or already has one. */
  attach(gift: JournalGift, entry: JournalEntry): JournalEntry | undefined {
    for (let index = this.entries.length - 1; index >= 0; index--) {
      const candidate = this.entries[index];
      if (!candidate || candidate.line !== entry.line || candidate.date !== entry.date) continue;
      if (candidate.gift) return undefined;
      const updated = { ...candidate, gift };
      this.entries[index] = updated;
      return updated;
    }
    return undefined;
  }

  /** A short journal for demos: a few adventures over the last days, the newest an hour before `now`. */
  static demo(now: Instant): PetJournal {
    const journal = new PetJournal(5);
    for (const hoursAgo of [50, 26, 1]) journal.record(now - hoursAgo * 3600);
    return journal;
  }

  /** The Mac's JSON form: dates as seconds since 2001, plus `schemaVersion`. */
  toJSON(): Record<string, unknown> {
    return {
      entries: this.entries.map((entry) => ({
        line: entry.line,
        date: entry.date - REFERENCE_DATE_OFFSET,
        ...(entry.gift ? { gift: giftToJSON(entry.gift) } : {}),
      })),
      deck: [...this.deck],
      decksFinished: this.decksFinished,
      seed: Number(this.seed) <= Number.MAX_SAFE_INTEGER ? Number(this.seed) : this.seed.toString(),
      schemaVersion: PetJournal.schemaVersion,
    };
  }

  /** Reads a saved journal after any migration its version needs; throws when it isn't one. */
  static decode(text: string): PetJournal {
    /*
     * The Mac writes the seed as a plain 64-bit number, which JSON.parse would
     * round above 2^53, so its digits are read from the text itself (the
     * last match: sorted keys put the top-level seed after the entries).
     */
    const seedDigits = [...text.matchAll(/"seed"\s*:\s*(\d+)/g)].at(-1)?.[1];
    return PetJournal.schema.decode(text, (document) =>
      PetJournal.fromJSON(seedDigits === undefined ? document : { ...document, seed: seedDigits }),
    );
  }

  /** The journal file as the Mac writes it: pretty printed, sorted keys, the seed as a plain number. */
  encoded(): string {
    const text = PetJournal.schema.encode({ ...this.toJSON(), seed: SEED_PLACEHOLDER }, { pretty: true, sortedKeys: true });
    return text.replace(`"${SEED_PLACEHOLDER}"`, this.seed.toString());
  }

  /** The journal saved as `name` in `store`, or undefined when there is none yet. A corrupt file rejects, so the caller can decide not to overwrite it. */
  static async load(store: DocumentStore, name: string): Promise<PetJournal | undefined> {
    const text = await store.read(name);
    return text === undefined ? undefined : PetJournal.decode(text);
  }

  /** Saves the journal as `name` in `store`. */
  async write(store: DocumentStore, name: string): Promise<void> {
    await store.write(name, this.encoded());
  }

  /** Reads forgivingly: unknown deck ids and gifts are dropped, so a newer build's save still loads. */
  static fromJSON(raw: unknown): PetJournal {
    if (typeof raw !== "object" || raw === null || Array.isArray(raw)) throw new Error("A journal must be an object");
    const object = raw as Record<string, unknown>;
    const seed = typeof object.seed === "number" || typeof object.seed === "string" ? BigInt(object.seed) : 0n;
    const journal = new PetJournal(seed);
    if (Array.isArray(object.entries)) {
      journal.entries = object.entries.flatMap((value): JournalEntry[] => {
        if (typeof value !== "object" || value === null) throw new Error("A journal entry must be an object");
        const entry = value as Record<string, unknown>;
        if (typeof entry.line !== "string" || typeof entry.date !== "number") throw new Error("A journal entry needs a line and date");
        const gift = giftFromJSON(entry.gift);
        return [{ line: entry.line, date: entry.date + REFERENCE_DATE_OFFSET, ...(gift ? { gift } : {}) }];
      });
    }
    const known = new Set(JOURNAL_LINES.map((line) => line.id));
    const seen = new Set<string>();
    const deck = Array.isArray(object.deck) ? object.deck : [];
    journal.deck = deck.filter((id): id is string => {
      if (typeof id !== "string" || !known.has(id) || seen.has(id)) return false;
      seen.add(id);
      return true;
    });
    if (journal.deck.length >= JOURNAL_LINES.length) journal.deck = [];
    journal.decksFinished =
      typeof object.decksFinished === "number" ? Math.max(0, Math.trunc(object.decksFinished)) : 0;
    return journal;
  }
}
