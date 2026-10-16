import { durationSeconds } from "../../../src/core/formatting/durationFormat";
import { describe, expect, it } from "vitest";
import { InMemoryDocumentStore } from "../../../src/core/persistence/documentStore";
import { VersionedJSON } from "../../../src/core/persistence/versionedJson";
import type { ClaudeStreamEvent } from "../../../src/core/claude/claudeStreamEvent";
import {
  decodeLimitsRecord,
  encodeLimitsRecord,
  firstLimitsSnapshot,
  LimitsProbeError,
  shouldRefreshOnOpen,
} from "../../../src/core/claudeUsage/claudeLimits";
import { aggregateUsage, emptyLocalStats, periodMessages, periodTokens, topModel } from "../../../src/core/claudeUsage/claudeLocalStats";
import {
  ClaudeUsageLogScanner,
  claudeProjectsRoot,
  CLAUDE_USAGE_SCAN_INDEX_NAME,
  MAX_LINE_LENGTH,
  type TranscriptFile,
} from "../../../src/core/claudeUsage/claudeUsageLogScanner";
import {
  compactTokens,
  modelName,
  percentText,
  resetDescription,
  updatedDescription,
  usageLevel,
} from "../../../src/core/claudeUsage/claudeUsageFormat";
import { probesLimits, usageHighlights, usageSourceFor } from "../../../src/core/claudeUsage/claudeUsageHighlights";
import { type ClaudeUsageRecord, parseUsageRecord, tokenUsage, totalTokens } from "../../../src/core/claudeUsage/claudeUsageRecord";
import { CODEX_DEFAULT_MODEL, codexFilesToRead, codexSessionsRoot, summarizeCodexSessions } from "../../../src/core/claudeUsage/codexUsageLog";

/* Port of ClaudeUsageTests and CodexUsageLogTests, with the file system replaced by an in-memory one. */

const at = (text: string) => Date.parse(text) / 1000;

function assistantLine(
  id: string,
  timestamp: string,
  options: { model?: string; input?: number; output?: number; cacheRead?: number; cacheCreation?: number } = {},
): string {
  const { model = "claude-opus-4-5-20251101", input = 1, output = 2, cacheRead = 3, cacheCreation = 4 } = options;
  return `{"parentUuid":"p","type":"assistant","message":{"model":"${model}","id":"${id}","role":"assistant","content":[{"type":"text","text":"hi"}],"usage":{"input_tokens":${input},"cache_creation_input_tokens":${cacheCreation},"cache_read_input_tokens":${cacheRead},"output_tokens":${output},"service_tier":"standard"}},"timestamp":"${timestamp}","sessionId":"s"}`;
}

describe("ClaudeUsageRecord", () => {
  it("parses assistant usage", () => {
    const record = parseUsageRecord(assistantLine("msg_1", "2026-10-01T12:30:00.250Z", { input: 10, output: 20, cacheRead: 30, cacheCreation: 40 }));
    expect(record?.messageID).toBe("msg_1");
    expect(record?.model).toBe("claude-opus-4-5-20251101");
    expect(record?.usage).toEqual({ input: 10, output: 20, cacheRead: 30, cacheCreation: 40 });
    expect(record && totalTokens(record.usage)).toBe(100);
    expect(record?.timestamp).toBeCloseTo(at("2026-10-01T12:30:00Z") + 0.25, 3);
  });

  it("accepts a timestamp without fractional seconds", () => {
    expect(parseUsageRecord(assistantLine("m", "2026-10-01T12:30:00Z"))).toBeDefined();
  });

  it("ignores non-assistant, malformed and synthetic lines", () => {
    const lines = [
      `{"type":"user","message":{"role":"user","content":"assistant usage"}}`,
      `{"type":"assistant","message":{"usage":`,
      "",
      `not json "assistant" "usage"`,
      assistantLine("m", "2026-10-01T12:30:00Z", { model: "<synthetic>" }),
      assistantLine("m", "yesterday"),
    ];
    for (const line of lines) expect(parseUsageRecord(line), line).toBeUndefined();
  });

  it("counts missing usage fields as zero and ignores content it does not need", () => {
    expect(parseUsageRecord(`{"type":"assistant","message":{"model":"claude-haiku-4-5","id":"m","usage":{"output_tokens":7}},"timestamp":"2026-10-01T00:00:00Z"}`)?.usage).toEqual(
      tokenUsage({ output: 7 }),
    );
    const line = `{"type":"assistant","message":{"model":"claude-opus-4-5","id":"m","content":[{"type":"tool_use","input":{"nested":[1,{"a":null}],"text":"\\"usage\\" \\n"}}],"usage":{"input_tokens":1,"output_tokens":2,"server_tool_use":{"web_search_requests":0}}},"timestamp":"2026-10-01T00:00:00Z","toolUseResult":{"x":[true]}}`;
    expect(parseUsageRecord(line)?.usage).toEqual(tokenUsage({ input: 1, output: 2 }));
  });
});

