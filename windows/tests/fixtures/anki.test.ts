import { beforeAll, describe, expect, it } from "vitest";
import { ACTIVITY_UNITS, makeActivityRecord } from "../../src/core/activity/activityRecord";
import {
  AnkiConnectClient,
  type AnkiRequest,
  type AnkiTransportError,
} from "../../src/core/anki/ankiConnectClient";
import {
  type AnkiConnectError,
  AnkiConnectFailure,
  errorMessage,
  errorSuggestion,
  errorTitle,
  failsWholeRefresh,
  isUnexplained,
  quotedMessage,
} from "../../src/core/anki/ankiConnectError";
import { dueTotal } from "../../src/core/anki/ankiConnectModels";
import {
  isSetupStep,
  keepsLastSummary,
  refreshInterval,
  resolveAnkiConnectionState,
} from "../../src/core/anki/ankiConnectionState";
import {
  ankiConnectionClearsBySelf,
  ankiConnectionStatus,
  ankiConnectionTechnicalLabel,
  connectionActionName,
  connectionActionTitle,
} from "../../src/core/anki/ankiConnectionStatus";
import { ankiDayText } from "../../src/core/anki/ankiDay";
import { dayHelp, heatLevels, progressHelp, streakText } from "../../src/core/anki/ankiFormat";
import {
  type AnkiSummary,
  type AnkiSummaryPiece,
  ankiProgressItem,
  completionFraction,
  deckOutline,
  fetchAnkiSummary,
  hasReviewedToday,
  reviewActivity,
  summaryDay,
  summaryDueTotal,
  topDecks,
} from "../../src/core/anki/ankiSummary";
import { switchLanguage } from "../support/catalogs";
import { loadFixture } from "../support/fixtures";
import { goldenDiff } from "../support/goldenCompare";

/*
 * Replays shared/fixtures/anki (written by AnkiGoldenTests on the Mac): each
 * case is one refresh on a fresh client, answered with the recorded replies
 * in order. The suite compares the requests and timeouts the port sends,
 * the errors it reports, and the summary or error, the AnkiFormat strings,
 * the progress goal, the activity record and the connection row it ends with.
 */

interface Reply {
  status?: number;
  body?: string;
  failure?: "connectionRefused" | "timedOut" | "failed";
  failureMessage?: string;
}

interface Exchange {
  request: unknown;
  timeout: number;
  reply: Reply;
}

interface LoggedActivity {
  source: string;
  kind: string;
  quantity: number;
  ankiDay?: string;
}

interface Environment {
  now: number;
  timeZone: string;
  rolloverHour: number;
  apiKey?: string;
  ankiRunning: boolean;
  isInstalled: boolean;
  launchedAt?: number;
}

interface Case {
  name: string;
  environment: Environment;
  activityLog: LoggedActivity[];
  exchanges: Exchange[];
  reportedErrors: { action: string; error: string }[];
  summary?: unknown;
  format?: unknown;
  progress?: unknown;
  activity?: unknown;
  error?: unknown;
  connection: unknown;
}

interface AnkiFixture {
  schema: string;
  version: number;
  cases: Case[];
}

const fixture = loadFixture<AnkiFixture>("anki/anki.json");

/** The module the activity record and progress goal carry, as on the Mac. */
const SOURCE = "anki";

/* The Mac's Piece.allCases order, which the fixture lists `missing` in. */
const PIECES: AnkiSummaryPiece[] = ["todayCount", "history", "reviewLog"];

/** Answers each request with the next recorded reply and keeps what was sent. */
function replayTransport(exchanges: readonly Exchange[], sent: { request: unknown; timeout: number }[]) {
  return async (request: AnkiRequest): Promise<unknown> => {
    const recorded = exchanges[sent.length];
    sent.push({ request: JSON.parse(request.body) as unknown, timeout: request.timeoutSeconds });
    if (!recorded) throw new Error(`request ${sent.length} was never recorded: ${request.body}`);
    const reply = recorded.reply;
    if (reply.failure === "connectionRefused") throw { kind: "connectionRefused" } satisfies AnkiTransportError;
    if (reply.failure === "timedOut") throw { kind: "timedOut" } satisfies AnkiTransportError;
    if (reply.failure === "failed") {
      throw { kind: "failed", message: reply.failureMessage ?? "" } satisfies AnkiTransportError;
    }
    const status = reply.status ?? 200;
    if (status < 200 || status > 299) throw { kind: "status", status } satisfies AnkiTransportError;
    return reply.body ?? "";
  };
}

function summaryOutput(summary: AnkiSummary): unknown {
  const day = summaryDay(summary);
  return {
    day: day && ankiDayText(day),
    newDue: summary.newDue,
    learnDue: summary.learnDue,
    reviewDue: summary.reviewDue,
    dueTotal: summaryDueTotal(summary),
    reviewedToday: summary.reviewedToday,
    hasReviewedToday: hasReviewedToday(summary),
    streak: summary.streak,
    history: summary.history.map((entry) => ({ day: ankiDayText(entry.day), count: entry.count })),
    retention: summary.retention,
    retentionSampleSize: summary.retentionSampleSize,
    studyTimeToday: summary.studyTimeToday,
    completionFraction: completionFraction(summary),
    decks: summary.decks.map((deck) => ({ ...deck, dueTotal: dueTotal(deck) })),
    topDecks: topDecks(summary).map((deck) => deck.name),
    deckOutline: deckOutline(summary).map((row) => ({ deckID: row.deck.deckID, depth: row.depth, title: row.title })),
    missing: PIECES.filter((piece) => summary.missing.has(piece)),
    gaps: summary.gaps.map((gap) => ({ action: gap.action, message: gap.message })),
  };
}

