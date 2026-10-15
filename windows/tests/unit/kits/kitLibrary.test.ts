import { describe, expect, it } from "vitest";
import { BUNDLED_KIT_FILES, BUNDLED_KITS, isBundledKit } from "../../../src/core/kits/bundledKits";
import {
  chosenAnswers,
  kitAccentModule,
  kitLayout,
  kitStarterTasks,
  selectingAnswer,
  type KitAnswers,
} from "../../../src/core/kits/kitApplication";
import {
  DEFAULT_KIT_ID,
  KitLibrary,
  RETIRED_KIT_IDS,
  authorKitID,
  importedKitID,
  isImportedKitID,
} from "../../../src/core/kits/kitLibrary";
import {
  kitAnswer,
  kitDefaults,
  kitManifest,
  kitModuleEntry,
  kitModuleIDs,
  kitModuleSettings,
  kitQuestion,
  type KitManifest,
} from "../../../src/core/kits/kitManifest";
import { decodeKit, firstExceededLimit, kitIssues } from "../../../src/core/kits/kitValidation";
import { ModuleCatalog } from "../../../src/core/modules/moduleCatalog";
import { MODULE_CATEGORIES, moduleDescriptor } from "../../../src/core/modules/moduleDescriptor";
import { appSettings, applyKit, resolvedKitTicker, settingsShowsPreview } from "../../../src/core/settings/appSettings";
import { settingPreviewKind } from "../../../src/core/settings/notchPreviewSettings";
import { BUILT_IN_TICKER_KINDS } from "../../../src/core/settings/tickerKind";
import { BUILT_IN_CATALOG, defaultTestLayout } from "../../support/builtInCatalog";

const answers = (entries: Record<string, string[]>): KitAnswers =>
  Object.fromEntries(Object.entries(entries).map(([question, picked]) => [question, new Set(picked)]));

function bundled(id: string): KitManifest {
  const kit = BUNDLED_KITS.get(id);
  if (!kit) throw new Error(`no bundled kit ${id}`);
  return kit;
}

const testKit = kitManifest({
  id: "test",
  name: "Test",
  summary: "",
  symbol: "star",
  modules: [kitModuleEntry("planner"), kitModuleEntry("leetcode"), kitModuleEntry("spotify"), kitModuleEntry("system", false)],
  onboarding: [
    kitQuestion({
      id: "music",
      prompt: "Music?",
      options: [
        kitAnswer({ id: "yes", label: "Yes", tasks: ["Make a playlist"] }),
        kitAnswer({ id: "no", label: "No", disables: ["spotify"] }),
      ],
    }),
    kitQuestion({
      id: "extras",
      prompt: "Extras?",
      allowsMultiple: true,
      options: [
        kitAnswer({ id: "stats", label: "Stats", enables: ["system"], tasks: ["Check CPU", " "] }),
        kitAnswer({ id: "claude", label: "Claude", enables: ["claudeAsk"], tasks: ["Make a playlist"] }),
      ],
    }),
  ],
  starterTasks: ["Plan the day"],
});

