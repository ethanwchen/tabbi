import { describe, expect, it } from "vitest";
import { AnkiConnectClient, ANKI_CONNECT_ENDPOINT, isAnkiProcess } from "../../../src/core/anki/ankiConnectClient";
import {
  type AnkiConnectError,
  AnkiConnectFailure,
  AnkiErrors,
  ANKI_CONNECT_ADD_ON_CODE,
  errorFromAnkiMessage,
  errorSuggestion,
  errorTitle,
} from "../../../src/core/anki/ankiConnectError";
import { AnkiReviewKind, deckDepth, deckLeafName, dueTotal, isFailure, reviewedAt } from "../../../src/core/anki/ankiConnectModels";
import {
  addingDays,
  ankiDay,
  ankiDayAt,
  ankiDayText,
  compareAnkiDays,
  instantFromZoned,
  parseAnkiDay,
} from "../../../src/core/anki/ankiDay";
import { FakeAnkiTransport, failure, json, params, recorded, type Reply } from "./fakeAnki";

/* Port of AnkiConnectClientTests, over recorded AnkiConnect replies. */

function client(replies: Record<string, Reply>, options: { apiKey?: string; ankiRunning?: boolean } = {}) {
  const fake = new FakeAnkiTransport(replies);
  const value = new AnkiConnectClient({
    transport: fake.transport,
    apiKey: options.apiKey,
    isAnkiRunning: async () => options.ankiRunning ?? false,
  });
  return { client: value, fake };
}

async function caught(promise: Promise<unknown>): Promise<AnkiConnectError> {
  try {
    await promise;
  } catch (error) {
    if (error instanceof AnkiConnectFailure) return error.error;
    throw error;
  }
  throw new Error("Expected an AnkiConnect error");
}

const granted = `{"result":{"permission":"granted","version":6},"error":null}`;
const keyed = `{"result":{"permission":"granted","requireApikey":true,"version":6},"error":null}`;
const defaultOnly = `{"result":{"Default":1},"error":null}`;

describe("AnkiConnect request shape", () => {
  it("always carries version 6 and no key by default", async () => {
    const { client: c, fake } = client({ version: json(`{"result":6,"error":null}`) });
    expect(await c.version()).toBe(6);
    const request = fake.requests[0];
    expect(request?.action).toBe("version");
    expect(request?.version).toBe(6);
    expect(request).not.toHaveProperty("key");
    expect(request).not.toHaveProperty("params");
    expect(fake.timeouts).toEqual([3]);
  });

  it("sends the API key when configured", async () => {
    const { client: c, fake } = client({ getNumCardsReviewedToday: json(`{"result":42,"error":null}`) }, { apiKey: "s3cret" });
    expect(await c.numCardsReviewedToday()).toBe(42);
    expect(fake.requests[0]?.key).toBe("s3cret");
  });
});

describe("AnkiConnect permission", () => {
  it("decodes the add-on code's spelling of requireApikey", async () => {
    const { client: c } = client({
      requestPermission: json(`{"result":{"permission":"granted","requireApikey":true,"version":6},"error":null}`),
    });
    expect(await c.connect()).toEqual({ granted: true, requireAPIKey: true, version: 6 });
  });

  it("also accepts the README's spelling", async () => {
    const { client: c } = client({
      requestPermission: json(`{"result":{"permission":"granted","requireApiKey":true,"version":6},"error":null}`),
    });
    expect((await c.requestPermission()).requireAPIKey).toBe(true);
  });
});

