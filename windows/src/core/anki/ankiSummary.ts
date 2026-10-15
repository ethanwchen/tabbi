import { DAY, type Instant, type Seconds } from "../time";
import type { AnkiConnectClient } from "./ankiConnectClient";
import { AnkiConnectFailure, errorMessage, failsWholeRefresh } from "./ankiConnectError";
import {
  type AnkiDayCount,
  type AnkiDeckStats,
  type AnkiReview,
  AnkiReviewKind,
  dueTotal as deckDue,
  isFailure,
  reviewedAt,
} from "./ankiConnectModels";
import {
  type AnkiDay,
  addingDays,
  ankiDayAt,
  ankiDayText,
  instantFromZoned,
  sameAnkiDay,
} from "./ankiDay";
import { DECK_SEPARATOR, deckLeaf, deckNameComponents } from "./ankiDeckName";
import { type AnkiFavoriteDeck, resolveFavorite } from "./ankiFavoriteDeck";

/** A part of the summary that comes from an optional action, so it can be missing while due counts show. */
export type AnkiSummaryPiece =
  /** Today's review count (`getNumCardsReviewedToday` and `getNumCardsReviewedByDay` both failed). */
  | "todayCount"
  /** The per-day history and the streak (`getNumCardsReviewedByDay`). */
  | "history"
  /** Retention and today's study time (`cardReviews`). */
  | "reviewLog";

/** An optional action that failed, and what Anki said. */
export interface AnkiSummaryGap {
  action: string;
  message: string;
}

/**
 * Port of AnkiSummary: everything the Anki card shows, aggregated from a
 * handful of AnkiConnect replies by the pure `buildAnkiSummary`, so the math
 * is testable without a transport; `fetchAnkiSummary` fetches it.
 */
export interface AnkiSummary {
  /** Due today, summed over top-level decks only (Anki rolls children up). */
  readonly newDue: number;
  readonly learnDue: number;
  readonly reviewDue: number;
  /** Reviews (button presses) since today's rollover. */
  readonly reviewedToday: number;
  /** Consecutive days with a review, ending today, or yesterday while today has none yet. */
  readonly streak: number;
  /** One entry per day, oldest first, ending today, zero-filled. */
  readonly history: readonly AnkiDayCount[];
  /** Share of review-card answers that were not Again; undefined with too few reviews to say. */
  readonly retention: number | undefined;
  /** How many review answers `retention` is based on. */
  readonly retentionSampleSize: number;
  /** Seconds spent answering today's reviews in the fetched decks. */
  readonly studyTimeToday: Seconds;
  /** Per-deck counts, in the order given. */
  readonly decks: readonly AnkiDeckStats[];
  /**
   * The parts AnkiConnect couldn't send this time. Their numbers above are
   * placeholders and must not be shown, logged or celebrated as real.
   */
  readonly missing: ReadonlySet<AnkiSummaryPiece>;
  /** Why each optional action failed, for logs and the panel's tooltip. */
  readonly gaps: readonly AnkiSummaryGap[];
}

/** Days of history kept for the sparkline. */
export const DEFAULT_HISTORY_DAYS = 14;
/** Window for the retention estimate. */
export const DEFAULT_RETENTION_WINDOW_DAYS = 30;
/** Below this many answers a retention percentage is mostly noise. */
export const MINIMUM_RETENTION_SAMPLE = 20;

export interface AnkiSummaryInput {
  /** `getDeckStats` for any set of decks; a deck whose ancestor is present is left out of the totals. */
  deckStats: readonly AnkiDeckStats[];
  /** `getNumCardsReviewedToday`. */
  reviewedToday: number;
  /** `getNumCardsReviewedByDay`, any order. */
  reviewsByDay: readonly AnkiDayCount[];
  /** `cardReviews` rows from any decks; duplicates are ignored. */
  reviews: readonly AnkiReview[];
  now: Instant;
  /** The current Anki day, already shifted by the rollover hour. */
  today: AnkiDay;
  /** The IANA zone Anki days are counted in. */
  timeZone: string;
  rolloverHour?: number;
  historyDays?: number;
  retentionWindowDays?: number;
  missing?: Iterable<AnkiSummaryPiece>;
  gaps?: readonly AnkiSummaryGap[];
}