describe("kit application", () => {
  it("follows kit order and parks other modules switched off", () => {
    const layout = kitLayout(testKit, BUILT_IN_CATALOG);
    expect(layout.order).toEqual([
      "planner",
      "spotify",
      "system",
      "claudeUsage",
      "claudeAsk",
      "focus",
      "study",
      "anki",
      "party",
      "closet",
    ]);
    expect(layout.enabled).toEqual(["planner", "spotify"]);
  });

  it("switches modules on and off from the answers", () => {
    const layout = kitLayout(testKit, BUILT_IN_CATALOG, answers({ music: ["no"], extras: ["stats", "claude"] }));
    expect(layout.enabled).toEqual(["planner", "system", "claudeAsk"]);
  });

  it("uses only the first picked answer of a single-choice question", () => {
    expect(chosenAnswers(testKit, answers({ music: ["yes", "no"] })).map((answer) => answer.id)).toEqual(["yes"]);
  });

  it("replaces the pick of a single-choice question", () => {
    const music = testKit.onboarding[0];
    expect(music).toBeDefined();
    if (!music) return;
    expect(selectingAnswer(music, "yes", new Set())).toEqual(new Set(["yes"]));
    expect(selectingAnswer(music, "no", new Set(["yes"]))).toEqual(new Set(["no"]));
    expect(selectingAnswer(music, "no", new Set(["no"]))).toEqual(new Set());
    expect(selectingAnswer(music, "maybe", new Set(["yes"]))).toEqual(new Set(["yes"]));
  });

  it("toggles a multiple-choice answer", () => {
    const extras = testKit.onboarding[1];
    expect(extras).toBeDefined();
    if (!extras) return;
    expect(selectingAnswer(extras, "claude", new Set(["stats"]))).toEqual(new Set(["stats", "claude"]));
    expect(selectingAnswer(extras, "stats", new Set(["stats", "claude"]))).toEqual(new Set(["claude"]));
  });

  it("merges starter tasks without blanks or duplicates", () => {
    expect(kitStarterTasks(testKit, answers({ music: ["yes"], extras: ["stats", "claude"] }))).toEqual([
      "Plan the day",
      "Make a playlist",
      "Check CPU",
    ]);
  });

  it("lays out against the given catalog", () => {
    const accent = { red: 0, green: 0, blue: 0 };
    const catalog = new ModuleCatalog([
      moduleDescriptor({ id: "leetcode", title: "LeetCode", symbol: "chevron.left", category: MODULE_CATEGORIES.study, accent }),
      moduleDescriptor({ id: "planner", title: "Today", symbol: "checklist", category: MODULE_CATEGORIES.productivity, accent }),
    ]);
    expect(kitLayout(testKit, catalog).order).toEqual(["planner", "leetcode"]);
  });

  it("falls back to the first enabled tab for the accent", () => {
    expect(kitAccentModule(testKit, BUILT_IN_CATALOG)).toBe("planner");
    expect(kitAccentModule({ ...testKit, accent: "spotify" }, BUILT_IN_CATALOG)).toBe("spotify");
    const chess = { ...testKit, accent: "chess" };
    expect(kitAccentModule(chess, BUILT_IN_CATALOG)).toBe("planner");
    expect(kitIssues(chess, BUILT_IN_CATALOG)).toEqual([
      { kind: "unknownModule", id: "leetcode" },
      { kind: "unknownModule", id: "chess" },
    ]);
  });

  it("lists unknown values once", () => {
    const kit: KitManifest = {
      ...testKit,
      modules: [...testKit.modules, kitModuleEntry("planner")],
      defaults: kitDefaults({ ticker: ["weather"] }),
      onboarding: [
        ...testKit.onboarding,
        kitQuestion({ id: "music", prompt: "Again?", options: [kitAnswer({ id: "x", label: "X", enables: ["chess"] })] }),
      ],
    };
    expect(kitIssues(kit, BUILT_IN_CATALOG)).toEqual([
      { kind: "unknownModule", id: "leetcode" },
      { kind: "duplicateModule", id: "planner" },
      { kind: "unknownModule", id: "chess" },
      { kind: "unknownTickerKind", value: "weather" },
      { kind: "duplicateQuestion", id: "music" },
    ]);
  });

  it("skips modules the edition leaves out quietly", () => {
    const catalog = BUILT_IN_CATALOG.excluding(["claudeUsage", "party"]);
    const kit = decodeKit(`{"formatVersion": 1, "id": "k", "name": "K", "modules": ["planner", "party"],
      "defaults": {"ticker": ["party", "claudeUsage"], "moduleSettings": {"party": {}}}}`);
    expect(kit.ok && kitIssues(kit.kit, catalog)).toEqual([]);
  });
});

