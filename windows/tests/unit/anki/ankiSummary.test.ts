import { describe, expect, it } from "vitest";
import { AnkiConnectClient } from "../../../src/core/anki/ankiConnectClient";
import { AnkiConnectFailure, AnkiErrors } from "../../../src/core/anki/ankiConnectError";
import { type AnkiDayCount, type AnkiDeckStats, type AnkiReview, AnkiReviewKind } from "../../../src/core/anki/ankiConnectModels";
import { addingDays, ankiDay, ankiDayText } from "../../../src/core/anki/ankiDay";
import { heatLevels, ageText, dayHelp, progressHelp, streakText } from "../../../src/core/anki/ankiFormat";
import {
  favoriteMatches,
  makeFavoriteDeck,
  resolveFavorite,
  updatedFavorite,
  favoriteFromDeck,
} from "../../../src/core/anki/ankiFavoriteDeck";
import {
  ANKI_ACTIVITY_DAY_KEY,
  ANKI_STUDY_ACTION_ID,
  ankiProgressItem,
  buildAnkiSummary,
  reviewActivity,
  studyAction,
  demoAnkiSummary,
  fetchAnkiSummary,
  hasReviewedToday,
  MINIMUM_RETENTION_SAMPLE,
  studyActionTitle,
  studyDeck,
  summaryDueTotal,
  topDecks,
  unloggedReviews,
} from "../../../src/core/anki/ankiSummary";
import { makeActivityRecord } from "../../../src/core/activity/activityRecord";
import { actionOf, innerActions, params, ScriptedAnkiTransport } from "./fakeAnki";

/* Port of AnkiSummaryTests, AnkiFormatTests and AnkiFavoriteDeckTests. */

/** 2026-10-01 15:00 UTC. */
const now = 1_790_866_800;
const today = ankiDay(2026, 10, 1);

const stats = (id: number, name: string, counts: { new?: number; learn?: number; review?: number } = {}): AnkiDeckStats => ({
  deckID: id,
  name,
  newCount: counts.new ?? 0,
  learnCount: counts.learn ?? 0,
  reviewCount: counts.review ?? 0,
  totalInDeck: 100,
});

function review(id: number, secondsAgo: number, ease = 3, kind: AnkiReview["kind"] = AnkiReviewKind.review, durationMs = 5000): AnkiReview {
  return {
    id: Math.trunc((now - secondsAgo) * 1000) + (id % 1000),
    cardID: id,
    ease,
    interval: 10,
    lastInterval: 4,
    factor: 2500,
    durationMilliseconds: durationMs,
    kind,
  };
}

function summary(input: { deckStats?: AnkiDeckStats[]; reviewedToday?: number; byDay?: AnkiDayCount[]; reviews?: AnkiReview[]; historyDays?: number } = {}) {
  return buildAnkiSummary({
    deckStats: input.deckStats ?? [],
    reviewedToday: input.reviewedToday ?? 0,
    reviewsByDay: input.byDay ?? [],
    reviews: input.reviews ?? [],
    now,
    today,
    timeZone: "UTC",
    rolloverHour: 4,
    historyDays: input.historyDays ?? 14,
  });
}

const days = (newestFirst: number[]): AnkiDayCount[] => newestFirst.map((count, offset) => ({ day: addingDays(today, -offset), count }));

