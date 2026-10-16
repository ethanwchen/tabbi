import { describe, expect, it } from "vitest";
import { AnkiConnectClient } from "../../../src/core/anki/ankiConnectClient";
import {
  type AnkiConnectError,
  AnkiConnectFailure,
  AnkiErrors,
  ANKI_CONNECT_ADD_ON_CODE,
  addOnReminder,
  errorFromAnkiMessage,
  errorMessage,
  errorSuggestion,
  errorTitle,
  isMalformedRequest,
  isUnexplained,
  MESSAGE_LIMIT,
  characters,
  quotedMessage,
  shortMessage,
} from "../../../src/core/anki/ankiConnectError";
import { ankiDayAt, addingDays } from "../../../src/core/anki/ankiDay";
import {
  buildAnkiSummary,
  fetchAnkiSummary,
  fillingSummary,
  summaryDueTotal,
} from "../../../src/core/anki/ankiSummary";
import { actionOf, decksIn, innerActions, recorded, ScriptedAnkiTransport, statsJSON } from "./fakeAnki";

/* Port of AnkiRobustnessTests: AnkiConnect's real strings and the getDeckStats fallback. */

async function caught(promise: Promise<unknown>): Promise<AnkiConnectError> {
  try {
    await promise;
  } catch (error) {
    if (error instanceof AnkiConnectFailure) return error.error;
    throw error;
  }
  throw new Error("Expected an AnkiConnect error");
}

describe("classification from AnkiConnect's real strings", () => {
  it("reads every version's closed-collection message as collection unavailable", () => {
    const closed = [
      "collection is not available" /* 2023 to 2025 add-on: no profile open */,
      "database is not available" /* full sync in progress */,
      "CollectionNotOpen" /* Anki's backend */,
      "Collection is not available." /* 2026.10 rewrite: no profile open */,
      "A collection operation is active." /* 2026.10 rewrite: sync or Check Database running */,
      "Collection session changed." /* 2026.10 rewrite: profile reopened mid-request */,
    ];
    for (const message of closed) {
      expect(errorFromAnkiMessage(message, "deckNamesAndIds"), message).toEqual(AnkiErrors.collectionUnavailable);
    }
  });

  it("does not read unrelated errors that mention a collection as the profile picker", () => {
    const unrelated = [
      "'NoneType' object has no attribute 'all'; collection is none of these",
      "collection is not open to new decks",
      "Deck counts unavailable.",
      "model was not found: Basic",
    ];
    for (const message of unrelated) expect(errorFromAnkiMessage(message, "x"), message).toEqual(AnkiErrors.anki(message));
    expect(errorFromAnkiMessage("valid api key must be provided", "x")).toEqual(AnkiErrors.apiKeyRequired);
    expect(errorFromAnkiMessage("unsupported action", "cardReviews")).toEqual(AnkiErrors.unsupportedAction("cardReviews"));
    expect(errorFromAnkiMessage("sync: auth not configured", "sync")).toEqual(AnkiErrors.syncNotConfigured);
  });

  it("shortens messages to one line", () => {
    expect(shortMessage("  database \n is\tlocked  ")).toBe("database is locked");
    const short = shortMessage("word ".repeat(60));
    expect(characters(short).length).toBeLessThanOrEqual(MESSAGE_LIMIT);
    expect(short.endsWith("…")).toBe(true);
    expect(errorMessage(AnkiErrors.anki("x"))).toBe("x");
    expect(errorMessage(AnkiErrors.timeout)).toBeUndefined();
  });
});

