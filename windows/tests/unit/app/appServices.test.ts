// Port of LeetCodeAcceptanceTests and the runtime's own checks: AppServices
// built from the module list plus one module checks that every shared
// surface picks it up with no shared code, the way "Adding a module" in
// AGENTS.md promises.
import { beforeAll, describe, expect, it } from "vitest";
import { isLive, nextLiveChange } from "../../../src/app/liveActivity";
import { kitIssues } from "../../../src/core/kits/kitValidation";
import { BUNDLED_KITS } from "../../../src/core/kits/bundledKits";
import { kitDefaults, kitManifest } from "../../../src/core/kits/kitManifest";
import { setLookup } from "../../../src/core/localization/tr";
import { ModuleCatalog } from "../../../src/core/modules/moduleCatalog";
import { MODULE_IDS } from "../../../src/core/modules/moduleId";
import { moduleProvision, type ModuleProvision } from "../../../src/core/providers/moduleProvision";
import { ProvidedFocus } from "../../../src/core/providers/providedFocus";
import { ProviderSnapshot } from "../../../src/core/providers/providerSnapshot";
import { upcomingEvent } from "../../../src/core/planner/upcomingEvent";
import { MODULE_LIST } from "../../../src/modules/moduleList";
import { LeetCodeModule } from "../../support/leetCodeModule";
import { recordingModule, testApp } from "../../support/runtime";
import { switchLanguage } from "../../support/catalogs";
import { Observable } from "../../../src/app/store";

const NOW = 1_790_000_000;
/* The default kit's layout with LeetCode added as a tab. */
const WITH_LEETCODE = { "settings.modules.order": ["leetcode", "planner", "study"], "settings.modules.disabled": [] };

beforeAll(() => switchLanguage("en"));

describe("MODULE_LIST", () => {
  it("lists every Mac module once, in the Mac's order", () => {
    expect(MODULE_LIST.map((type) => type.descriptor.id)).toEqual([
      "spotify",
      "system",
      "claudeUsage",
      "planner",
      "claudeAsk",
      "focus",
      "study",
      "anki",
      "party",
      "closet",
      "schedule",
    ]);
  });

  it("knows every module and setting the bundled kits use", () => {
    const catalog = new ModuleCatalog(MODULE_LIST.map((type) => type.descriptor));
    for (const kit of BUNDLED_KITS.kits) expect(kitIssues(kit, catalog), kit.id).toEqual([]);
  });

  it("keeps the descriptors' words in the user's language", () => {
    const today = MODULE_LIST.find((type) => type.descriptor.id === MODULE_IDS.planner)?.descriptor;
    const closet = MODULE_LIST.find((type) => type.descriptor.id === MODULE_IDS.closet)?.descriptor;
    setLookup((key) => ({ Today: "Heute", "Your pet": "Dein Haustier" })[key]);
    expect(today?.title).toBe("Heute");
    expect(closet?.headerShortcut).toMatchObject({ key: "p", label: "Dein Haustier" });
    switchLanguage("en");
    expect(today?.title).toBe("Today");
  });
});

describe("AppServices", () => {
  it("creates every listed module, starts the enabled ones in the island, and none in Settings", async () => {
    const log: string[] = [];
    const types = [recordingModule("a", log), recordingModule("b", log)];
    const entries = { "settings.modules.order": ["b", "a"], "settings.modules.disabled": ["a"] };
    const island = await testApp({ moduleTypes: types, settingsEntries: entries });
    expect(log).toEqual(["create a", "create b", "start b"]);
    island.app.settings.update((settings) => {
      const modules = settings.modules.clone();
      modules.setEnabled("a", true);
      return { ...settings, modules };
    });
    expect(log.at(-1)).toBe("start a");
    expect(island.app.ticker).toBeDefined();

    log.length = 0;
    const settingsWindow = await testApp({ moduleTypes: types, settingsEntries: entries, role: "settings" });
    expect(log).toEqual(["create a", "create b"]);
    expect(settingsWindow.app.ticker).toBeUndefined();
    island.app.dispose();
    expect(log).toEqual(["create a", "create b", "stop b", "stop a"]);
  });

  it("keeps demo and snapshot runs off the user's files", async () => {
    const { app, host } = await testApp({ moduleTypes: MODULE_LIST, runMode: { isDemo: true, isSnapshot: false } });
    app.settings.update((settings) => ({ ...settings, themeID: "forest" }));
    await app.settings.flush();
    expect(host.calls.filter((call) => call.name.startsWith("storage"))).toEqual([]);
  });
});

