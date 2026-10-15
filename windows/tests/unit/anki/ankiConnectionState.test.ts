import { describe, expect, it } from "vitest";
import { AnkiErrors } from "../../../src/core/anki/ankiConnectError";
import {
  ANKI_STARTUP_GRACE,
  type AnkiConnectionState,
  ankiConnectionStateFromPreviewName,
  AnkiRecovery,
  isSetupStep,
  keepsLastSummary,
  pollsWhileHidden,
  refreshInterval,
  resolveAnkiConnectionState,
} from "../../../src/core/anki/ankiConnectionState";
import { ankiDayAt } from "../../../src/core/anki/ankiDay";
import {
  buildAnkiSummary,
  completionFraction,
  deckOutline,
  isSummaryCurrent,
  nextRollover,
  topDecks,
} from "../../../src/core/anki/ankiSummary";
import type { AnkiDeckStats } from "../../../src/core/anki/ankiConnectModels";

/* Port of AnkiConnectionStateTests. */

const now = 1_790_866_800;

function resolve(error: Parameters<typeof resolveAnkiConnectionState>[0], installed = true, launchedSecondsAgo?: number) {
  return resolveAnkiConnectionState(error, installed, launchedSecondsAgo === undefined ? undefined : now - launchedSecondsAgo, now);
}

const state = (kind: "checking" | "notInstalled" | "notRunning" | "starting" | "addOnMissing" | "addOnOutdated" | "ready") =>
  ({ kind }) as AnkiConnectionState;

describe("AnkiConnectionState", () => {
  it("is ready on success", () => {
    expect(resolve(undefined)).toEqual({ kind: "ready" });
    expect(resolve(undefined, false)).toEqual({ kind: "ready" });
  });

  it("reads a refused connection without a process by whether Anki is installed", () => {
    expect(resolve(AnkiErrors.ankiNotRunning)).toEqual({ kind: "notRunning" });
    expect(resolve(AnkiErrors.ankiNotRunning, false)).toEqual({ kind: "notInstalled" });
  });

  it("is starting right after launch, then add-on missing", () => {
    expect(resolve(AnkiErrors.addOnMissing, true, 3)).toEqual({ kind: "starting" });
    expect(resolve(AnkiErrors.addOnMissing, true, ANKI_STARTUP_GRACE + 1)).toEqual({ kind: "addOnMissing" });
    expect(resolve(AnkiErrors.addOnMissing)).toEqual({ kind: "addOnMissing" });
  });

  it("makes permission and version errors setup steps", () => {
    expect(resolve(AnkiErrors.permissionDenied)).toEqual({ kind: "needsPermission", error: AnkiErrors.permissionDenied });
    expect(resolve(AnkiErrors.apiKeyRequired)).toEqual({ kind: "needsPermission", error: AnkiErrors.apiKeyRequired });
    expect(resolve(AnkiErrors.addOnOutdated(5))).toEqual({ kind: "addOnOutdated" });
    expect(resolve(AnkiErrors.unsupportedAction("multi"))).toEqual({ kind: "addOnOutdated" });
    for (const value of [resolve(AnkiErrors.permissionDenied), resolve(AnkiErrors.addOnOutdated(5)), resolve(AnkiErrors.ankiNotRunning)]) {
      expect(isSetupStep(value)).toBe(true);
      expect(keepsLastSummary(value)).toBe(false);
    }
  });

  it("keeps the last summary through transient errors", () => {
    for (const error of [AnkiErrors.timeout, AnkiErrors.collectionUnavailable, AnkiErrors.transport("x"), AnkiErrors.invalidResponse("x")]) {
      const value = resolve(error);
      expect(value).toEqual({ kind: "problem", error });
      expect(isSetupStep(value)).toBe(false);
      expect(keepsLastSummary(value)).toBe(true);
    }
  });

  it("polls setup steps faster than ready", () => {
    expect(refreshInterval(state("starting"))).toBeLessThan(refreshInterval(state("notRunning")));
    expect(refreshInterval(state("addOnMissing"))).toBeLessThan(refreshInterval(state("ready")));
    expect(refreshInterval(state("ready"))).toBeGreaterThanOrEqual(120);
  });

  it("retries problems fast at first, then backs off", () => {
    const problem: AnkiConnectionState = { kind: "problem", error: AnkiErrors.collectionUnavailable };
    expect(refreshInterval(problem, 0)).toBe(4);
    expect(refreshInterval(problem, 59)).toBe(4);
    expect(refreshInterval(problem, 60)).toBe(15);
    expect(refreshInterval(problem, 299)).toBe(15);
    expect(refreshInterval(problem, 300)).toBe(60);
    expect(refreshInterval(problem, 86_400)).toBe(60);
    for (let age = 0; age <= 3600; age += 7) {
      const interval = refreshInterval(problem, age);
      expect(interval).toBeGreaterThanOrEqual(4);
      expect(interval).toBeLessThanOrEqual(60);
    }
    expect(AnkiRecovery.fastInterval).toBe(4);
    expect(AnkiRecovery.idleInterval).toBe(60);
  });

  it("polls while hidden only while starting and for a fresh problem", () => {
    expect(pollsWhileHidden(state("starting"))).toBe(true);
    expect(pollsWhileHidden({ kind: "problem", error: AnkiErrors.timeout }, 0)).toBe(true);
    expect(pollsWhileHidden({ kind: "problem", error: AnkiErrors.collectionUnavailable }, 59)).toBe(true);
    expect(pollsWhileHidden({ kind: "problem", error: AnkiErrors.timeout }, 60)).toBe(false);
    expect(AnkiRecovery.fastWindow / AnkiRecovery.fastInterval).toBeLessThanOrEqual(15);
    const others: AnkiConnectionState[] = [
      state("checking"),
      state("notInstalled"),
      state("notRunning"),
      state("addOnMissing"),
      { kind: "needsPermission", error: AnkiErrors.permissionDenied },
      state("addOnOutdated"),
      state("ready"),
    ];
    for (const value of others) {
      expect(pollsWhileHidden(value)).toBe(false);
      expect(pollsWhileHidden(value, 0)).toBe(false);
    }
    const launched = 1000;
    const afterGrace = launched + ANKI_STARTUP_GRACE + 1;
    expect(pollsWhileHidden(resolveAnkiConnectionState(AnkiErrors.addOnMissing, true, launched, afterGrace))).toBe(false);
  });

  it("parses preview state names", () => {
    expect(ankiConnectionStateFromPreviewName("addOnMissing")).toEqual({ kind: "addOnMissing" });
    expect(ankiConnectionStateFromPreviewName("notrunning")).toEqual({ kind: "notRunning" });
    expect(ankiConnectionStateFromPreviewName("apikey")).toEqual({ kind: "needsPermission", error: AnkiErrors.apiKeyRequired });
    expect(ankiConnectionStateFromPreviewName("permission")).toEqual({ kind: "needsPermission", error: AnkiErrors.permissionDenied });
    expect(ankiConnectionStateFromPreviewName("problem")).toEqual({ kind: "problem", error: AnkiErrors.timeout });
    expect(ankiConnectionStateFromPreviewName("bogus")).toBeUndefined();
  });
});