describe("AnkiConnect access check", () => {
  it("passes when cards can be read", async () => {
    const { client: c, fake } = client({ requestPermission: json(granted), deckNamesAndIds: json(defaultOnly) });
    expect(await c.checkAccess()).toBeUndefined();
    expect(fake.requests.map((r) => r.action)).toEqual(["requestPermission", "deckNamesAndIds"]);
  });

  it("fails when the handshake says a key is needed", async () => {
    const { client: c } = client({ requestPermission: json(keyed), deckNamesAndIds: json(defaultOnly) });
    expect(await c.checkAccess()).toEqual(AnkiErrors.apiKeyRequired);
  });

  it("catches a key the handshake does not mention", async () => {
    /* An older add-on grants the handshake without saying a key is set, then refuses every real call. */
    const { client: c } = client({
      requestPermission: json(granted),
      deckNamesAndIds: json(`{"result":null,"error":"valid api key must be provided"}`),
    });
    expect(await c.checkAccess()).toEqual(AnkiErrors.apiKeyRequired);
  });

  it("passes with the configured key", async () => {
    const { client: c, fake } = client({ requestPermission: json(keyed), deckNamesAndIds: json(defaultOnly) }, { apiKey: "s3cret" });
    expect(await c.checkAccess()).toBeUndefined();
    expect(fake.requests.at(-1)?.key).toBe("s3cret");
  });

  it("reports a closed profile", async () => {
    const { client: c } = client({
      requestPermission: json(granted),
      deckNamesAndIds: json(`{"result":null,"error":"collection is not available"}`),
    });
    expect(await c.checkAccess()).toEqual(AnkiErrors.collectionUnavailable);
  });

  it("reports a denied handshake", async () => {
    const { client: c } = client({ requestPermission: json(`{"result":{"permission":"denied"},"error":null}`) });
    expect(await c.checkAccess()).toEqual(AnkiErrors.permissionDenied);
    expect(await caught(c.connect())).toEqual(AnkiErrors.permissionDenied);
  });

  it("rejects an old add-on version from connect", async () => {
    const { client: c } = client({
      requestPermission: json(`{"result":{"permission":"granted","requireApikey":false,"version":5},"error":null}`),
    });
    expect(await caught(c.connect())).toEqual(AnkiErrors.addOnOutdated(5));
  });

  it("reads HTTP 403 as permission denied", async () => {
    const { client: c } = client({ version: failure({ kind: "status", status: 403 }) });
    expect(await caught(c.version())).toEqual(AnkiErrors.permissionDenied);
    const { client: other } = client({ version: failure({ kind: "status", status: 500 }) });
    expect(await caught(other.version())).toEqual(AnkiErrors.transport("HTTP 500"));
  });
});

describe("AnkiConnect decks and stats", () => {
  it("sorts decks by name and keeps their ids", async () => {
    const { client: c } = client({ deckNamesAndIds: json(recorded.deckList) });
    const decks = await c.decks();
    expect(decks.map((d) => d.name)).toEqual(["Default", "Step1", "Step1::Cardio"]);
    expect(decks.map((d) => d.id)).toEqual([1, 2, 3]);
    const cardio = decks[2];
    const first = decks[0];
    if (!cardio || !first) throw new Error("missing decks");
    expect(deckLeafName(cardio)).toBe("Cardio");
    expect(deckDepth(cardio)).toBe(1);
    expect(deckDepth(first)).toBe(0);
  });

  it("matches stats by id and keeps full names in the requested order (old leaf-name replies)", async () => {
    const { client: c, fake } = client({ getDeckStats: json(recorded.leafNameStats) });
    const stats = await c.deckStats([
      { id: 1651445861960, name: "Easy Spanish" },
      { id: 1651445861967, name: "Japanese::JLPT N5" },
      { id: 7, name: "Missing" },
    ]);
    expect(stats.map((s) => s.name)).toEqual(["Easy Spanish", "Japanese::JLPT N5"]);
    expect(stats.map((s) => s.deckID)).toEqual([1651445861960, 1651445861967]);
    expect(stats[0]).toEqual({
      deckID: 1651445861960,
      name: "Easy Spanish",
      newCount: 26,
      learnCount: 10,
      reviewCount: 5,
      totalInDeck: 852,
    });
    const firstStats = stats[0];
    if (!firstStats) throw new Error("missing stats");
    expect(dueTotal(firstStats)).toBe(41);
    expect(params(fake.requests[0]).decks).toEqual(["Easy Spanish", "Japanese::JLPT N5", "Missing"]);
  });

  it("skips the request for no decks", async () => {
    const { client: c, fake } = client({});
    expect(await c.deckStats([])).toEqual([]);
    expect(fake.requests).toEqual([]);
  });
});