describe("Adding a module", () => {
  it("plugs a module in with its own folder and one line in the list", async () => {
    const { app, clock } = await testApp({ moduleTypes: [...MODULE_LIST, LeetCodeModule], settingsEntries: WITH_LEETCODE }, NOW);
    const module = app.modules.instance(LeetCodeModule);
    expect(module?.store.state.isRunning).toBe(true);
    expect(app.settings.catalog.descriptor("leetcode").title).toBe("LeetCode");
    expect(app.settings.current.modules.tabs[0]).toBe("leetcode");

    /* Today and Plan my day see its task and goal; the ticker shows its line. */
    const snapshot = app.providers.snapshot.get();
    expect(snapshot.tasks.map((task) => [task.source, task.title, task.estimatedMinutes])).toEqual([["leetcode", "LeetCode: Two Sum", 20]]);
    /* The Timer shares its daily goal too, so only the module's own goal is checked. */
    expect(snapshot.progress.some((item) => item.source === "leetcode")).toBe(true);
    const lines: string[] = [];
    for (let turn = 0; turn < 4; turn++) {
      const shown = app.ticker?.state.item;
      lines.push(shown?.type === "highlight" ? shown.highlight.text : (shown?.type ?? "none"));
      app.ticker?.cycle();
    }
    expect(lines).toContain("1 problem left");

    /* Kits can list and configure it, and validation checks its settings. */
    const kit = kitManifest({
      id: "coding",
      name: "Coding",
      modules: [{ id: "leetcode", enabled: true }],
      summary: "Code every day.",
      symbol: "laptopcomputer",
      defaults: kitDefaults({ ticker: ["leetcode"], moduleSettings: { leetcode: { minutesPerProblem: 45, minutesPerProblme: 1 } } }),
    });
    expect(kitIssues(kit, app.settings.catalog).map((issue) => issue.kind)).toEqual(["unknownField"]);
    app.settings.kits.upsert(kit);
    app.settings.switchKit("coding");
    expect(module?.store.state.estimatedMinutes).toBe(45);

    /* What the user did lands in the activity log, and the ticker line goes. */
    clock.now += 60;
    module?.store.markSolved();
    const records = await app.activityLog.records("2026-09-21");
    expect(records.map((record) => [record.source, record.kind, record.subject])).toEqual([["leetcode", "problem.solved", "Two Sum"]]);
    expect(app.providers.snapshot.get().highlights).toEqual([]);
    app.dispose();
  });
});

describe("Live activity", () => {
  const snapshot = (provision: Partial<ModuleProvision>) => new ProviderSnapshot([{ module: "planner", provision: moduleProvision(provision) }]);

  it("is live while a clock runs, music plays or a meeting starts within five minutes", () => {
    expect(isLive(ProviderSnapshot.empty, NOW)).toBe(false);
    expect(isLive(snapshot({ isPlaying: true }), NOW)).toBe(true);
    const focus = new ProvidedFocus({ source: "focus", phase: "focus", clock: { kind: "countdown", endsAt: NOW + 60 }, phaseLength: 1500 });
    expect(isLive(snapshot({ focus }), NOW)).toBe(true);
    const meeting = upcomingEvent({ id: "m", title: "Standup", start: NOW + 600, end: NOW + 1500 });
    const later = snapshot({ events: [meeting] });
    expect(isLive(later, NOW)).toBe(false);
    expect(nextLiveChange(later, NOW)).toBe(NOW + 300);
    expect(isLive(later, NOW + 300)).toBe(true);
    expect(nextLiveChange(later, NOW + 300)).toBe(NOW + 600);
    expect(isLive(later, NOW + 600)).toBe(false);
  });

  it("drives the ticker's live flag and wakes it when a meeting comes close", async () => {
    const provision = new Observable<ModuleProvision>(moduleProvision());
    const planner = recordingModule("planner", [], provision);
    const { app, clock, alarm } = await testApp({ moduleTypes: [planner], settingsEntries: { "settings.modules.order": ["planner"] } }, NOW);
    expect(app.ticker?.state.live).toBe(false);
    provision.set(moduleProvision({ events: [upcomingEvent({ id: "m", title: "Standup", start: NOW + 600, end: NOW + 1500 })] }));
    expect(app.ticker?.state.live).toBe(false);
    /* The countdown wakes it each minute; by the time the meeting is five minutes out it is live. */
    while ((alarm()?.at ?? Infinity) <= NOW + 300) {
      clock.now = alarm()?.at ?? clock.now;
      alarm()?.fire();
    }
    expect(clock.now).toBe(NOW + 300);
    expect(app.ticker?.state.live).toBe(true);
    expect(app.ticker?.state.item?.type).toBe("meeting");
  });
});