describe("what the user reads", () => {
  it("quotes Anki and reminds about the add-on for unexplained errors", () => {
    const error = AnkiErrors.anki("Deck counts unavailable.");
    expect(isUnexplained(error)).toBe(true);
    expect(quotedMessage(error)).toBe("Anki said: “Deck counts unavailable.”");
    expect(errorSuggestion(error)).toContain("Deck counts unavailable.");
    expect(errorSuggestion(error)).toContain(ANKI_CONNECT_ADD_ON_CODE);
    expect(addOnReminder()).toContain("AnkiConnect");
    expect(errorSuggestion(error)).not.toContain("Try again in a moment");
    for (const known of [
      AnkiErrors.permissionDenied,
      AnkiErrors.apiKeyRequired,
      AnkiErrors.addOnOutdated(5),
      AnkiErrors.ankiNotRunning,
      AnkiErrors.timeout,
    ]) {
      expect(isUnexplained(known)).toBe(false);
      expect(quotedMessage(known)).toBeUndefined();
      expect(errorSuggestion(known)).not.toContain("Make sure the AnkiConnect");
    }
    expect(quotedMessage(AnkiErrors.invalidResponse("getNumCardsReviewedByDay: Bad day"))).toBe(
      "Details: getNumCardsReviewedByDay: Bad day",
    );
  });

  it("says Anki may be busy while the collection is closed", () => {
    const error = AnkiErrors.collectionUnavailable;
    expect(errorTitle(error)).toBe("Waiting for Anki");
    expect(errorSuggestion(error)).toContain("syncing");
    expect(errorSuggestion(error)).toContain("reconnects");
  });
});