describe("KitLibrary", () => {
  it("loads every bundled kit file under its own name", () => {
    expect(BUNDLED_KIT_FILES.length).toBeGreaterThan(0);
    for (const file of BUNDLED_KIT_FILES) {
      const result = decodeKit(file.text);
      expect(result.ok, file.name).toBe(true);
      if (!result.ok) continue;
      expect(result.kit.id).toBe(file.name);
      expect(result.kit.summary).not.toBe("");
      expect(result.kit.pickerOrder, `${result.kit.id} needs a pickerOrder`).toBeDefined();
    }
    expect(BUNDLED_KITS.kits.length).toBe(BUNDLED_KIT_FILES.length);
  });

  it("puts bundled kits in picker order", () => {
    expect(BUNDLED_KITS.ids).toEqual(["essentials", "medicine"]);
    expect(BUNDLED_KITS.kits[0]?.id).toBe(DEFAULT_KIT_ID);
    const orders = BUNDLED_KITS.kits.map((kit) => kit.pickerOrder);
    expect(new Set(orders).size).toBe(orders.length);
  });

  it("orders kits without a picker order last, by id", () => {
    const file = (id: string, order?: number) => ({
      name: id,
      text: JSON.stringify({ formatVersion: 1, id, name: id, modules: ["planner"], pickerOrder: order }),
    });
    expect(KitLibrary.fromBundledFiles([file("zeta"), file("beta", 2), file("alpha"), file("gamma", 1)]).ids).toEqual([
      "gamma",
      "beta",
      "alpha",
      "zeta",
    ]);
    expect(KitLibrary.fromBundledFiles([file("ok", 1), { name: "broken", text: "not json" }]).ids).toEqual(["ok"]);
  });

  it("reads a picker order and leaves it optional", () => {
    const ordered = decodeKit(`{"formatVersion": 1, "id": "k", "name": "K", "pickerOrder": 4, "modules": ["planner"]}`);
    expect(ordered.ok && ordered.kit.pickerOrder).toBe(4);
    expect(ordered.ok && ordered.kit.unknownFields).toEqual([]);
    const unordered = decodeKit(`{"formatVersion": 1, "id": "k", "name": "K", "modules": ["planner"]}`);
    expect(unordered.ok && unordered.kit.pickerOrder).toBeUndefined();
  });

  it("gives bundled kits distinct accents", () => {
    const accents = BUNDLED_KITS.kits.map((kit) => kitAccentModule(kit, BUILT_IN_CATALOG));
    expect(new Set(accents).size).toBe(BUNDLED_KITS.ids.length);
  });

  it("makes Essentials the default with the four tabs and the paw", () => {
    const kit = bundled(DEFAULT_KIT_ID);
    expect(kit.id).toBe("essentials");
    expect(kit.name).toBe("Essentials");
    expect(kitLayout(kit, BUILT_IN_CATALOG).enabled).toEqual(["study", "planner", "spotify", "claudeAsk", "closet"]);
    expect(kitIssues(kit, BUILT_IN_CATALOG)).toEqual([]);
    /* Essentials keeps the user's focus sound and starts the study timer on a plain countdown. */
    expect(kitModuleSettings(kit.defaults, "focus")).toBeUndefined();
    expect(kitModuleSettings(kit.defaults, "study")).toMatchObject({ method: "timer" });
  });

  it("keeps usage stats off the closed panel in every bundled kit", () => {
    for (const kit of BUNDLED_KITS.kits) {
      const kinds = resolvedKitTicker(kit.defaults, BUILT_IN_CATALOG);
      expect(kinds, `${kit.id} lists its previews`).toBeDefined();
      expect(kinds).toEqual(new Set(BUILT_IN_TICKER_KINDS));
      expect(kinds?.has("claudeUsage")).toBe(false);
      expect(kinds?.has("system")).toBe(false);

      /* Adding Claude Usage later keeps its preview off until the user turns it on. */
      let settings = applyKit(appSettings({ modules: defaultTestLayout() }), kit, BUILT_IN_CATALOG);
      const modules = settings.modules.clone();
      modules.setEnabled("claudeUsage", true);
      settings = { ...settings, modules };
      expect(settingsShowsPreview(settings, "claudeUsage")).toBe(false);
      settings = { ...settings, notchPreview: settingPreviewKind(settings.notchPreview, "claudeUsage", true) };
      expect(settingsShowsPreview(settings, "claudeUsage")).toBe(true);
    }
  });

  it("lets Essentials answers add tasks but never tabs", () => {
    const kit = bundled("essentials");
    const every = answers({ day: kit.onboarding.flatMap((question) => question.options.map((option) => option.id)) });
    expect(kitLayout(kit, BUILT_IN_CATALOG, every).equals(kitLayout(kit, BUILT_IN_CATALOG))).toBe(true);
    expect(kitStarterTasks(kit, answers({ day: ["classes"] }))).toContain("Review today's lecture notes");
  });

  it("parks modules outside the kit, switched off, for the library", () => {
    const layout = kitLayout(bundled("essentials"), BUILT_IN_CATALOG);
    expect(new Set(layout.order)).toEqual(new Set(BUILT_IN_CATALOG.ids));
    expect(layout.order.slice(5).filter((id) => layout.isEnabled(id))).toEqual([]);
  });

  it("uses only known values in bundled kits", () => {
    for (const kit of BUNDLED_KITS.kits) expect(kitIssues(kit, BUILT_IN_CATALOG), kit.id).toEqual([]);
  });

  it("starts Med School on the study timer with Anki-first methods", () => {
    const kit = bundled("medicine");
    expect(kit.name).toBe("Med School");
    expect(kitModuleIDs(kit)).toEqual(["study", "planner", "anki", "spotify", "claudeAsk", "closet"]);
    expect(kitModuleSettings(kit.defaults, "study")).toMatchObject({ method: "pomodoro" });
    const study = kitModuleSettings(kit.defaults, "study");
    expect(study && typeof study === "object" && !Array.isArray(study) && study.methods).toContain("ankiSprint");
    expect(kitModuleSettings(kit.defaults, "closet")).toMatchObject({ pet: { breed: "orangeTabby" } });
    expect(kitStarterTasks(kit, answers({ stage: ["preclinical"] }))[0]).toBe("Clear today's Anki reviews");
  });

  it("makes Med School Essentials plus Anki", () => {
    const medicine = kitLayout(bundled("medicine"), BUILT_IN_CATALOG);
    const essentials = kitLayout(bundled("essentials"), BUILT_IN_CATALOG);
    expect(medicine.enabled).toEqual(["study", "planner", "anki", "spotify", "claudeAsk", "closet"]);
    expect(medicine.enabled.filter((id) => id !== "anki")).toEqual(essentials.enabled);
    expect(kitLayout(bundled("medicine"), BUILT_IN_CATALOG, answers({ anki: ["no"] })).enabled).toEqual(
      essentials.enabled,
    );
  });

  it("falls back to the default kit when one is missing", () => {
    expect(BUNDLED_KITS.kit("removed")?.id).toBe(DEFAULT_KIT_ID);
    expect(BUNDLED_KITS.kit(undefined)?.id).toBe(DEFAULT_KIT_ID);
    expect(BUNDLED_KITS.kit("medicine")?.id).toBe("medicine");
    expect(BUNDLED_KITS.kit("student")?.id).toBe(DEFAULT_KIT_ID);
  });

  it("replaces in place on upsert and drops duplicate ids", () => {
    const one = kitManifest({ id: "one", name: "One", summary: "", symbol: "1.circle", modules: [kitModuleEntry("planner")] });
    const two = kitManifest({ id: "two", name: "Two", summary: "", symbol: "2.circle", modules: [kitModuleEntry("system")] });
    const library = new KitLibrary([one, two, one]);
    expect(library.ids).toEqual(["one", "two"]);
    library.upsert({ ...one, name: "Uno" });
    expect(library.kits.map((kit) => kit.name)).toEqual(["Uno", "Two"]);
  });

  it("keeps bundled kits within the caps", () => {
    for (const kit of BUNDLED_KITS.kits) expect(firstExceededLimit(kit), kit.id).toBeUndefined();
  });

  it("keeps retired ids out of the bundle and points them at a bundled kit", () => {
    for (const [retired, replacement] of Object.entries(RETIRED_KIT_IDS)) {
      expect(BUNDLED_KITS.get(retired)).toBeUndefined();
      expect(BUNDLED_KITS.get(replacement)).toBeDefined();
    }
  });

  it("namespaces imported kit ids", () => {
    expect(importedKitID("deep-work")).toBe("imported.deep-work");
    expect(importedKitID("imported.deep-work")).toBe("imported.deep-work");
    expect(isImportedKitID("deep-work")).toBe(false);
    expect(authorKitID("imported.deep-work")).toBe("deep-work");
    expect(isBundledKit("medicine")).toBe(true);
    expect(isBundledKit("imported.medicine")).toBe(false);
  });
});