describe("AnkiSummary due counts", () => {
  it("sums top-level decks only", () => {
    const result = summary({
      deckStats: [
        stats(1, "Step1", { new: 20, learn: 5, review: 100 }),
        stats(2, "Step1::Cardio", { new: 8, learn: 2, review: 40 }),
        stats(3, "Step1::Cardio::Arrhythmia", { new: 1, review: 9 }),
        stats(4, "Pharm", { new: 10, learn: 1, review: 30 }),
      ],
    });
    expect([result.newDue, result.learnDue, result.reviewDue]).toEqual([30, 6, 130]);
    expect(summaryDueTotal(result)).toBe(166);
    expect(result.decks).toHaveLength(4);
  });

  it("counts a child whose parent was not fetched", () => {
    expect(summaryDueTotal(summary({ deckStats: [stats(2, "Step1::Cardio", { new: 8, review: 40 }), stats(5, "Step1::Renal", { new: 2, review: 10 })] }))).toBe(60);
  });

  it("does not treat a similarly prefixed deck as a child", () => {
    expect(summary({ deckStats: [stats(1, "Step", { review: 10 }), stats(2, "Step1", { review: 5 })] }).reviewDue).toBe(15);
  });

  it("counts a duplicate deck once", () => {
    expect(summary({ deckStats: [stats(1, "Step1", { review: 10 }), stats(1, "Step1", { review: 10 })] }).reviewDue).toBe(10);
  });

  it("handles an empty collection", () => {
    const result = summary();
    expect(summaryDueTotal(result)).toBe(0);
    expect(result.reviewedToday).toBe(0);
    expect(hasReviewedToday(result)).toBe(false);
    expect(result.streak).toBe(0);
    expect(result.retention).toBeUndefined();
    expect(result.retentionSampleSize).toBe(0);
    expect(result.studyTimeToday).toBe(0);
    expect(result.history).toHaveLength(14);
    expect(result.history.every((entry) => entry.count === 0)).toBe(true);
  });
});

describe("AnkiSummary today and history", () => {
  it("takes the larger of the two sources for today", () => {
    expect(summary({ reviewedToday: 50, byDay: days([42]) }).reviewedToday).toBe(50);
    expect(summary({ reviewedToday: 40, byDay: days([42]) }).reviewedToday).toBe(42);
    expect(hasReviewedToday(summary({ reviewedToday: 1 }))).toBe(true);
  });

  it("is oldest first, zero-filled and ends today", () => {
    const result = summary({
      reviewedToday: 12,
      byDay: [
        { day: today, count: 12 },
        { day: addingDays(today, -2), count: 30 },
        { day: addingDays(today, -20), count: 99 },
      ],
    });
    expect(result.history).toHaveLength(14);
    expect(result.history[0]?.day).toEqual(addingDays(today, -13));
    expect(result.history.at(-1)).toEqual({ day: today, count: 12 });
    expect(result.history.slice(-3).map((e) => e.count)).toEqual([30, 0, 12]);
    expect(result.history.some((e) => e.count === 99)).toBe(false);
  });

  it("crosses a month boundary", () => {
    expect(summary({ historyDays: 3 }).history.map((e) => ankiDayText(e.day))).toEqual(["2026-09-29", "2026-09-30", "2026-10-01"]);
  });

  it("ignores input order and merges repeated days", () => {
    const byDay = [
      { day: addingDays(today, -1), count: 5 },
      { day: today, count: 3 },
      { day: addingDays(today, -1), count: 2 },
    ];
    expect(summary({ byDay, historyDays: 2 }).history.map((e) => e.count)).toEqual([7, 3]);
  });
});

describe("AnkiSummary streak", () => {
  it("counts back from today", () => expect(summary({ byDay: days([10, 20, 30, 0, 40]) }).streak).toBe(3));
  it("stays alive before today's first review", () => {
    const result = summary({ byDay: days([0, 20, 30, 15]) });
    expect(result.streak).toBe(3);
    expect(hasReviewedToday(result)).toBe(false);
  });
  it("is zero after a missed day", () => expect(summary({ byDay: days([0, 0, 30, 15]) }).streak).toBe(0));
  it("is not capped by the history window", () => expect(summary({ byDay: days(Array(40).fill(5)) }).streak).toBe(40));
  it("starts with today's count alone", () => expect(summary({ reviewedToday: 3, byDay: days([0, 0]) }).streak).toBe(1));
});