/** Aggregates raw AnkiConnect data. */
export function buildAnkiSummary(input: AnkiSummaryInput): AnkiSummary {
  const rolloverHour = input.rolloverHour ?? 4;
  const historyDays = input.historyDays ?? DEFAULT_HISTORY_DAYS;
  const retentionWindowDays = input.retentionWindowDays ?? DEFAULT_RETENTION_WINDOW_DAYS;
  const roots = rootDecks(input.deckStats);

  const counts = new Map<string, number>();
  const key = ankiDayText;
  for (const entry of input.reviewsByDay) counts.set(key(entry.day), (counts.get(key(entry.day)) ?? 0) + entry.count);
  /*
   * The two actions are separate queries; trust the larger number for today
   * so a review landing between them never reads as zero.
   */
  const todayKey = key(input.today);
  counts.set(todayKey, Math.max(counts.get(todayKey) ?? 0, input.reviewedToday));
  const count = (day: AnkiDay) => counts.get(key(day)) ?? 0;

  const history: AnkiDayCount[] = [];
  for (let back = Math.max(historyDays, 0) - 1; back >= 0; back--) {
    const day = addingDays(input.today, -back);
    history.push({ day, count: count(day) });
  }

  let streak = 0;
  let day = count(input.today) > 0 ? input.today : addingDays(input.today, -1);
  while (count(day) > 0) {
    streak += 1;
    day = addingDays(day, -1);
  }

  const seen = new Set<number>();
  const unique = input.reviews.filter((review) => !seen.has(review.id) && seen.add(review.id));
  const windowStart = input.now - retentionWindowDays * DAY;
  const graded = unique.filter(
    (review) =>
      review.kind === AnkiReviewKind.review &&
      review.ease > 0 &&
      reviewedAt(review) >= windowStart &&
      reviewedAt(review) <= input.now,
  );
  let retention: number | undefined;
  if (graded.length >= MINIMUM_RETENTION_SAMPLE) {
    const failures = graded.filter(isFailure).length;
    retention = 1 - failures / graded.length;
  }

  const todaysReviews = unique.filter((review) =>
    sameAnkiDay(ankiDayAt(reviewedAt(review), input.timeZone, rolloverHour), input.today),
  );
  const studyTimeToday = todaysReviews.reduce((sum, review) => sum + review.durationMilliseconds, 0) / 1000;

  return {
    newDue: roots.reduce((sum, deck) => sum + deck.newCount, 0),
    learnDue: roots.reduce((sum, deck) => sum + deck.learnCount, 0),
    reviewDue: roots.reduce((sum, deck) => sum + deck.reviewCount, 0),
    reviewedToday: count(input.today),
    streak,
    history,
    retention,
    retentionSampleSize: graded.length,
    studyTimeToday,
    decks: [...input.deckStats],
    missing: new Set(input.missing ?? []),
    gaps: [...(input.gaps ?? [])],
  };
}

export function summaryDueTotal(summary: AnkiSummary): number {
  return summary.newDue + summary.learnDue + summary.reviewDue;
}

/** Whether at least one card has been answered today. */
export function hasReviewedToday(summary: AnkiSummary): boolean {
  return summary.reviewedToday > 0;
}

/**
 * Decks with no ancestor in the list. `getDeckStats` already includes
 * children in a parent's counts, so summing both would double count.
 */
export function rootDecks(stats: readonly AnkiDeckStats[]): AnkiDeckStats[] {
  const names = new Set(stats.map((deck) => deck.name));
  const seen = new Set<number>();
  return stats.filter((deck) => {
    if (seen.has(deck.deckID)) return false;
    seen.add(deck.deckID);
    const parts = deck.name.split(DECK_SEPARATOR);
    for (let length = 1; length < Math.max(parts.length, 1); length++) {
      if (names.has(parts.slice(0, length).join(DECK_SEPARATOR))) return false;
    }
    return true;
  });
}

/** The Anki day this summary describes (the last history entry). */
export function summaryDay(summary: AnkiSummary): AnkiDay | undefined {
  return summary.history.at(-1)?.day;
}

