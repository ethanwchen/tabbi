import { describe, expect, it } from "vitest";
import { MODULE_IDS } from "../../../src/core/modules/moduleId";
import { DEMO_RUN_MODE, LIVE_RUN_MODE } from "../../../src/core/modules/runMode";
import { mockHost } from "../../../src/host/mock";
import { ClaudeUsageModule } from "../../../src/modules/claudeUsage/claudeUsageModule";
import { type ClaudeUsageStore, demoWeeklyReset, LIMITS_DOCUMENT, USAGE_FOLDER } from "../../../src/modules/claudeUsage/claudeUsageStore";
import { testApp } from "../../support/runtime";

/* Port of the ClaudeUsageStore tests, over the mock host's seeded logs. */

/* 2026-10-14T12:00:00Z, a Wednesday. */
const NOW = 1_791_979_200;
const tick = () => new Promise<void>((resolve) => setTimeout(resolve, 0));
const settle = async (times = 6) => {
  for (let i = 0; i < times; i++) await tick();
};

function assistantLine(id: string, timestamp: string, tokens: number, model = "claude-opus-4-5-20251101"): string {
  return `{"type":"assistant","message":{"model":"${model}","id":"${id}","role":"assistant","content":[{"type":"text","text":"hi"}],"usage":{"input_tokens":${tokens},"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}},"timestamp":"${timestamp}","sessionId":"s"}`;
}

function codexLine(timestamp: string, total: number, usedPercent?: number): string {
  const limits = usedPercent === undefined ? "" : `,"rate_limits":{"primary":{"used_percent":${usedPercent},"resets_in_seconds":3600},"secondary":{"used_percent":12}}`;
  return `{"timestamp":"${timestamp}","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":${total},"cached_input_tokens":0,"output_tokens":0}}${limits}}}`;
}

async function liveStore(seed: (host: ReturnType<typeof mockHost>) => void, host = mockHost(undefined, { aiLogModified: NOW - 60 })) {
  seed(host);
  const { app } = await testApp({ moduleTypes: [ClaudeUsageModule], runMode: LIVE_RUN_MODE, host }, NOW);
  const module = app.modules.get(MODULE_IDS.claudeUsage) as { store: ClaudeUsageStore } | undefined;
  if (!module) throw new Error("no module");
  await settle();
  return { store: module.store, host };
}

describe("ClaudeUsageStore in a demo run", () => {
  it("shows sample limits and stats and a highlight-free provision at 76%", async () => {
    const { app } = await testApp({ moduleTypes: [ClaudeUsageModule], runMode: DEMO_RUN_MODE }, NOW);
    const module = app.modules.get(MODULE_IDS.claudeUsage) as { store: ClaudeUsageStore } | undefined;
    expect(module).toBeDefined();
    if (!module) return;
    const state = module.store.state;
    expect(state.cliStatus).toBe("available");
    expect(state.limits?.snapshot.fiveHour?.utilization).toBe(0.42);
    expect(state.stats?.today.models[0]?.model).toBe("claude-opus-5-5");
    expect(app.providers.snapshot.get().highlights).toEqual([]);
  });

  it("resets the demo weekly window on the next Thursday at 9:00", () => {
    const reset = demoWeeklyReset(NOW, "UTC");
    const date = new Date(reset * 1000);
    expect(date.getUTCDay()).toBe(4);
    expect(date.getUTCHours()).toBe(9);
    expect(reset).toBeGreaterThan(NOW + 24 * 3600);
  });
});