describe("AnkiSummary helpers", () => {
  const today = ankiDayAt(now, "UTC");
  const summary = (stats: AnkiDeckStats[], reviewed = 0) =>
    buildAnkiSummary({ deckStats: stats, reviewedToday: reviewed, reviewsByDay: [], reviews: [], now, today, timeZone: "UTC" });
  const deck = (id: number, name: string, due: number): AnkiDeckStats => ({
    deckID: id,
    name,
    newCount: 0,
    learnCount: 0,
    reviewCount: due,
    totalInDeck: 100,
  });

  it("lists root decks with cards due, most due first", () => {
    const value = summary([deck(1, "AnKing", 40), deck(2, "AnKing::Cardio", 30), deck(3, "Pharm", 90), deck(4, "Micro", 40), deck(5, "Default", 0)]);
    expect(topDecks(value).map((d) => d.name)).toEqual(["Pharm", "AnKing", "Micro"]);
  });

  it("nests subdecks under their parent by most due", () => {
    const value = summary([
      deck(1, "AnKing", 40),
      deck(2, "AnKing::Cardio", 10),
      deck(3, "AnKing::Renal", 30),
      deck(4, "AnKing::Renal::Acid Base", 12),
      deck(5, "Pharm", 90),
      deck(6, "Pharm::Empty", 0),
    ]);
    const outline = deckOutline(value);
    expect(outline.map((row) => row.deck.name)).toEqual(["Pharm", "AnKing", "AnKing::Renal", "AnKing::Renal::Acid Base", "AnKing::Cardio"]);
    expect(outline.map((row) => row.depth)).toEqual([0, 0, 1, 2, 1]);
    expect(outline.map((row) => row.title)).toEqual(["Pharm", "AnKing", "Renal", "Acid Base", "Cardio"]);
  });

  it("hangs a subdeck under its nearest listed ancestor", () => {
    const outline = deckOutline(summary([deck(1, "Step1", 20), deck(2, "Step1::Cardio::Arrhythmias", 5)]));
    expect(outline.map((row) => row.title)).toEqual(["Step1", "Cardio::Arrhythmias"]);
    expect(outline.at(-1)?.deck.name).toBe("Step1::Cardio::Arrhythmias");
    expect(outline.at(-1)?.depth).toBe(1);
  });

  it("has an empty outline when nothing is due", () => {
    expect(deckOutline(summary([deck(1, "A", 0), deck(2, "A::B", 0)]))).toEqual([]);
  });

  it("computes the completion fraction", () => {
    expect(completionFraction(summary([deck(1, "A", 30)], 90))).toBeCloseTo(0.75, 4);
    expect(completionFraction(summary([], 0))).toBe(1);
  });

  it("stays current until the rollover", () => {
    const value = summary([]);
    expect(isSummaryCurrent(value, now, "UTC")).toBe(true);
    /* 2026-10-02 03:00 UTC is still Oct 1 in Anki (rollover at 4). */
    const beforeRollover = 1_790_910_000;
    expect(isSummaryCurrent(value, beforeRollover, "UTC")).toBe(true);
    expect(isSummaryCurrent(value, beforeRollover + 2 * 3600, "UTC")).toBe(false);
  });

  it("finds the start of the next Anki day", () => {
    const beforeRollover = 1_790_910_000;
    const sameMorning = nextRollover(beforeRollover, "UTC");
    expect(sameMorning - beforeRollover).toBe(3600);
    expect(nextRollover(sameMorning, "UTC") - sameMorning).toBe(86_400);
    const value = summary([]);
    expect(isSummaryCurrent(value, nextRollover(now, "UTC"), "UTC")).toBe(false);
    expect(isSummaryCurrent(value, nextRollover(now, "UTC") - 1, "UTC")).toBe(true);
  });

  it("finds the rollover in a zone with daylight saving", () => {
    /* 2026-11-01 is the day New York falls back; the next rollover is 04:00 local, 09:00 UTC. */
    const evening = Date.UTC(2026, 10, 1, 1, 0) / 1000;
    expect(new Date(nextRollover(evening, "America/New_York") * 1000).toISOString()).toBe("2026-11-01T09:00:00.000Z");
  });
});