describe("AnkiSummary retention", () => {
  it("is the share of mature reviews not answered Again", () => {
    const passes = Array.from({ length: 36 }, (_, i) => review(i, 3600, i % 2 === 0 ? 3 : 4));
    const lapses = [100, 101, 102, 103].map((i) => review(i, 3600, 1));
    const result = summary({ reviews: [...passes, ...lapses] });
    expect(result.retentionSampleSize).toBe(40);
    expect(result.retention).toBeCloseTo(0.9, 4);
  });

  it("ignores learning, relearning, filtered and manual rows", () => {
    const kinds = [AnkiReviewKind.learn, AnkiReviewKind.relearn, AnkiReviewKind.filtered, AnkiReviewKind.manual, AnkiReviewKind.unknown];
    const reviews = [
      ...Array.from({ length: 20 }, (_, i) => review(i, 60)),
      ...kinds.map((kind, offset) => review(500 + offset, 60, 1, kind)),
      review(900, 60, 0),
    ];
    const result = summary({ reviews });
    expect(result.retentionSampleSize).toBe(20);
    expect(result.retention).toBe(1);
  });

  it("only uses the window", () => {
    const recent = Array.from({ length: 20 }, (_, i) => review(i, 86_400));
    const old = Array.from({ length: 20 }, (_, i) => review(100 + i, 31 * 86_400, 1));
    const future = [review(200, -60, 1)];
    const result = summary({ reviews: [...recent, ...old, ...future] });
    expect(result.retentionSampleSize).toBe(20);
    expect(result.retention).toBe(1);
  });

  it("is undefined below the minimum sample", () => {
    const result = summary({ reviews: Array.from({ length: MINIMUM_RETENTION_SAMPLE - 1 }, (_, i) => review(i, 60)) });
    expect(result.retention).toBeUndefined();
    expect(result.retentionSampleSize).toBe(MINIMUM_RETENTION_SAMPLE - 1);
  });

  it("counts duplicate rows once", () => {
    const lapse = review(77, 60, 1);
    const result = summary({ reviews: [...Array.from({ length: 20 }, (_, i) => review(i, 60)), lapse, lapse, lapse] });
    expect(result.retentionSampleSize).toBe(21);
    expect(result.retention).toBeCloseTo(20 / 21, 4);
  });
});