describe("ClaudeLocalStats", () => {
  const record = (id: string, model: string, timestamp: string, tokens: number): ClaudeUsageRecord => ({
    messageID: id,
    model,
    timestamp: at(timestamp),
    usage: tokenUsage({ input: tokens }),
  });

  it("splits today and seven days by model", () => {
    const stats = aggregateUsage(
      [
        record("a", "opus", "2026-10-01T09:00:00Z", 100),
        record("b", "opus", "2026-10-01T10:00:00Z", 50),
        record("c", "haiku", "2026-10-01T11:00:00Z", 500),
        record("d", "sonnet", "2026-09-30T23:59:59Z", 1000),
        record("e", "opus", "2026-09-25T00:00:00Z", 7),
        record("f", "opus", "2026-09-24T23:59:59Z", 9999),
        record("g", "opus", "2026-10-01T16:00:00Z", 9999),
      ],
      at("2026-10-01T15:00:00Z"),
      "UTC",
    );
    expect(periodMessages(stats.today)).toBe(3);
    expect(totalTokens(periodTokens(stats.today))).toBe(650);
    expect(topModel(stats.today)).toBe("haiku");
    expect(stats.today.models.map((m) => m.model)).toEqual(["haiku", "opus"]);
    expect(stats.today.models.at(-1)?.messages).toBe(2);
    expect(periodMessages(stats.lastSevenDays)).toBe(5);
    expect(totalTokens(periodTokens(stats.lastSevenDays))).toBe(1657);
    expect(topModel(stats.lastSevenDays)).toBe("sonnet");
  });

  it("has no top model for empty input", () => {
    const stats = aggregateUsage([], 0, "UTC");
    expect(stats).toEqual(emptyLocalStats());
    expect(topModel(stats.today)).toBeUndefined();
  });

  it("counts days in the given zone", () => {
    /* 23:30 UTC on Sep 30 is already Oct 1 in Auckland. */
    const stats = aggregateUsage([record("a", "opus", "2026-09-30T23:30:00Z", 5)], at("2026-10-01T01:00:00Z"), "Pacific/Auckland");
    expect(periodMessages(stats.today)).toBe(1);
  });
});

/** An in-memory folder of transcripts the scanner reads through the host's interface. */
class FakeDisk {
  readonly files = new Map<string, { bytes: Uint8Array; identity: string; modified: number }>();
  readonly reads: { path: string; offset: number }[] = [];
  private nextIdentity = 1;

  write(path: string, lines: string[], modified: number, trailingNewline = true): void {
    const text = lines.join("\n") + (trailingNewline ? "\n" : "");
    this.files.set(path, { bytes: new TextEncoder().encode(text), identity: String(this.nextIdentity++), modified });
  }

  append(path: string, text: string, modified: number): void {
    const file = this.files.get(path);
    if (!file) throw new Error(path);
    const added = new TextEncoder().encode(text);
    const bytes = new Uint8Array(file.bytes.length + added.length);
    bytes.set(file.bytes);
    bytes.set(added, file.bytes.length);
    this.files.set(path, { ...file, bytes, modified });
  }