describe("AnkiConnect history and reviews", () => {
  it("decodes heterogeneous day pairs", async () => {
    const { client: c } = client({ getNumCardsReviewedByDay: json(`{"result":[["2021-02-28",124],["2021-02-27",261]],"error":null}`) });
    expect(await c.numCardsReviewedByDay()).toEqual([
      { day: ankiDay(2021, 2, 28), count: 124 },
      { day: ankiDay(2021, 2, 27), count: 261 },
    ]);
  });

  it("reads a malformed day as an invalid response naming the action", async () => {
    const { client: c } = client({ getNumCardsReviewedByDay: json(`{"result":[["yesterday",1]],"error":null}`) });
    const error = await caught(c.numCardsReviewedByDay());
    expect(error.kind).toBe("invalidResponse");
    expect("message" in error && error.message.startsWith("getNumCardsReviewedByDay")).toBe(true);
  });

  it("decodes review nine-tuples", async () => {
    const fixture = `{"result":[[1594194095746,1485369733217,-1,3,4,-60,2500,6157,0],[1594201393292,1485369902086,-1,1,-60,-60,0,4846,1]],"error":null}`;
    const { client: c, fake } = client({ cardReviews: json(fixture) });
    const reviews = await c.cardReviews("default", 1594194095740);
    expect(reviews).toHaveLength(2);
    expect(reviews[0]).toEqual({
      id: 1594194095746,
      cardID: 1485369733217,
      ease: 3,
      interval: 4,
      lastInterval: -60,
      factor: 2500,
      durationMilliseconds: 6157,
      kind: AnkiReviewKind.learn,
    });
    const [first, second] = reviews;
    if (!first || !second) throw new Error("missing reviews");
    expect(isFailure(second)).toBe(true);
    expect(second.kind).toBe(AnkiReviewKind.review);
    expect(reviewedAt(first)).toBeCloseTo(1594194095.746, 3);
    expect(params(fake.requests[0])).toEqual({ deck: "default", startID: 1594194095740 });
  });

  it("tolerates an unknown review kind", async () => {
    const { client: c } = client({ cardReviews: json(`{"result":[[1,2,-1,3,4,5,2500,100,9]],"error":null}`) });
    expect((await c.cardReviews("d", 0))[0]?.kind).toBe(AnkiReviewKind.unknown);
  });

  it("batches several decks' reviews through one multi", async () => {
    const fixture =
      `{"result":[{"result":[[1594194095746,1485369733217,-1,3,4,-60,2500,6157,1]],"error":null},{"result":[],"error":null},` +
      `{"result":[[1594201393292,1485369902086,-1,1,-60,-60,0,4846,1]],"error":null}],"error":null}`;
    const { client: c, fake } = client({ multi: json(fixture) });
    const reviews = await c.cardReviewsForDecks(["Step1", "Step1::Cardio", "Pharm"], 42);
    expect(reviews.map((r) => r.id)).toEqual([1594194095746, 1594201393292]);
    expect(fake.requests).toHaveLength(1);
    expect(fake.timeouts).toEqual([20]);
    const request = fake.requests[0];
    expect(request?.action).toBe("multi");
    const actions = params(request).actions as Record<string, unknown>[];
    expect(actions.map((a) => a.action)).toEqual(["cardReviews", "cardReviews", "cardReviews"]);
    expect(actions.every((a) => a.version === 6)).toBe(true);
    expect(actions.map((a) => params(a).deck)).toEqual(["Step1", "Step1::Cardio", "Pharm"]);
    expect(actions.every((a) => params(a).startID === 42)).toBe(true);
  });

  it("skips the batched request for no decks", async () => {
    const { client: c, fake } = client({});
    expect(await c.cardReviewsForDecks([], 0)).toEqual([]);
    expect(fake.requests).toEqual([]);
  });

  it("surfaces inner errors of a batch", async () => {
    const { client: failing } = client({
      multi: json(`{"result":[{"result":[],"error":null},{"result":null,"error":"collection is not available"}],"error":null}`),
    });
    expect(await caught(failing.cardReviewsForDecks(["A", "B"], 0))).toEqual(AnkiErrors.collectionUnavailable);
    const { client: short } = client({ multi: json(`{"result":[{"result":[],"error":null}],"error":null}`) });
    expect(await caught(short.cardReviewsForDecks(["A", "B"], 0))).toEqual(
      AnkiErrors.invalidResponse("multi: expected 2 replies, got 1"),
    );
  });

  it("sends the find query", async () => {
    const { client: c, fake } = client({ findCards: json(`{"result":[1494723142483,1494703460437],"error":null}`) });
    expect(await c.findCards(`deck:"Step1" rated:7`)).toEqual([1494723142483, 1494703460437]);
    expect(params(fake.requests[0]).query).toBe(`deck:"Step1" rated:7`);
  });
});