function formatOutput(summary: AnkiSummary): unknown {
  const today = summaryDay(summary);
  return {
    streak: streakText(summary.streak),
    progressHelp: progressHelp(summary),
    heatLevels: heatLevels(summary.history),
    dayHelp: today === undefined ? [] : summary.history.map((entry) => dayHelp(entry, today, "en-US")),
  };
}

function progressOutput(summary: AnkiSummary): unknown {
  const item = ankiProgressItem(summary, SOURCE);
  return {
    id: item.id,
    title: item.title,
    completed: item.completed,
    target: item.target,
    unit: item.unit,
    actionID: item.action?.id,
    actionTitle: item.action?.title,
  };
}

function activityOutput(summary: AnkiSummary, log: readonly LoggedActivity[], now: number): unknown {
  /* Logged an hour before the refresh, as the Mac's test logs them. */
  const logged = log.map((entry) =>
    makeActivityRecord({
      id: "6A1F1C1E-0000-4000-8000-000000000001",
      source: entry.source,
      kind: entry.kind,
      start: now - 3600,
      quantity: entry.quantity,
      unit: ACTIVITY_UNITS.cards,
      metadata: entry.ankiDay === undefined ? {} : { ankiDay: entry.ankiDay },
    }),
  );
  const record = reviewActivity(summary, logged, SOURCE, now);
  if (record === undefined) return undefined;
  return {
    source: record.source,
    kind: record.kind,
    start: record.start,
    end: record.end,
    quantity: record.quantity,
    unit: record.unit,
    metadata: record.metadata,
  };
}

function errorOutput(error: AnkiConnectError): unknown {
  return {
    kind: error.kind,
    message: errorMessage(error),
    quotedMessage: quotedMessage(error),
    isUnexplained: isUnexplained(error),
    failsWholeRefresh: failsWholeRefresh(error),
    title: errorTitle(error),
    suggestion: errorSuggestion(error),
  };
}

function connectionOutput(error: AnkiConnectError | undefined, environment: Environment): unknown {
  const state = resolveAnkiConnectionState(error, environment.isInstalled, environment.launchedAt, environment.now);
  const status = ankiConnectionStatus(state);
  return {
    state: ankiConnectionTechnicalLabel(state),
    isSetupStep: isSetupStep(state),
    keepsLastSummary: keepsLastSummary(state),
    refreshInterval: refreshInterval(state),
    clearsBySelf: ankiConnectionClearsBySelf(state),
    light: status.light,
    headline: status.headline,
    detail: status.detail,
    action: status.action && connectionActionName(status.action),
    actionTitle: status.action && connectionActionTitle(status.action),
  };
}

interface Outcome {
  sent: { request: unknown; timeout: number }[];
  reported: { action: string; error: string }[];
  outputs: Record<string, unknown>;
}

async function refresh(testCase: Case): Promise<Outcome> {
  const { environment } = testCase;
  const sent: { request: unknown; timeout: number }[] = [];
  const reported: { action: string; error: string }[] = [];
  const client = new AnkiConnectClient({
    transport: replayTransport(testCase.exchanges, sent),
    apiKey: environment.apiKey,
    isAnkiRunning: async () => environment.ankiRunning,
    onError: (action, error) => reported.push({ action, error: error.kind }),
  });
  let summary: AnkiSummary | undefined;
  let failure: AnkiConnectError | undefined;
  try {
    summary = await fetchAnkiSummary(client, {
      now: environment.now,
      timeZone: environment.timeZone,
      rolloverHour: environment.rolloverHour,
    });
  } catch (error) {
    if (!(error instanceof AnkiConnectFailure)) throw error;
    failure = error.error;
  }
  return {
    sent,
    reported,
    outputs: {
      summary: summary && summaryOutput(summary),
      format: summary && formatOutput(summary),
      progress: summary && progressOutput(summary),
      activity: summary && activityOutput(summary, testCase.activityLog, environment.now),
      error: failure && errorOutput(failure),
      connection: connectionOutput(failure, environment),
    },
  };
}

describe("anki golden fixture", () => {
  beforeAll(() => switchLanguage("en"));

  it("is the version this suite reads", () => {
    expect(fixture.schema).toBe("tabbi.anki.golden");
    expect(fixture.version).toBe(1);
    expect(fixture.cases).toHaveLength(21);
  });

  describe.each(fixture.cases.map((testCase) => [testCase.name, testCase] as const))("%s", (_name, testCase) => {
    let outcome: Outcome;
    beforeAll(async () => {
      outcome = await refresh(testCase);
    });

    it("sends the recorded requests with the recorded timeouts", () => {
      const expected = testCase.exchanges.map((exchange) => ({ request: exchange.request, timeout: exchange.timeout }));
      expect(goldenDiff(outcome.sent, expected)).toBeUndefined();
    });

    it("reports the recorded errors", () => {
      expect(goldenDiff(outcome.reported, testCase.reportedErrors)).toBeUndefined();
    });

    it.each(["summary", "format", "progress", "activity", "error", "connection"] as const)("ends with the recorded %s", (key) => {
      const expected = testCase[key];
      const actual = outcome.outputs[key];
      if (expected === undefined) expect(actual).toBeUndefined();
      else expect(goldenDiff(actual, expected)).toBeUndefined();
    });
  });
});