  listing(): TranscriptFile[] {
    return [...this.files]
      .filter(([path]) => path.endsWith(".jsonl"))
      .map(([path, file]) => ({ path, size: file.bytes.length, identity: file.identity, modified: file.modified }));
  }

  readonly read = async (path: string, offset: number) => {
    this.reads.push({ path, offset });
    return this.files.get(path)?.bytes.subarray(offset);
  };
}

describe("ClaudeUsageLogScanner", () => {
  const now = at("2026-10-01T15:00:00Z");
  const scan = (scanner: ClaudeUsageLogScanner, disk: FakeDisk, when = now) => scanner.scan(disk.listing(), disk.read, when, "UTC");

  it("scans nested files and dedupes content-block lines", async () => {
    const disk = new FakeDisk();
    disk.write(
      "a\\one.jsonl",
      [assistantLine("m1", "2026-10-01T10:00:00Z"), assistantLine("m1", "2026-10-01T10:00:00Z"), "{garbage", `{"type":"user","message":{"content":"hi"}}`],
      now,
    );
    disk.write("a\\session\\subagents\\agent.jsonl", [assistantLine("m2", "2026-10-01T11:00:00Z", { model: "claude-haiku-4-5" })], now);
    disk.write("a\\notes.txt", [assistantLine("m3", "2026-10-01T11:00:00Z")], now);
    const stats = await scan(new ClaudeUsageLogScanner(), disk);
    expect(periodMessages(stats.today)).toBe(2);
    expect(totalTokens(periodTokens(stats.today))).toBe(20);
  });

  it("reads only appended bytes and waits for partial lines", async () => {
    const disk = new FakeDisk();
    disk.write("s.jsonl", [assistantLine("m1", "2026-10-01T10:00:00Z")], now);
    const scanner = new ClaudeUsageLogScanner();
    expect(periodMessages((await scan(scanner, disk)).today)).toBe(1);
    const next = assistantLine("m2", "2026-10-01T11:00:00Z");
    disk.append("s.jsonl", next.slice(0, 40), now);
    expect(periodMessages((await scan(scanner, disk)).today)).toBe(1);
    disk.append("s.jsonl", next.slice(40) + "\n", now);
    expect(periodMessages((await scan(scanner, disk)).today)).toBe(2);
    const firstLength = new TextEncoder().encode(assistantLine("m1", "2026-10-01T10:00:00Z") + "\n").length;
    expect(disk.reads.map((r) => r.offset)).toEqual([0, firstLength, firstLength]);
  });

  it("rereads a file that shrank or was replaced", async () => {
    const disk = new FakeDisk();
    disk.write("s.jsonl", [1, 2, 3].map((n) => assistantLine(`m${n}`, "2026-10-01T10:00:00Z")), now);
    const scanner = new ClaudeUsageLogScanner();
    await scan(scanner, disk);
    disk.write("s.jsonl", [assistantLine("m4", "2026-10-01T12:00:00Z")], now);
    expect(periodMessages((await scan(scanner, disk)).today)).toBe(4);
  });

  it("drops records that age out of the window", async () => {
    const disk = new FakeDisk();
    disk.write("s.jsonl", [assistantLine("old", "2026-09-25T10:00:00Z"), assistantLine("new", "2026-10-01T10:00:00Z")], now);
    const scanner = new ClaudeUsageLogScanner();
    expect(periodMessages((await scan(scanner, disk)).lastSevenDays)).toBe(2);
    const later = await scan(scanner, disk, at("2026-10-02T09:00:00Z"));
    expect(periodMessages(later.lastSevenDays)).toBe(1);
    expect(periodMessages(later.today)).toBe(0);
  });

  it("is empty with no transcripts", async () => {
    expect(await scan(new ClaudeUsageLogScanner(), new FakeDisk())).toEqual(emptyLocalStats());
  });

  it("skips files last modified before the window without reading them", async () => {
    const disk = new FakeDisk();
    disk.write("old.jsonl", [assistantLine("m1", "2026-10-01T10:00:00Z")], at("2026-09-20T00:00:00Z"));
    expect(await scan(new ClaudeUsageLogScanner(), disk)).toEqual(emptyLocalStats());
    expect(disk.reads).toEqual([]);
  });

  it("survives a relaunch through its index without rereading files", async () => {
    const disk = new FakeDisk();
    disk.write("a.jsonl", [assistantLine("m1", "2026-10-01T10:00:00Z")], now);
    disk.write("b.jsonl", [assistantLine("m2", "2026-10-01T11:00:00Z")], now);
    const store = new InMemoryDocumentStore();
    await scan(new ClaudeUsageLogScanner({ store }), disk);
    expect(Object.keys(store.snapshot())).toEqual([CLAUDE_USAGE_SCAN_INDEX_NAME]);
    disk.append("b.jsonl", assistantLine("m3", "2026-10-01T12:00:00Z") + "\n", now);
    disk.reads.length = 0;
    const stats = await scan(new ClaudeUsageLogScanner({ store }), disk);
    expect(periodMessages(stats.today)).toBe(3);
    expect(totalTokens(periodTokens(stats.today))).toBe(30);
    expect(disk.reads.map((r) => r.path)).toEqual(["b.jsonl"]);
  });

  it("dedupes copies of a persisted message after a model ages out", async () => {
    const disk = new FakeDisk();
    disk.write(
      "a.jsonl",
      [
        assistantLine("old", "2026-09-25T10:00:00Z", { model: "claude-sonnet-4-5", output: 100 }),
        assistantLine("m1", "2026-10-01T10:00:00Z", { model: "claude-haiku-4-5", output: 7 }),
        assistantLine("m2", "2026-10-01T11:00:00Z", { output: 9 }),
      ],
      now,
    );
    const later = at("2026-10-02T09:00:00Z");
    const store = new InMemoryDocumentStore();
    await scan(new ClaudeUsageLogScanner({ store }), disk);
    await scan(new ClaudeUsageLogScanner({ store }), disk, later);
    disk.write("resumed.jsonl", [assistantLine("m1", "2026-10-01T10:00:00Z", { model: "claude-haiku-4-5", output: 7 })], later);
    const stats = await scan(new ClaudeUsageLogScanner({ store }), disk, later);
    expect(stats.lastSevenDays.models.map((m) => m.model)).toEqual(["claude-opus-4-5-20251101", "claude-haiku-4-5"]);
    expect(stats.lastSevenDays.models.map((m) => m.tokens.output)).toEqual([9, 7]);
    expect(periodMessages(stats.lastSevenDays)).toBe(2);
  });

  it("falls back to a full scan with a corrupt index", async () => {
    const store = new InMemoryDocumentStore({ [CLAUDE_USAGE_SCAN_INDEX_NAME]: "{not json" });
    const disk = new FakeDisk();
    disk.write("a.jsonl", [assistantLine("m1", "2026-10-01T10:00:00Z")], now);
    expect(periodMessages((await scan(new ClaudeUsageLogScanner({ store }), disk)).today)).toBe(1);
  });

  it("skips lines longer than the limit and keeps reading", async () => {
    const disk = new FakeDisk();
    const filler = "x".repeat(MAX_LINE_LENGTH + 10);
    disk.write("s.jsonl", [assistantLine("m1", "2026-10-01T10:00:00Z"), `{"type":"user","text":"${filler}"}`, assistantLine("m2", "2026-10-01T11:00:00Z")], now);
    expect(periodMessages((await scan(new ClaudeUsageLogScanner(), disk)).today)).toBe(2);
  });

  it("finds the projects folder under the user profile", () => {
    expect(claudeProjectsRoot("C:\\Users\\ana\\")).toBe("C:\\Users\\ana\\.claude\\projects");
  });
});