describe("AnkiConnect GUI and sync", () => {
  it("sends the deck name for GUI actions", async () => {
    const { client: c, fake } = client({
      guiDeckReview: json(`{"result":true,"error":null}`),
      guiDeckOverview: json(`{"result":false,"error":null}`),
    });
    expect(await c.guiDeckReview("Step1")).toBe(true);
    expect(await c.guiDeckOverview("Nope")).toBe(false);
    expect(fake.requests.map((r) => params(r).name)).toEqual(["Step1", "Nope"]);
  });

  it("syncs with the long timeout and accepts a null result", async () => {
    const { client: c, fake } = client({ sync: json(`{"result":null,"error":null}`) });
    await c.sync();
    expect(fake.timeouts).toEqual([90]);
  });

  it("types a sync without an AnkiWeb login", async () => {
    const { client: c } = client({ sync: json(`{"result":null,"error":"sync: auth not configured"}`) });
    expect(await caught(c.sync())).toEqual(AnkiErrors.syncNotConfigured);
  });
});

describe("AnkiConnect error mapping", () => {
  it("reads a refused connection without Anki as not running", async () => {
    const { client: c } = client({ version: failure({ kind: "connectionRefused" }) }, { ankiRunning: false });
    expect(await caught(c.version())).toEqual(AnkiErrors.ankiNotRunning);
  });

  it("reads a refused connection while Anki runs as add-on missing", async () => {
    const { client: c } = client({ version: failure({ kind: "connectionRefused" }) }, { ankiRunning: true });
    expect(await caught(c.version())).toEqual(AnkiErrors.addOnMissing);
  });

  it("maps timeouts and other transport failures", async () => {
    const { client: timingOut } = client({ version: failure({ kind: "timedOut" }) });
    expect(await caught(timingOut.version())).toEqual(AnkiErrors.timeout);
    const { client: broken } = client({ version: failure({ kind: "failed", message: "boom" }) });
    expect(await caught(broken.version())).toEqual(AnkiErrors.transport("boom"));
    const thrower = new AnkiConnectClient({
      transport: async () => {
        throw new Error("socket hang up");
      },
    });
    expect(await caught(thrower.version())).toEqual(AnkiErrors.transport("socket hang up"));
  });

  it("maps Anki's error strings to typed cases", async () => {
    const { client: keyedClient } = client({ deckNamesAndIds: json(`{"result":null,"error":"valid api key must be provided"}`) });
    expect(await caught(keyedClient.decks())).toEqual(AnkiErrors.apiKeyRequired);
    const { client: old } = client({});
    expect(await caught(old.numCardsReviewedByDay())).toEqual(AnkiErrors.unsupportedAction("getNumCardsReviewedByDay"));
    const { client: other } = client({ findCards: json(`{"result":null,"error":"invalid search"}`) });
    expect(await caught(other.findCards("("))).toEqual(AnkiErrors.anki("invalid search"));
    expect(errorFromAnkiMessage("collection is not available", "x")).toEqual(AnkiErrors.collectionUnavailable);
  });

  it("reads non-JSON and wrong types as invalid responses", async () => {
    const { client: garbage } = client({ version: json("<html>") });
    expect(await caught(garbage.version())).toEqual(AnkiErrors.invalidResponse("version: not JSON"));
    const { client: wrong } = client({ version: json(`{"result":"six","error":null}`) });
    expect((await caught(wrong.version())).kind).toBe("invalidResponse");
  });

  it("accepts a reply the host already parsed", async () => {
    const parsed = new AnkiConnectClient({ transport: async () => ({ result: 6, error: null }) });
    expect(await parsed.version()).toBe(6);
  });

  it("has human copy for every error", () => {
    const all: AnkiConnectError[] = [
      AnkiErrors.ankiNotRunning,
      AnkiErrors.addOnMissing,
      AnkiErrors.timeout,
      AnkiErrors.permissionDenied,
      AnkiErrors.apiKeyRequired,
      AnkiErrors.addOnOutdated(4),
      AnkiErrors.unsupportedAction("x"),
      AnkiErrors.collectionUnavailable,
      AnkiErrors.syncNotConfigured,
      AnkiErrors.anki("x"),
      AnkiErrors.invalidResponse("x"),
      AnkiErrors.transport("x"),
    ];
    for (const error of all) {
      expect(errorTitle(error)).not.toBe("");
      expect(errorSuggestion(error).endsWith(".")).toBe(true);
    }
    expect(errorSuggestion(AnkiErrors.addOnMissing)).toContain(ANKI_CONNECT_ADD_ON_CODE);
  });
});