describe("deck counts across AnkiConnect versions", () => {
  it("asks again without the hidden Default deck after Deck counts unavailable", async () => {
    const fake = new ScriptedAnkiTransport((request) =>
      (decksIn(request) as string[]).includes("Default")
        ? recorded.deckCountsUnavailable
        : `{"result":{${statsJSON(5, "Biology", 3)}},"error":null}`,
    );
    const client = new AnkiConnectClient({ transport: fake.transport });
    const stats = await client.deckStats([
      { id: 1, name: "Default" },
      { id: 5, name: "Biology" },
    ]);
    expect(stats.map((s) => s.name)).toEqual(["Biology"]);
    expect(stats[0]?.newCount).toBe(3);
    expect(fake.requests.map(decksIn)).toEqual([["Default", "Biology"], ["Biology"]]);
  });

  it("falls back to one deck at a time in one multi, keeping every deck that answers", async () => {
    const fake = new ScriptedAnkiTransport((request) => {
      if (actionOf(request) === "multi") {
        return (
          `{"result":[{"result":{${statsJSON(5, "Biology", 3)}},"error":null},` +
          `{"result":null,"error":"Deck counts unavailable."}` +
          `,{"result":{${statsJSON(7, "Chemistry", 2)}},"error":null}],"error":null}`
        );
      }
      return recorded.deckCountsUnavailable;
    });
    const client = new AnkiConnectClient({ transport: fake.transport, apiKey: "secret" });
    const stats = await client.deckStats([
      { id: 5, name: "Biology" },
      { id: 6, name: "Broken" },
      { id: 7, name: "Chemistry" },
    ]);
    expect(stats.map((s) => s.name)).toEqual(["Biology", "Chemistry"]);
    /* Without Default in the list there is no second batch: straight to deck by deck. */
    expect(fake.requests.map(actionOf)).toEqual(["getDeckStats", "multi"]);
    const inner = innerActions(fake.requests.at(-1));
    expect(inner.map((action) => action.action)).toEqual(["getDeckStats", "getDeckStats", "getDeckStats"]);
    expect(inner.map(decksIn)).toEqual([["Biology"], ["Broken"], ["Chemistry"]]);
    expect(inner.every((action) => action.version === 6)).toBe(true);
    /* AnkiConnect checks the key of each inner action. */
    expect(inner.map((action) => action.key)).toEqual(["secret", "secret", "secret"]);
  });

  it("walks all three steps when Default is in the list and another deck also fails", async () => {
    const fake = new ScriptedAnkiTransport((request) => {
      if (actionOf(request) === "multi") {
        return (
          `{"result":[{"result":null,"error":"Deck counts unavailable."},` +
          `{"result":{${statsJSON(5, "Biology", 3)}},"error":null},` +
          `{"result":null,"error":"Deck counts unavailable."}],"error":null}`
        );
      }
      return recorded.deckCountsUnavailable;
    });
    const client = new AnkiConnectClient({ transport: fake.transport });
    const stats = await client.deckStats([
      { id: 1, name: "Default" },
      { id: 5, name: "Biology" },
      { id: 6, name: "Broken" },
    ]);
    expect(stats.map((s) => s.deckID)).toEqual([5]);
    expect(fake.requests.map(actionOf)).toEqual(["getDeckStats", "getDeckStats", "multi"]);
    expect(fake.requests.slice(0, 2).map(decksIn)).toEqual([["Default", "Biology", "Broken"], ["Biology", "Broken"]]);
    expect(innerActions(fake.requests[2]).map(decksIn)).toEqual([["Default"], ["Biology"], ["Broken"]]);
  });

  it("matches deck-by-deck replies by id even when the add-on sends leaf names", async () => {
    const fake = new ScriptedAnkiTransport((request) => {
      if (actionOf(request) === "multi") {
        return (
          `{"result":[{"result":{${statsJSON(21, "Cardio", 4)}},"error":null},` +
          `{"result":{${statsJSON(20, "Step1", 9)}},"error":null}],"error":null}`
        );
      }
      return recorded.deckCountsUnavailable;
    });
    const client = new AnkiConnectClient({ transport: fake.transport });
    const stats = await client.deckStats([
      { id: 20, name: "Step1" },
      { id: 21, name: "Step1::Cardio" },
    ]);
    expect(stats.map((s) => [s.deckID, s.name, s.newCount])).toEqual([
      [20, "Step1", 9],
      [21, "Step1::Cardio", 4],
    ]);
  });

  it("fails only when every deck fails, with the first deck's error", async () => {
    const fake = new ScriptedAnkiTransport((request) =>
      actionOf(request) === "multi"
        ? `{"result":[{"result":null,"error":"Deck counts unavailable."},{"result":null,"error":"other"}],"error":null}`
        : recorded.deckCountsUnavailable,
    );
    const errors: string[] = [];
    const client = new AnkiConnectClient({ transport: fake.transport, onError: (action) => errors.push(action) });
    const error = await caught(
      client.deckStats([
        { id: 5, name: "Biology" },
        { id: 6, name: "Broken" },
      ]),
    );
    expect(error).toEqual(AnkiErrors.anki("Deck counts unavailable."));
    expect(errors.at(-1)).toBe("getDeckStats");
  });

  it("still fails at once when Anki is closed", async () => {
    const fake = new ScriptedAnkiTransport(() => recorded.collectionNotAvailable);
    const client = new AnkiConnectClient({ transport: fake.transport });
    expect(await caught(client.deckStats([{ id: 5, name: "Biology" }]))).toEqual(AnkiErrors.collectionUnavailable);
    expect(fake.requests).toHaveLength(1);
  });

  it("never retries a connection failure", async () => {
    let calls = 0;
    const client = new AnkiConnectClient({
      transport: async () => {
        calls += 1;
        throw { kind: "connectionRefused" };
      },
    });
    expect(
      await caught(
        client.deckStats([
          { id: 1, name: "Default" },
          { id: 5, name: "Biology" },
        ]),
      ),
    ).toEqual(AnkiErrors.ankiNotRunning);
    expect(calls).toBe(1);
  });
});

describe("a damaged request body", () => {
  it("is sent once more", async () => {
    let count = 0;
    const fake = new ScriptedAnkiTransport(() =>
      count++ === 0 ? `{"result":null,"error":"Expecting value: line 1 column 1 (char 0)"}` : `{"result":6,"error":null}`,
    );
    const client = new AnkiConnectClient({ transport: fake.transport });
    expect(await client.version()).toBe(6);
    expect(fake.requests).toHaveLength(2);
    expect(isMalformedRequest(AnkiErrors.anki("Expecting property name enclosed in double quotes: line 1 column 2 (char 1)"))).toBe(
      true,
    );
    expect(isMalformedRequest(AnkiErrors.anki("Deck counts unavailable."))).toBe(false);
  });
});