describe("ClaudeUsageFormat", () => {
  it("writes compact token counts", () => {
    const cases: [number, string][] = [
      [0, "0"],
      [999, "999"],
      [1000, "1K"],
      [1250, "1.3K"],
      [12_340, "12.3K"],
      [123_456, "123K"],
      [999_400, "999K"],
      [999_950, "1M"],
      [1_200_000, "1.2M"],
      [3_400_000_000, "3.4B"],
      [-5, "0"],
    ];
    for (const [count, text] of cases) expect(compactTokens(count), String(count)).toBe(text);
  });

  it("writes percents and levels", () => {
    expect(percentText(0.424)).toBe("42%");
    expect(percentText(1.05)).toBe("105%");
    expect(percentText(-0.1)).toBe("0%");
    expect(usageLevel(0.69)).toBe("normal");
    expect(usageLevel(0.7)).toBe("warning");
    expect(usageLevel(0.9)).toBe("warning");
    expect(usageLevel(0.91)).toBe("critical");
  });

  it("writes durations", () => {
    expect(durationSeconds(30)).toBe("<1 min");
    expect(durationSeconds(14 * 60)).toBe("14 min");
    expect(durationSeconds(2 * 3600 + 13 * 60 + 5)).toBe("2h 14m");
    expect(durationSeconds(3 * 3600)).toBe("3h");
  });

  it("describes resets", () => {
    const now = at("2026-10-01T15:00:00Z");
    expect(resetDescription(undefined, now, "UTC")).toBeUndefined();
    expect(resetDescription(now - 5, now, "UTC")).toBe("resets now");
    expect(resetDescription(now + 2 * 3600 + 14 * 60, now, "UTC")).toBe("resets in 2h 14m");
    expect(resetDescription(at("2026-10-08T09:00:00Z"), now, "UTC")?.replace(/\s/gu, " ")).toBe("resets Thu 9:00 AM");
  });

  it("says when the numbers were updated", () => {
    const now = at("2026-10-01T15:00:00Z");
    expect(updatedDescription(now - 20, now)).toBe("Updated just now");
    expect(updatedDescription(now - 180, now)).toBe("Updated 3m ago");
    expect(updatedDescription(now - 7200, now)).toBe("Updated 2h ago");
    expect(updatedDescription(now - 3 * 86400, now)).toBe("Updated 3d ago");
    expect(updatedDescription(now + 60, now)).toBe("Updated just now");
  });

  it("names models", () => {
    expect(modelName("claude-opus-4-5-20251101")).toBe("Opus 4.5");
    expect(modelName("claude-haiku-4-5")).toBe("Haiku 4.5");
    expect(modelName("claude-sonnet-4-20250514")).toBe("Sonnet 4");
    expect(modelName("claude-3-5-sonnet-20241022")).toBe("Sonnet 3.5");
    expect(modelName("claude-opus-4-6[1m]")).toBe("Opus 4.6");
    expect(modelName("claude-opus-5-5")).toBe("Opus 5.5");
    expect(modelName("claude-fable-5-1")).toBe("Fable 5.1");
    expect(modelName("llama3.2")).toBe("llama3.2");
    expect(modelName("gpt-5-codex")).toBe("GPT-5 Codex");
    expect(modelName("gpt-5.1-codex-mini")).toBe("GPT-5.1 Codex Mini");
    expect(modelName("gpt-5")).toBe("GPT-5");
  });
});