describe("AnkiConnect cancellation", () => {
  it("sends nothing for a caller that already cancelled", async () => {
    const { client: c, fake } = client({ version: failure({ kind: "connectionRefused" }) });
    const controller = new AbortController();
    controller.abort();
    await expect(c.version(controller.signal)).rejects.toMatchObject({ name: "AbortError" });
    expect(fake.requests).toEqual([]);
  });

  it("lets cancellation during a request win over its error", async () => {
    const controller = new AbortController();
    const c = new AnkiConnectClient({
      transport: async () => {
        controller.abort();
        throw { kind: "timedOut" };
      },
    });
    const error = await c.version(controller.signal).catch((e: unknown) => e);
    expect(error).not.toBeInstanceOf(AnkiConnectFailure);
    expect(error).toMatchObject({ name: "AbortError" });
  });

  it("hands the signal and timeout to the transport", async () => {
    const controller = new AbortController();
    let seen: AbortSignal | undefined;
    const c = new AnkiConnectClient({
      transport: async (request) => {
        seen = request.signal;
        return `{"result":6,"error":null}`;
      },
    });
    await c.version(controller.signal);
    expect(seen).toBe(controller.signal);
  });
});

describe("AnkiConnect host and detection", () => {
  it("posts to loopback", () => {
    expect(ANKI_CONNECT_ENDPOINT).toBe("http://127.0.0.1:8765");
  });

  it("recognizes Anki's process by name", () => {
    expect(isAnkiProcess("anki.exe")).toBe(true);
    expect(isAnkiProcess("C:\\Program Files\\Anki\\anki.exe")).toBe(true);
    expect(isAnkiProcess("Anki")).toBe(true);
    expect(isAnkiProcess("msedge.exe")).toBe(false);
    expect(isAnkiProcess(undefined)).toBe(false);
  });
});

describe("AnkiDay", () => {
  it("parses and does arithmetic", () => {
    expect(parseAnkiDay("2021-13-01")).toBeUndefined();
    expect(parseAnkiDay("nope")).toBeUndefined();
    const day = parseAnkiDay("2024-02-28");
    if (!day) throw new Error("did not parse");
    expect(ankiDayText(addingDays(day, 1))).toBe("2024-02-29");
    expect(ankiDayText(addingDays(day, 2))).toBe("2024-03-01");
    const newYear = parseAnkiDay("2025-01-01");
    if (!newYear) throw new Error("did not parse");
    expect(ankiDayText(addingDays(newYear, -1))).toBe("2024-12-31");
    expect(compareAnkiDays(day, addingDays(day, 1))).toBeLessThan(0);
  });

  it("respects the rollover hour in the given zone", () => {
    const twoAM = instantFromZoned(2026, 10, 1, 2, "America/New_York");
    expect(ankiDayText(ankiDayAt(twoAM, "America/New_York", 4))).toBe("2026-09-30");
    expect(ankiDayText(ankiDayAt(twoAM, "America/New_York", 0))).toBe("2026-10-01");
  });
});