/** Whether this summary still describes today; due counts reset at Anki's rollover. */
export function isSummaryCurrent(summary: AnkiSummary, now: Instant, timeZone: string, rolloverHour = 4): boolean {
  return sameAnkiDay(summaryDay(summary), ankiDayAt(now, timeZone, rolloverHour));
}

/** The instant the next Anki day starts after `now`, when due counts reset. */
export function nextRollover(now: Instant, timeZone: string, rolloverHour = 4): Instant {
  const tomorrow = addingDays(ankiDayAt(now, timeZone, rolloverHour), 1);
  return instantFromZoned(tomorrow.year, tomorrow.month, tomorrow.day, rolloverHour, timeZone);
}

function byMostDue(a: AnkiDeckStats, b: AnkiDeckStats): number {
  const difference = deckDue(b) - deckDue(a);
  if (difference !== 0) return difference;
  return a.name < b.name ? -1 : a.name > b.name ? 1 : 0;
}

/**
 * Top-level decks with cards due, most due first, ties by name. Anki rolls
 * children into parents, so listing only roots never double counts.
 */
export function topDecks(summary: AnkiSummary): AnkiDeckStats[] {
  return rootDecks(summary.decks)
    .filter((deck) => deckDue(deck) > 0)
    .sort(byMostDue);
}

/**
 * One line of `deckOutline`: a deck, how deep it sits under the listed
 * decks, and its name relative to the row above it ("Cells" under
 * "Biology"). Opening it still uses `deck.name`, the full path.
 */
export interface AnkiDeckOutlineRow {
  deck: AnkiDeckStats;
  depth: number;
  title: string;
}

/**
 * Every deck with cards due, as an outline: each of `topDecks` followed by
 * its subdecks with cards due, most due first at every level. A subdeck
 * hangs under its nearest listed ancestor, so a missing middle deck never
 * hides its children.
 */
export function deckOutline(summary: AnkiSummary): AnkiDeckOutlineRow[] {
  const seen = new Set<number>();
  const due = summary.decks.filter((deck) => {
    if (deckDue(deck) <= 0 || seen.has(deck.deckID)) return false;
    seen.add(deck.deckID);
    return true;
  });
  const pathKey = (parts: readonly string[]) => JSON.stringify(parts);
  const byName = new Map<string, AnkiDeckStats>();
  for (const deck of due) {
    const keyed = pathKey(deckNameComponents(deck.name));
    if (!byName.has(keyed)) byName.set(keyed, deck);
  }
  const children = new Map<string, AnkiDeckStats[]>();
  for (const deck of due) {
    const parts = deckNameComponents(deck.name);
    for (let length = Math.max(parts.length, 1) - 1; length >= 1; length--) {
      const parent = pathKey(parts.slice(0, length));
      if (byName.has(parent)) {
        children.set(parent, [...(children.get(parent) ?? []), deck]);
        break;
      }
    }
  }
  const rows: AnkiDeckOutlineRow[] = [];
  const visit = (deck: AnkiDeckStats, parent: readonly string[], depth: number) => {
    const parts = deckNameComponents(deck.name);
    const title = parts.slice(parent.length).join(DECK_SEPARATOR);
    rows.push({ deck, depth, title: title.length === 0 ? deck.name : title });
    for (const child of [...(children.get(pathKey(parts)) ?? [])].sort(byMostDue)) visit(child, parts, depth + 1);
  };
  for (const root of topDecks(summary)) visit(root, [], 0);
  return rows;
}

/** Share of today's work done: reviewed out of reviewed plus still due; 1 when nothing was due. */
export function completionFraction(summary: AnkiSummary): number {
  const target = summary.reviewedToday + summaryDueTotal(summary);
  return target > 0 ? summary.reviewedToday / target : 1;
}

/**
 * This summary with its missing pieces filled in from `previous`, when that
 * one is from the same Anki day and has them, so one failed optional action
 * doesn't blank the streak or retention showing a minute ago.
 */