describe("ClaudeLimitsRecord", () => {
  it("round-trips through its stored form", () => {
    const record = { snapshot: { status: "allowed", fiveHour: { utilization: 0.42, resetsAt: 1_790_912_400 } }, fetchedAt: 1_790_900_000 };
    expect(decodeLimitsRecord(encodeLimitsRecord(record))).toEqual(record);
    expect(VersionedJSON.version(encodeLimitsRecord(record) ?? "")).toBe(1);
  });

  it("decodes corrupt or missing data to nothing", () => {
    expect(decodeLimitsRecord(undefined)).toBeUndefined();
    expect(decodeLimitsRecord("{")).toBeUndefined();
    expect(decodeLimitsRecord(`{"status":"allowed"}`)).toBeUndefined();
  });

  it("refreshes on open only when stale", () => {
    const now = 1_000_000;
    const record = (age: number) => ({ snapshot: {}, fetchedAt: now - age });
    expect(shouldRefreshOnOpen(undefined, now)).toBe(false);
    expect(shouldRefreshOnOpen(record(9 * 60), now)).toBe(false);
    expect(shouldRefreshOnOpen(record(10 * 60), now)).toBe(true);
  });
});

describe("ClaudeLimitsProbe", () => {
  const window = { utilization: 0.3 };

  async function* events(list: ClaudeStreamEvent[], endless = false, stopped?: { value: boolean }): AsyncGenerator<ClaudeStreamEvent> {
    try {
      for (const event of list) yield event;
      if (endless) await new Promise(() => undefined);
    } finally {
      if (stopped) stopped.value = true;
    }
  }

  async function failure(promise: Promise<unknown>) {
    try {
      await promise;
    } catch (error) {
      if (error instanceof LimitsProbeError) return error.failure;
      throw error;
    }
    throw new Error("expected a probe failure");
  }

  it("takes the first rate limit with a window and stops consuming", async () => {
    const stopped = { value: false };
    const snapshot = await firstLimitsSnapshot(
      events(
        [
          { type: "sessionStarted", sessionID: "s" },
          { type: "rateLimit", snapshot: { status: "allowed" } },
          { type: "rateLimit", snapshot: { status: "allowed", fiveHour: window } },
        ],
        true,
        stopped,
      ),
    );
    expect(snapshot.fiveHour).toEqual(window);
    expect(stopped.value).toBe(true);
  });

  it("fails on an error result, a stream with no limits, and a timeout", async () => {
    expect(await failure(firstLimitsSnapshot(events([{ type: "result", result: { text: "Not logged in", isError: true } }])))).toEqual({
      kind: "cliError",
      message: "Not logged in",
    });
    expect(await failure(firstLimitsSnapshot(events([{ type: "assistantText", text: "ok" }])))).toEqual({ kind: "noLimitsReported" });
    expect(await failure(firstLimitsSnapshot(events([], true), AbortSignal.timeout(50)))).toEqual({ kind: "timedOut" });
  });
});