describe("a summary with a piece missing", () => {
  const now = 1_790_000_000;
  const emptyReviews = `{"result":[{"result":[],"error":null}],"error":null}`;

  function summaryTransport(byDay: string, reviews = emptyReviews) {
    return new ScriptedAnkiTransport((request) => {
      switch (actionOf(request)) {
        case "deckNamesAndIds":
          return `{"result":{"Biology":5},"error":null}`;
        case "getDeckStats":
          return `{"result":{${statsJSON(5, "Biology", 12)}},"error":null}`;
        case "getNumCardsReviewedToday":
          return `{"result":7,"error":null}`;
        case "getNumCardsReviewedByDay":
          return byDay;
        case "multi":
          return reviews;
        default:
          return recorded.unsupportedAction;
      }
    });
  }

  it("still shows the due counts when the history fails", async () => {
    const actions: string[] = [];
    const fake = summaryTransport(`{"result":null,"error":"no such column: day"}`);
    const client = new AnkiConnectClient({ transport: fake.transport, onError: (action) => actions.push(action) });
    const summary = await fetchAnkiSummary(client, { now, timeZone: "UTC" });
    expect(summaryDueTotal(summary)).toBe(12);
    expect(summary.reviewedToday).toBe(7);
    expect([...summary.missing]).toEqual(["history"]);
    expect(summary.gaps).toEqual([{ action: "getNumCardsReviewedByDay", message: "no such column: day" }]);
    expect(actions).toEqual(["getNumCardsReviewedByDay"]);
  });

  it("only loses retention when the review log is unreadable", async () => {
    const fake = summaryTransport(`{"result":[["2026-09-21",7]],"error":null}`, `{"result":[{"result":[["x"]],"error":null}],"error":null}`);
    const summary = await fetchAnkiSummary(new AnkiConnectClient({ transport: fake.transport }), { now, timeZone: "UTC" });
    expect([...summary.missing]).toEqual(["reviewLog"]);
    expect(summaryDueTotal(summary)).toBe(12);
    expect(summary.retention).toBeUndefined();
  });

  it("still fails the refresh when the collection closes midway", async () => {
    const fake = summaryTransport(`{"result":null,"error":"database is not available"}`);
    expect(await caught(fetchAnkiSummary(new AnkiConnectClient({ transport: fake.transport }), { now, timeZone: "UTC" }))).toEqual(
      AnkiErrors.collectionUnavailable,
    );
  });

  it("fills missing pieces from the last summary of the same day", () => {
    const today = ankiDayAt(now, "UTC");
    const stats = [{ deckID: 5, name: "Biology", newCount: 12, learnCount: 0, reviewCount: 0, totalInDeck: 10 }];
    const history = [0, 1, 2, 3, 4].map((back) => ({ day: addingDays(today, -back), count: 10 }));
    const base = { deckStats: stats, reviews: [], now, today, timeZone: "UTC" };
    const previous = buildAnkiSummary({ ...base, reviewedToday: 10, reviewsByDay: history });
    expect(previous.streak).toBe(5);
    const partial = buildAnkiSummary({
      ...base,
      reviewedToday: 14,
      reviewsByDay: [],
      missing: ["history"],
      gaps: [{ action: "getNumCardsReviewedByDay", message: "x" }],
    });
    expect(partial.streak).toBe(1);
    const filled = fillingSummary(partial, previous);
    expect(filled.streak).toBe(5);
    expect(filled.reviewedToday).toBe(14);
    expect(filled.history.at(-1)?.count).toBe(14);
    expect(filled.missing.size).toBe(0);
    /* Nothing to fill from: the piece stays missing. */
    expect([...fillingSummary(partial, undefined).missing]).toEqual(["history"]);
    expect([...fillingSummary(partial, partial).missing]).toEqual(["history"]);
    /* A complete summary is left alone. */
    expect(fillingSummary(previous, partial)).toBe(previous);
  });
});