export function fillingSummary(summary: AnkiSummary, previous: AnkiSummary | undefined): AnkiSummary {
  if (!previous || summary.missing.size === 0 || !sameAnkiDay(summaryDay(previous), summaryDay(summary))) return summary;
  const missing = new Set(summary.missing);
  let filled: AnkiSummary = summary;
  if (missing.has("todayCount") && !previous.missing.has("todayCount")) {
    filled = { ...filled, reviewedToday: previous.reviewedToday };
    missing.delete("todayCount");
  }
  if (missing.has("history") && !previous.missing.has("history")) {
    /* The newer count for today wins; the days before can't change. */
    const today = Math.max(filled.reviewedToday, previous.reviewedToday);
    const history = [...previous.history];
    const last = history.at(-1);
    if (last) history[history.length - 1] = { day: last.day, count: today };
    const startsToday = previous.reviewedToday === 0 && today > 0;
    filled = { ...filled, history, reviewedToday: today, streak: previous.streak + (startsToday ? 1 : 0) };
    missing.delete("history");
  }
  if (missing.has("reviewLog") && !previous.missing.has("reviewLog")) {
    filled = {
      ...filled,
      retention: previous.retention,
      retentionSampleSize: previous.retentionSampleSize,
      studyTimeToday: previous.studyTimeToday,
    };
    missing.delete("reviewLog");
  }
  return { ...filled, missing };
}

/**
 * The full name of the deck a one-click Study opens: the pinned favorite (by
 * id, else by its stored name), otherwise the deck with the most due.
 * Undefined when there is neither, and Anki opens on its deck list.
 */
export function studyDeck(summary: AnkiSummary, favorite: AnkiFavoriteDeck | undefined): string | undefined {
  if (favorite) return resolveFavorite(favorite, summary.decks)?.name ?? favorite.name;
  return topDecks(summary)[0]?.name;
}

/** The `id` of the study action Today and the ticker run on click. */
export const ANKI_STUDY_ACTION_ID = "anki.study";

/** The study action's title: "Study <deck>", or "Open Anki" with no deck. */
export function studyActionTitle(summary: AnkiSummary, favorite: AnkiFavoriteDeck | undefined): string {
  const deck = studyDeck(summary, favorite);
  return deck === undefined ? "Open Anki" : `Study ${deckLeaf(deck)}`;
}

/** Metadata key holding the Anki day a `cardsReviewed` activity record counts toward. */
export const ANKI_ACTIVITY_DAY_KEY = "ankiDay";

/**
 * How many cards answered today the activity log doesn't hold yet, given
 * the quantities already logged for this summary's Anki day, or undefined
 * when there are none. Matching on the Anki day keeps reviews done after
 * midnight but before the rollover from being counted twice.
 */
export function unloggedReviews(summary: AnkiSummary, loggedForDay: readonly number[]): number | undefined {
  if (!summaryDay(summary)) return undefined;
  const already = loggedForDay.reduce((sum, quantity) => sum + quantity, 0);
  const fresh = summary.reviewedToday - already;
  return fresh >= 1 ? fresh : undefined;
}

/**
 * Realistic sample data for demo runs: four neutral decks and a 12-day
 * streak, built through the real aggregation so it stays honest.
 */