describe("CodexUsageLog", () => {
  const now = at("2026-10-09T12:00:00Z");
  const turnContext = (model: string) =>
    `{"timestamp":"2026-10-08T09:00:00.000Z","type":"turn_context","payload":{"cwd":"/tmp","approval_policy":"on-request","model":"${model}","summary":"auto"}}`;
  const defaultLimits = `{"primary":{"used_percent":42.0,"window_minutes":300,"resets_at":1791561600},"secondary":{"used_percent":76.5,"window_minutes":10080,"resets_at":1791900000}}`;
  const tokenCount = (timestamp: string, input: number, output: number, cached = 0, limits: string | null = defaultLimits) => {
    const info = `{"total_token_usage":{"input_tokens":${input},"cached_input_tokens":${cached},"output_tokens":${output},"reasoning_output_tokens":0,"total_tokens":${input + output}},"last_token_usage":{"input_tokens":1,"output_tokens":1,"total_tokens":2},"model_context_window":272000}`;
    return `{"timestamp":"${timestamp}","type":"event_msg","payload":{"type":"token_count","info":${info},"rate_limits":${limits ?? "null"}}}`;
  };
  const session = (...lines: string[]) => lines.join("\n");
  const summarize = (...sessions: string[]) => summarizeCodexSessions(sessions, now, "UTC");

  it("reads turns as the increases of the session totals", () => {
    const usage = summarize(
      session(
        turnContext("gpt-5-codex"),
        `{"timestamp":"2026-10-09T09:00:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"token_count"}]}}`,
        tokenCount("2026-10-09T09:00:05.000Z", 1000, 200, 400),
        tokenCount("2026-10-09T09:00:06.000Z", 1000, 200, 400),
        tokenCount("2026-10-09T09:01:00.000Z", 3000, 500, 2000),
      ),
    );
    expect(periodMessages(usage.stats.today)).toBe(2);
    expect(topModel(usage.stats.today)).toBe("gpt-5-codex");
    expect(periodTokens(usage.stats.today)).toEqual(tokenUsage({ input: 1000, output: 500, cacheRead: 2000 }));
    expect(totalTokens(periodTokens(usage.stats.today))).toBe(3500);
  });

  it("splits today from the week and drops older turns", () => {
    const usage = summarize(
      session(turnContext("gpt-5"), tokenCount("2026-10-01T10:00:00Z", 50, 50), tokenCount("2026-10-05T10:00:00Z", 150, 50)),
      session(turnContext("gpt-5-codex"), tokenCount("2026-10-09T08:00:00Z", 10, 20)),
    );
    expect(totalTokens(periodTokens(usage.stats.today))).toBe(30);
    expect(totalTokens(periodTokens(usage.stats.lastSevenDays))).toBe(130);
    expect(topModel(usage.stats.lastSevenDays)).toBe("gpt-5");
  });

  it("attributes model changes mid-session", () => {
    const usage = summarize(
      session(turnContext("gpt-5"), tokenCount("2026-10-09T09:00:00Z", 100, 0), turnContext("gpt-5-codex"), tokenCount("2026-10-09T09:05:00Z", 400, 0)),
    );
    expect(usage.stats.today.models.map((m) => m.model)).toEqual(["gpt-5-codex", "gpt-5"]);
    expect(usage.stats.today.models.map((m) => totalTokens(m.tokens))).toEqual([300, 100]);
  });

  it("keeps the newest limits with their reset times", () => {
    const older = `{"primary":{"used_percent":10,"window_minutes":300,"resets_at":1791500000},"secondary":{"used_percent":20,"window_minutes":10080,"resets_at":1791900000}}`;
    const usage = summarize(session(tokenCount("2026-10-09T11:00:00Z", 1, 1)), session(tokenCount("2026-10-09T10:00:00Z", 1, 1, 0, older)));
    expect(usage.limits?.fetchedAt).toBe(at("2026-10-09T11:00:00Z"));
    expect(usage.limits?.snapshot.fiveHour).toEqual({ utilization: 0.42, resetsAt: 1_791_561_600 });
    expect(usage.limits?.snapshot.sevenDay?.utilization).toBeCloseTo(0.765, 4);
  });

  it("reads older limit shapes", () => {
    const relative = `{"primary":{"used_percent":30,"window_minutes":299,"resets_in_seconds":10800},"secondary":null}`;
    const flat = `{"primary_used_percent":55,"secondary_used_percent":12,"primary_to_secondary_ratio_percent":20}`;
    const relativeUsage = summarize(session(tokenCount("2026-10-09T10:00:00Z", 1, 1, 0, relative)));
    expect(relativeUsage.limits?.snapshot.fiveHour?.resetsAt).toBe(at("2026-10-09T13:00:00Z"));
    expect(relativeUsage.limits?.snapshot.sevenDay).toBeUndefined();
    const flatUsage = summarize(session(tokenCount("2026-10-09T10:00:00Z", 1, 1, 0, flat)));
    expect(flatUsage.limits?.snapshot.fiveHour).toEqual({ utilization: 0.55 });
    expect(flatUsage.limits?.snapshot.sevenDay).toEqual({ utilization: 0.12 });
  });

  it("empties windows that reset since the last session", () => {
    const resetFiveHour = `{"primary":{"used_percent":95,"window_minutes":300,"resets_at":1791540000},"secondary":{"used_percent":60,"window_minutes":10080,"resets_at":1791900000}}`;
    const snapshot = summarize(session(tokenCount("2026-10-09T08:00:00Z", 1, 1, 0, resetFiveHour))).limits?.snapshot;
    expect(snapshot?.fiveHour).toEqual({ utilization: 0 });
    expect(snapshot?.sevenDay).toEqual({ utilization: 0.6, resetsAt: 1_791_900_000 });
    const flatSnapshot = summarize(session(tokenCount("2026-10-09T06:00:00Z", 1, 1, 0, `{"primary_used_percent":90,"secondary_used_percent":40}`))).limits?.snapshot;
    expect(flatSnapshot?.fiveHour).toEqual({ utilization: 0 });
    expect(flatSnapshot?.sevenDay).toEqual({ utilization: 0.4 });
  });

  it("has tokens but no limits for API-key sessions", () => {
    const usage = summarize(session(tokenCount("2026-10-09T10:00:00Z", 5, 5, 0, null)));
    expect(usage.limits).toBeUndefined();
    expect(totalTokens(periodTokens(usage.stats.today))).toBe(10);
    expect(topModel(usage.stats.today)).toBe(CODEX_DEFAULT_MODEL);
  });

  it("ignores malformed and unrelated lines", () => {
    const usage = summarize(
      session(
        `{"timestamp":"2026-10-09T10:00:00Z","type":"event_msg","payload":{"type":"token_count"`,
        `{"timestamp":"2026-10-09T10:00:00Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":null}}`,
        "not json",
        "",
      ),
    );
    expect(usage).toEqual({ stats: aggregateUsage([], now, "UTC") });
  });

  it("reads only session files touched this week, under CODEX_HOME or the profile", () => {
    const files = [
      { path: "C:\\x\\2026\\10\\09\\rollout-a.jsonl", modified: now },
      { path: "C:\\x\\2026\\10\\09\\rollout-b.jsonl", modified: at("2026-09-01T00:00:00Z") },
      { path: "C:\\x\\notes.txt", modified: now },
    ];
    expect(codexFilesToRead(files, now, "UTC").map((f) => f.path)).toEqual(["C:\\x\\2026\\10\\09\\rollout-a.jsonl"]);
    expect(codexSessionsRoot("C:\\Users\\ana", "D:\\codex")).toBe("D:\\codex\\sessions");
    expect(codexSessionsRoot("C:\\Users\\ana")).toBe("C:\\Users\\ana\\.codex\\sessions");
  });
});