describe("AnkiSummary study time and one-click study", () => {
  it("sums today's reviews after the rollover", () => {
    /* now is 15:00 UTC with a 04:00 rollover: 11h ago is today, 12h ago yesterday. */
    const reviews = [review(1, 60, 3, AnkiReviewKind.learn, 6000), review(2, 11 * 3600, 3, AnkiReviewKind.review, 4000), review(3, 12 * 3600, 3, AnkiReviewKind.review, 90_000)];
    expect(summary({ reviews }).studyTimeToday).toBe(10);
  });

  it("prefers the favorite by id, then by name, then the most due", () => {
    const result = summary({ deckStats: [stats(1, "Step1", { review: 100 }), stats(2, "Step1::Renal::Acid Base", { review: 9 }), stats(4, "Pharm", { review: 30 })] });
    expect(studyDeck(result, undefined)).toBe("Step1");
    expect(studyDeck(result, makeFavoriteDeck("Step1::Renal::Old Name", 2))).toBe("Step1::Renal::Acid Base");
    expect(studyDeck(result, makeFavoriteDeck("Micro::Bugs", 99))).toBe("Micro::Bugs");
    expect(studyDeck(summary(), undefined)).toBeUndefined();
  });

  it("titles the study action by the deck's leaf", () => {
    const result = summary({ deckStats: [stats(1, "Step1", { review: 100 }), stats(2, "Step1::Renal", { review: 9 })] });
    expect(studyActionTitle(result, undefined)).toBe("Study Step1");
    expect(studyActionTitle(result, makeFavoriteDeck("Step1::Renal", 2))).toBe("Study Renal");
    expect(studyActionTitle(summary(), undefined)).toBe("Open Anki");
  });

  it("shares today's reviews as a goal that carries the study action", () => {
    const result = summary({ deckStats: [stats(1, "Step1", { review: 100 }), stats(2, "Step1::Renal", { review: 9 })], reviewedToday: 20 });
    const item = ankiProgressItem(result);
    expect([item.id, item.source, item.title, item.unit]).toEqual(["reviews", "anki", "Anki reviews", "cards"]);
    expect([item.completed, item.target, item.remaining]).toEqual([20, 20 + summaryDueTotal(result), summaryDueTotal(result)]);
    expect(item.action).toEqual({ id: ANKI_STUDY_ACTION_ID, title: "Study Step1" });
    // A subdeck's title uses its leaf name.
    expect(ankiProgressItem(result, "anki", makeFavoriteDeck("Step1::Renal", 2)).action?.title).toBe("Study Renal");
    expect(studyAction(summary(), undefined).title).toBe("Open Anki");
    const demo = demoAnkiSummary(now, "UTC");
    expect(ankiProgressItem(demo).remaining).toBe(summaryDueTotal(demo));
  });

  it("logs a cards reviewed record only for cards not logged for the same Anki day", () => {
    // Port of ActivityLogTests.testAnkiLogsOnlyCardsNotLoggedForTheSameAnkiDay.
    const first = reviewActivity(summary({ reviewedToday: 30 }), [], "anki", now);
    expect([first?.kind, first?.quantity, first?.unit]).toEqual(["cards.reviewed", 30, "cards"]);
    expect(first?.metadata[ANKI_ACTIVITY_DAY_KEY]).toBe("2026-10-01");
    const logged = first === undefined ? [] : [first];
    const more = reviewActivity(summary({ reviewedToday: 45 }), logged, "anki", now + 3600);
    expect(more?.quantity).toBe(15);
    const both = more === undefined ? logged : [...logged, more];
    expect(reviewActivity(summary({ reviewedToday: 45 }), both, "anki", now + 7200)).toBeUndefined();
    // Another module's cards don't count as logged.
    const study = makeActivityRecord({
      source: "study",
      kind: "cards.reviewed",
      start: now,
      quantity: 45,
      metadata: { [ANKI_ACTIVITY_DAY_KEY]: "2026-10-01" },
    });
    expect(reviewActivity(summary({ reviewedToday: 45 }), [study], "anki", now)?.quantity).toBe(45);
  });

  it("logs only the reviews not yet logged for the Anki day", () => {
    const result = summary({ reviewedToday: 30 });
    expect(unloggedReviews(result, [])).toBe(30);
    expect(unloggedReviews(result, [10, 15])).toBe(5);
    expect(unloggedReviews(result, [30])).toBeUndefined();
  });

  it("builds a demo that looks like a studying student", () => {
    const demo = demoAnkiSummary(now, "UTC");
    expect(summaryDueTotal(demo)).toBe(128);
    expect([demo.newDue, demo.learnDue, demo.reviewDue]).toEqual([20, 8, 100]);
    expect(topDecks(demo).map((d) => d.name)).toEqual(["Spanish verbs", "Biology", "World history", "Chemistry"]);
    expect(demo.reviewedToday).toBe(46);
    expect(demo.streak).toBe(12);
    expect(demo.history).toHaveLength(14);
    expect(Math.abs((demo.retention ?? 0) - 0.9)).toBeLessThanOrEqual(0.03);
    expect(demo.studyTimeToday).toBeGreaterThan(0);
  });
});