export function demoAnkiSummary(now: Instant, timeZone: string, rolloverHour = 4): AnkiSummary {
  const today = ankiDayAt(now, timeZone, rolloverHour);
  const stats: AnkiDeckStats[] = [
    { deckID: 1, name: "Spanish verbs", newCount: 8, learnCount: 3, reviewCount: 38, totalInDeck: 1200 },
    { deckID: 2, name: "Spanish verbs::Irregular", newCount: 3, learnCount: 1, reviewCount: 12, totalInDeck: 340 },
    { deckID: 3, name: "Biology", newCount: 6, learnCount: 2, reviewCount: 28, totalInDeck: 900 },
    { deckID: 4, name: "Biology::Cells", newCount: 2, learnCount: 1, reviewCount: 9, totalInDeck: 260 },
    { deckID: 5, name: "Biology::Cells::Mitosis", newCount: 0, learnCount: 1, reviewCount: 3, totalInDeck: 80 },
    { deckID: 6, name: "World history", newCount: 4, learnCount: 1, reviewCount: 20, totalInDeck: 650 },
    { deckID: 7, name: "Chemistry", newCount: 2, learnCount: 2, reviewCount: 14, totalInDeck: 480 },
    { deckID: 8, name: "Chemistry::Organic", newCount: 1, learnCount: 0, reviewCount: 6, totalInDeck: 150 },
  ];
  /* Oldest to newest; a missed day 12 days ago ends the earlier run. */
  const counts = [60, 0, 85, 110, 70, 140, 120, 95, 150, 105, 125, 90, 135, 46];
  const byDay = counts.map((count, offset) => ({ day: addingDays(today, offset - (counts.length - 1)), count }));
  /* 46 graded reviews today, 5 of them Again: about 89% retention. */
  const nowMs = Math.trunc(now * 1000);
  const reviews: AnkiReview[] = Array.from({ length: 46 }, (_, index) => ({
    id: nowMs - index * 20_000,
    cardID: 1000 + index,
    ease: index % 11 === 0 ? 1 : 3,
    interval: 12,
    lastInterval: 5,
    factor: 2500,
    durationMilliseconds: 8000,
    kind: AnkiReviewKind.review,
  }));
  return buildAnkiSummary({
    deckStats: stats,
    reviewedToday: counts.at(-1) ?? 0,
    reviewsByDay: byDay,
    reviews,
    now,
    today,
    timeZone,
    rolloverHour,
  });
}

export interface FetchAnkiSummaryOptions {
  now: Instant;
  timeZone: string;
  rolloverHour?: number;
  historyDays?: number;
  retentionWindowDays?: number;
  signal?: AbortSignal;
}

/**
 * Fetches everything `AnkiSummary` needs: due counts for every deck, today's
 * count, the per-day history, and the review log for the retention window.
 * `cardReviews` skips child decks, so every deck is asked for, batched into
 * one `multi`. The due counts are what the panel is for; the rest only
 * decorates it, so an action Anki fails for its own reasons leaves a gap
 * instead of failing everything, while Anki closing mid-refresh still fails.
 */
export async function fetchAnkiSummary(client: AnkiConnectClient, options: FetchAnkiSummaryOptions): Promise<AnkiSummary> {
  const { now, timeZone, signal } = options;
  const rolloverHour = options.rolloverHour ?? 4;
  const retentionWindowDays = options.retentionWindowDays ?? DEFAULT_RETENTION_WINDOW_DAYS;
  const allDecks = await client.decks(signal);
  const names = allDecks.map((deck) => deck.name);
  const stats = await client.deckStats(allDecks, signal);

  const gaps: AnkiSummaryGap[] = [];
  const optionalPiece = async <T>(action: string, body: () => Promise<T>): Promise<T | undefined> => {
    try {
      return await body();
    } catch (error) {
      if (!(error instanceof AnkiConnectFailure) || failsWholeRefresh(error.error)) throw error;
      gaps.push({ action, message: errorMessage(error.error) ?? JSON.stringify(error.error) });
      return undefined;
    }
  };
  const reviewedToday = await optionalPiece("getNumCardsReviewedToday", () => client.numCardsReviewedToday(signal));
  const byDay = await optionalPiece("getNumCardsReviewedByDay", () => client.numCardsReviewedByDay(signal));
  const startID = Math.trunc((now - retentionWindowDays * DAY) * 1000);
  const reviews = await optionalPiece("cardReviews", () => client.cardReviewsForDecks(names, startID, signal));

  const missing: AnkiSummaryPiece[] = [];
  if (byDay === undefined) missing.push("history");
  if (byDay === undefined && reviewedToday === undefined) missing.push("todayCount");
  if (reviews === undefined) missing.push("reviewLog");

  return buildAnkiSummary({
    deckStats: stats,
    reviewedToday: reviewedToday ?? 0,
    reviewsByDay: byDay ?? [],
    reviews: reviews ?? [],
    now,
    today: ankiDayAt(now, timeZone, rolloverHour),
    timeZone,
    rolloverHour,
    historyDays: options.historyDays,
    retentionWindowDays,
    missing,
    gaps,
  });
}