describe("AIUsageSource and highlights", () => {
  it("follows Codex and otherwise stays on Claude Code", () => {
    expect(usageSourceFor("codex-cli")).toBe("codex");
    for (const provider of [undefined, "claude-cli", "gemini-cli", "anthropic", "openai", "gemini", "ollama"] as const) {
      expect(usageSourceFor(provider)).toBe("claudeCode");
    }
    expect(probesLimits("claudeCode")).toBe(true);
    expect(probesLimits("codex")).toBe(false);
  });

  it("names the source in the highlight", () => {
    const snapshot = { status: "allowed", fiveHour: { utilization: 0.9 }, sevenDay: { utilization: 0.2 } };
    expect(usageHighlights(snapshot, 0, "claudeUsage", "codex").map((h) => h.summary)).toEqual(["Codex usage 5h 90%"]);
    expect(usageHighlights(snapshot, 0).map((h) => h.summary)).toEqual(["Claude usage 5h 90%"]);
  });

  it("publishes one highlight per full window, expiring at its reset", () => {
    const now = 1_790_000_000;
    const reset = now + 3600;
    const highlights = usageHighlights({ fiveHour: { utilization: 1.02, resetsAt: reset }, sevenDay: { utilization: 0.5 } }, now);
    expect(highlights.map((h) => h.text)).toEqual(["5h 102%"]);
    expect(highlights[0]?.tone).toBe("danger");
    expect(highlights[0]?.summary).toBe("Claude usage 5h 102%");
    expect(highlights[0]?.expiresAt).toBe(reset);
    expect(usageHighlights({ fiveHour: { utilization: 0.95, resetsAt: now - 1 } }, now)).toEqual([]);
    const both = usageHighlights({ fiveHour: { utilization: 0.85 }, sevenDay: { utilization: 0.85 } }, now);
    expect((both[0]?.priority ?? 0) > (both[1]?.priority ?? 0)).toBe(true);
  });
});