describe("fetchAnkiSummary", () => {
  it("fetches every deck and aggregates", async () => {
    const startMs = Math.trunc((now - 3600) * 1000);
    const row = (offset: number, ease: number) => `[${startMs + offset},1,-1,${ease},10,4,2500,5000,1]`;
    const step1Rows = Array.from({ length: 15 }, (_, i) => row(i, 3)).join(",");
    const cardioRows = [100, 101, 102, 103].map((i) => row(i, 3)).join(",") + "," + row(200, 1);
    const reviewsByDeck: Record<string, string> = {
      Step1: `{"result":[${step1Rows}],"error":null}`,
      "Step1::Cardio": `{"result":[${cardioRows}],"error":null}`,
    };
    const sentActions: string[] = [];
    const fake = new ScriptedAnkiTransport((request) => {
      sentActions.push(actionOf(request));
      switch (actionOf(request)) {
        case "deckNamesAndIds":
          return `{"result":{"Step1":1,"Step1::Cardio":2},"error":null}`;
        case "getDeckStats":
          return `{"result":{"1":{"deck_id":1,"name":"Step1","new_count":20,"learn_count":3,"review_count":80,"total_in_deck":900},"2":{"deck_id":2,"name":"Cardio","new_count":5,"learn_count":1,"review_count":30,"total_in_deck":200}},"error":null}`;
        case "getNumCardsReviewedToday":
          return `{"result":20,"error":null}`;
        case "getNumCardsReviewedByDay":
          return `{"result":[["2026-10-01",20],["2026-09-30",64],["2026-09-29",12]],"error":null}`;
        case "multi": {
          const inner = innerActions(request).map((action) => {
            sentActions.push(String(action.action));
            return reviewsByDeck[String(params(action).deck)] ?? `{"result":[],"error":null}`;
          });
          return `{"result":[${inner.join(",")}],"error":null}`;
        }
        default:
          return `{"result":null,"error":"unsupported action"}`;
      }
    });
    const result = await fetchAnkiSummary(new AnkiConnectClient({ transport: fake.transport }), { now, timeZone: "UTC" });
    expect(summaryDueTotal(result)).toBe(103);
    expect(result.decks.map((d) => d.name)).toEqual(["Step1", "Step1::Cardio"]);
    expect(result.reviewedToday).toBe(20);
    expect(result.streak).toBe(3);
    expect(result.retentionSampleSize).toBe(20);
    expect(result.retention).toBeCloseTo(0.95, 4);
    expect(result.studyTimeToday).toBe(100);
    expect(sentActions).toEqual(["deckNamesAndIds", "getDeckStats", "getNumCardsReviewedToday", "getNumCardsReviewedByDay", "multi", "cardReviews", "cardReviews"]);
    const multi = fake.requests.find((r) => actionOf(r) === "multi");
    const reviewParams = innerActions(multi).map(params);
    expect(reviewParams.map((p) => p.deck).sort()).toEqual(["Step1", "Step1::Cardio"]);
    const expectedStart = Math.trunc((now - 30 * 86_400) * 1000);
    expect(reviewParams.every((p) => p.startID === expectedStart)).toBe(true);
  });

  it("propagates typed errors", async () => {
    const fake = new ScriptedAnkiTransport(() => `{"result":null,"error":"unsupported action"}`);
    const error = await fetchAnkiSummary(new AnkiConnectClient({ transport: fake.transport }), { now, timeZone: "UTC" }).catch((e: unknown) => e);
    expect(error).toBeInstanceOf(AnkiConnectFailure);
    expect((error as AnkiConnectFailure).error).toEqual(AnkiErrors.unsupportedAction("deckNamesAndIds"));
  });
});