describe("ClaudeUsageStore in a live run", () => {
  it("reads today's and the week's Claude Code usage through the host and keeps the scan index", async () => {
    const { store, host } = await liveStore((host) => {
      host.aiLogFiles.set(
        "claude:C:\\Users\\me\\.claude\\projects\\a\\one.jsonl",
        [assistantLine("m1", "2026-10-14T10:00:00Z", 100), assistantLine("m1", "2026-10-14T10:00:00Z", 100), assistantLine("m2", "2026-10-10T10:00:00Z", 5)].join("\n") + "\n",
      );
      host.aiLogFiles.set("claude:C:\\Users\\me\\.claude\\projects\\b\\old.jsonl", assistantLine("m3", "2026-09-01T10:00:00Z", 999) + "\n");
    });
    expect(store.state.source).toBe("claudeCode");
    expect(store.state.cliStatus).toBe("missing");
    expect(store.state.limits).toBeUndefined();
    expect(store.state.stats?.today.models).toEqual([{ model: "claude-opus-4-5-20251101", tokens: { input: 100, output: 0, cacheRead: 0, cacheCreation: 0 }, messages: 1 }]);
    expect(store.state.stats?.lastSevenDays.models[0]?.messages).toBe(2);
    expect(host.documents.has("cache:ClaudeUsage/scan-index")).toBe(true);
    expect(host.calls.filter((call) => call.name === "aiLogRead")).toHaveLength(2);

    /* A refresh re-reads only what was appended. */
    store.refresh();
    await settle();
    expect(host.calls.filter((call) => call.name === "aiLogRead")).toHaveLength(2);
    expect(store.state.isFetching).toBe(false);
  });

  it("shows Codex's own limits and stats while Codex is the chosen AI, and switches back instantly", async () => {
    const { store } = await liveStore((host) => {
      host.aiLogFiles.set(
        "codex:C:\\Users\\me\\.codex\\sessions\\2026\\10\\14\\rollout.jsonl",
        [`{"type":"turn_context","payload":{"model":"gpt-5-codex"}}`, codexLine("2026-10-14T11:00:00Z", 1000), codexLine("2026-10-14T11:30:00Z", 1500, 86)].join("\n"),
      );
    });
    store.followSetup({ kind: "ready", provider: "codex-cli" });
    await settle();
    expect(store.state.source).toBe("codex");
    expect(store.state.limits?.snapshot.fiveHour).toEqual({ utilization: 0.86, resetsAt: Date.parse("2026-10-14T12:30:00Z") / 1000 });
    expect(store.state.limits?.snapshot.sevenDay?.utilization).toBe(0.12);
    expect(store.state.stats?.today.models[0]).toEqual({ model: "gpt-5-codex", tokens: { input: 1500, output: 0, cacheRead: 0, cacheCreation: 0 }, messages: 2 });
    store.followSetup({ kind: "ready", provider: "anthropic" });
    await settle();
    expect(store.state.source).toBe("claudeCode");
    expect(store.state.limits).toBeUndefined();
  });

  it("keeps a saved Claude limits snapshot in the module's folder and shows it on the next launch", async () => {
    const first = await liveStore(() => undefined);
    await first.store.saveClaudeLimits({ snapshot: { fiveHour: { utilization: 0.9, resetsAt: NOW + 600 } }, fetchedAt: NOW - 30 });
    const document = first.host.documents.get(`durable:${USAGE_FOLDER}/${LIMITS_DOCUMENT.replace(/\.json$/, "")}`);
    expect(document).toContain('"schemaVersion":1');
    const again = await liveStore(() => undefined, first.host);
    expect(again.store.state.limits?.snapshot.fiveHour?.utilization).toBe(0.9);
  });

  it("publishes a ticker highlight for a window above 80 percent", async () => {
    const host = mockHost();
    const { app } = await testApp({ moduleTypes: [ClaudeUsageModule], runMode: LIVE_RUN_MODE, host }, NOW);
    app.settings.update((settings) => {
      const modules = settings.modules.clone();
      modules.add(MODULE_IDS.claudeUsage);
      return { ...settings, modules };
    });
    const module = app.modules.get(MODULE_IDS.claudeUsage) as { store: ClaudeUsageStore } | undefined;
    if (!module) throw new Error("no module");
    await module.store.saveClaudeLimits({ snapshot: { fiveHour: { utilization: 0.86, resetsAt: NOW + 600 } }, fetchedAt: NOW });
    const highlights = app.providers.snapshot.get().highlights;
    expect(highlights.map((highlight) => highlight.text)).toEqual(["5h 86%"]);
    expect(highlights[0]?.summary).toBe("Claude usage 5h 86%");
  });
});