describe("AnkiFormat", () => {
  const history = (counts: number[]): AnkiDayCount[] => counts.map((count, i) => ({ day: addingDays(today, i - counts.length + 1), count }));

  it("scales heat levels to the busiest day", () => {
    expect(heatLevels(history([0, 100, 200, 300, 400]))).toEqual([0, 1, 2, 3, 4]);
    expect(heatLevels(history([1, 1000]))).toEqual([1, 4]);
    expect(heatLevels(history([0, 0, 0]))).toEqual([0, 0, 0]);
    expect(heatLevels([])).toEqual([]);
  });

  it("labels streaks", () => {
    expect(streakText(12)).toBe("12-day streak");
    expect(streakText(1)).toBe("1-day streak");
    expect(streakText(0)).toBe("No streak yet");
  });

  it("names recent days and pluralizes", () => {
    expect(dayHelp({ day: today, count: 112 }, today)).toBe("Today · 112 reviews");
    expect(dayHelp({ day: addingDays(today, -1), count: 1 }, today)).toBe("Yesterday · 1 review");
    expect(dayHelp({ day: addingDays(today, -2), count: 0 }, today)).toBe("Tue, Sep 29 · No reviews");
  });

  it("writes the ring's tooltip", () => {
    expect(progressHelp(demoAnkiSummary(now, "UTC"))).toBe("46 of 174 cards reviewed today");
    expect(progressHelp(summary({ reviewedToday: 40 }))).toBe("All 40 cards done for today");
    expect(progressHelp(summary())).toBe("Nothing due today");
  });

  it("says how old the numbers are", () => {
    expect(ageText(now - 30, now)).toBe("just now");
    expect(ageText(now - 9 * 60, now)).toBe("9m ago");
    expect(ageText(now - 3 * 3600, now)).toBe("3h ago");
    expect(ageText(now - 2 * 86_400, now)).toBe("2d ago");
    expect(ageText(now + 60, now)).toBe("just now");
  });
});

describe("AnkiFavoriteDeck", () => {
  const deck = (id: number, name: string) => stats(id, name);

  it("is nothing for a blank name and normalizes names", () => {
    expect(makeFavoriteDeck("  ")).toBeUndefined();
    expect(makeFavoriteDeck("::")).toBeUndefined();
    expect(makeFavoriteDeck(" Step 1 :: Cardio ")?.name).toBe("Step 1::Cardio");
    expect(favoriteFromDeck(deck(2, "Step 1:: Cardio")).name).toBe("Step 1::Cardio");
  });

  it("resolves by id through a rename", () => {
    const favorite = makeFavoriteDeck("Step 1::Cardio", 2);
    if (!favorite) throw new Error("no favorite");
    const decks = [deck(1, "Step 1"), deck(2, "Step 1::Heart")];
    expect(resolveFavorite(favorite, decks)?.name).toBe("Step 1::Heart");
    expect(favoriteMatches(favorite, deck(2, "Step 1::Heart"))).toBe(true);
    expect(favoriteMatches(favorite, deck(9, "Step 1::Cardio"))).toBe(false);
    expect(updatedFavorite(favorite, decks)).toEqual({ deckID: 2, name: "Step 1::Heart" });
  });

  it("falls back to the name when the id is gone, and a name-only favorite learns its id", () => {
    const favorite = makeFavoriteDeck("Step 1::Cardio", 2);
    if (!favorite) throw new Error("no favorite");
    expect(resolveFavorite(favorite, [deck(42, "Step 1::Cardio")])?.deckID).toBe(42);
    expect(updatedFavorite(favorite, [deck(42, "Step 1::Cardio")])?.deckID).toBe(42);
    const nameOnly = makeFavoriteDeck("Pathoma");
    if (!nameOnly) throw new Error("no favorite");
    expect(favoriteMatches(nameOnly, deck(5, "Pathoma"))).toBe(true);
    expect(updatedFavorite(nameOnly, [deck(5, "Pathoma")])?.deckID).toBe(5);
  });

  it("does not confuse a subdeck with its parent, and needs no update when unchanged", () => {
    const favorite = makeFavoriteDeck("Step 1::Cardio", 2);
    if (!favorite) throw new Error("no favorite");
    expect(resolveFavorite({ name: "Step 1::Cardio" }, [deck(1, "Step 1"), deck(3, "Cardio")])).toBeUndefined();
    expect(updatedFavorite(favorite, [deck(2, "Step 1::Cardio")])).toBeUndefined();
    expect(updatedFavorite(favorite, [])).toBeUndefined();
  });
});
