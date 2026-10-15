import { beforeEach, describe, expect, it } from "vitest";
import { BUNDLED_KITS } from "../../../src/core/kits/bundledKits";
import { kitLayout, type KitAnswers } from "../../../src/core/kits/kitApplication";
import { DEFAULT_KIT_ID, KitLibrary, importedKitID } from "../../../src/core/kits/kitLibrary";
import { kitManifest, kitModuleEntry, type KitManifest } from "../../../src/core/kits/kitManifest";
import { decodeKit } from "../../../src/core/kits/kitValidation";
import { ModuleCatalog } from "../../../src/core/modules/moduleCatalog";
import { InMemoryDefaults, defaultsString } from "../../../src/core/persistence/defaults";
import { TABBI_EDITION } from "../../../src/core/editions/bundledEditions";
import {
  appSettings,
  applyKit,
  defaultThemeForKit,
  kitState,
  resetGeneral,
  settingsCleanedName,
  settingsEqual,
  settingsShowsPreview,
  usesGeneralDefaults,
  usesKitDefaults,
  withClaudePath,
  withKitState,
  type AppSettings,
} from "../../../src/core/settings/appSettings";
import { HOTKEY_MODIFIERS } from "../../../src/core/settings/hotkey";
import {
  DEFAULT_NOTCH_PREVIEW,
  previewKindEnabled,
  previewShows,
  settingPreviewKind,
  tickerIntervalTitle,
  TICKER_INTERVALS,
} from "../../../src/core/settings/notchPreviewSettings";
import { SettingsRepository } from "../../../src/core/settings/settingsRepository";
import {
  CURRENT_SETTINGS_VERSION,
  SETTINGS_VERSION_KEY,
  migrateSettings,
  storedModuleOrder,
  storedSettingsVersion,
  type SettingsMigration,
} from "../../../src/core/settings/settingsSchema";
import { DEFAULT_THEME_ID } from "../../../src/core/settings/themeIds";
import { allTickerKinds, type TickerKind } from "../../../src/core/settings/tickerKind";
import { BUILT_IN_CATALOG, builtInLayout, defaultTestLayout } from "../../support/builtInCatalog";

const { command, option, shift } = HOTKEY_MODIFIERS;

function bundled(id: string): KitManifest {
  const kit = BUNDLED_KITS.get(id);
  if (!kit) throw new Error(`no bundled kit ${id}`);
  return kit;
}

const answers = (entries: Record<string, string[]>): KitAnswers =>
  Object.fromEntries(Object.entries(entries).map(([question, picked]) => [question, new Set(picked)]));

function repository(
  defaults: InMemoryDefaults,
  options: { kits?: KitLibrary; defaultKitID?: string; catalog?: ModuleCatalog } = {},
): SettingsRepository {
  return new SettingsRepository(
    defaults,
    options.catalog ?? BUILT_IN_CATALOG,
    options.kits ?? BUNDLED_KITS,
    options.defaultKitID ?? DEFAULT_KIT_ID,
  );
}

/* AppSettings.default in the Swift tests: the classic five tabs. */
function testSettings(overrides: Partial<AppSettings> = {}): AppSettings {
  return appSettings({ modules: defaultTestLayout(), ...overrides });
}

/* The built-in catalog's kinds the closed-panel preview may show. */
function previewKinds(settings: AppSettings): Set<TickerKind> {
  return new Set(allTickerKinds(BUILT_IN_CATALOG).filter((kind) => settingsShowsPreview(settings, kind)));
}

function withModules(settings: AppSettings, change: (layout: ReturnType<typeof defaultTestLayout>) => void): AppSettings {
  const modules = settings.modules.clone();
  change(modules);
  return { ...settings, modules };
}

let defaults: InMemoryDefaults;
beforeEach(() => {
  defaults = new InMemoryDefaults();
});

describe("SettingsRepository", () => {
  it("yields defaults from an empty store, on the default kit's tabs", () => {
    const settings = repository(defaults).load();
    const expected = { ...testSettings(), modules: kitLayout(bundled(DEFAULT_KIT_ID), BUILT_IN_CATALOG) };
    expect(settingsEqual(settings, expected)).toBe(true);
    expect(settings.modules.enabled).toEqual(["study", "planner", "spotify", "claudeAsk", "closet"]);
    expect(settings.openOnHover).toBe(false);
    expect(settings.hapticsEnabled).toBe(true);
    expect(settings.celebrationSoundEnabled).toBe(true);
    expect(settings.weeklyRecapEnabled).toBe(true);
    expect(settings.hotkey).toEqual({ keyCode: 49, modifiers: 3 });
    expect(settings.preferredDisplay).toEqual({ kind: "builtIn" });
    expect(settings.showOnExternalDisplays).toBe(true);
    expect(settings.hideInFullscreen).toBe(true);
    expect(settings.hideFromScreenCapture).toBe(false);
    expect(settings.hideInMissionControl).toBe(false);
    expect(settings.notchMode).toBe("always");
    expect(settings.panelSize).toBe("regular");
    expect(settings.motionPace).toBe("smooth");
    expect(settings.notchPreview.isEnabled).toBe(true);
    expect(settings.notchPreview.disabledKinds.size).toBe(0);
    expect(settings.notchPreview.interval).toBe(8);
    expect(settings.displayName).toBe("");
    expect(settingsCleanedName(settings)).toBeUndefined();
  });

  it("keeps the name as typed and cleans it for use", () => {
    let settings = testSettings({ displayName: "  Ada\u200B King, Countess of Lovelace " });
    expect(settings.displayName).toBe("  Ada\u200B King, Countess of Lovelace ");
    expect(settingsCleanedName(settings)).toBe("Ada King, Countess of Lo");
    settings = { ...settings, displayName: " \n " };
    expect(settingsCleanedName(settings)).toBeUndefined();
  });

  it("round-trips every field", () => {
    const modules = builtInLayout(["claudeAsk", "planner"]);
    modules.setEnabled("spotify", false);
    const settings = appSettings({
      displayName: "  Ada ",
      kitID: "medicine",
      hasChosenKit: true,
      kitAnswers: answers({ stage: ["clinical"], anki: ["yes", "no"] }),
      modules,
      openOnHover: true,
      hapticsEnabled: false,
      celebrationSoundEnabled: false,
      weeklyRecapEnabled: false,
      catWisdomEnabled: false,
      launchAtLogin: true,
      hotkey: { keyCode: 40, modifiers: command | shift },
      claudePathOverride: "C:\\Tools\\claude.exe",
      preferredDisplay: { kind: "specific", id: 5 },
      showOnExternalDisplays: false,
      hideInFullscreen: false,
      hideFromScreenCapture: true,
      hideInMissionControl: true,
      notchMode: "hover",
      panelSize: "large",
      motionPace: "instant",
      notchPreview: { isEnabled: false, disabledKinds: new Set(["tasks", "claudeUsage"]), interval: 12 },
      themeID: "sakura",
      ai: { provider: "ollama", models: { ollama: "llama3" }, consented: new Set(["ollama", "anthropic"]) },
    });
    const repo = repository(defaults);
    repo.save(settings);
    expect(settingsEqual(repo.load(), settings)).toBe(true);
  });

  it("stores values in the Mac's shape", () => {
    repository(defaults).save(
      testSettings({ kitAnswers: answers({ anki: ["yes", "no"] }), notchPreview: { ...DEFAULT_NOTCH_PREVIEW, disabledKinds: new Set(["tasks", "focus"]) } }),
    );
    expect(defaults.get("settings.hotkey")).toBe(`{"keyCode":49,"modifiers":3}`);
    expect(defaults.get("settings.kit.answers")).toEqual({ anki: ["no", "yes"] });
    expect(defaults.get("settings.preview.disabledKinds")).toEqual(["focus", "tasks"]);
    expect(defaults.get("settings.preferredDisplay")).toBe("builtIn");
    expect(defaults.get("settings.notchMode")).toBe("always");
    expect(defaults.get("settings.preview.interval")).toBe(8);
    expect(defaults.get(SETTINGS_VERSION_KEY)).toBe(CURRENT_SETTINGS_VERSION);
  });

  it("removes a cleared path override", () => {
    const repo = repository(defaults);
    repo.save(testSettings({ claudePathOverride: "/opt/claude" }));
    let settings = repo.load();
    expect(settings.claudePathOverride).toBe("/opt/claude");
    settings = withClaudePath(settings, "   ");
    expect(settings.claudePathOverride).toBeUndefined();
    repo.save(settings);
    expect(repo.load().claudePathOverride).toBeUndefined();
    expect(defaults.get("settings.claudePathOverride")).toBeUndefined();
  });

  it("trims a path override", () => {
    expect(testSettings({ claudePathOverride: " C:\\bin\\claude.exe " }).claudePathOverride).toBe("C:\\bin\\claude.exe");
  });

  it("falls back value by value from malformed data", () => {
    defaults.set("settings.openOnHover", "yes please");
    defaults.set("settings.hotkey", "garbage");
    defaults.set("settings.preferredDisplay", "screen:nope");
    defaults.set("settings.hapticsEnabled", false);
    defaults.set("settings.celebrationSoundEnabled", "loud");
    defaults.set("settings.weeklyRecapEnabled", "Sundays");
    defaults.set("settings.notchMode", "sometimes");
    defaults.set("settings.panelSize", "huge");
    defaults.set("settings.motionPace", "bouncy");
    const settings = repository(defaults).load();
    expect(settings.panelSize).toBe("regular");
    expect(settings.motionPace).toBe("smooth");
    expect(settings.notchMode).toBe("always");
    expect(settings.openOnHover).toBe(false);
    expect(settings.hotkey).toEqual({ keyCode: 49, modifiers: 3 });
    expect(settings.preferredDisplay).toEqual({ kind: "builtIn" });
    expect(settings.hapticsEnabled).toBe(false);
    expect(settings.celebrationSoundEnabled).toBe(true);
    expect(settings.weeklyRecapEnabled).toBe(true);
  });

  it("drops a saved hotkey that isn't valid", () => {
    defaults.set("settings.hotkey", `{"keyCode":0,"modifiers":4}`);
    expect(repository(defaults).load().hotkey).toEqual({ keyCode: 49, modifiers: 3 });
  });

  it("starts modules missing from the saved order switched off", () => {
    defaults.set("settings.modules.order", ["claudeAsk", "system", "spotify", "claudeUsage"]);
    defaults.set("settings.modules.disabled", ["system"]);
    const layout = repository(defaults).load().modules;
    expect(layout.enabled).toEqual(["claudeAsk", "spotify", "claudeUsage"]);
    expect(layout.order.slice(-6)).toEqual(["planner", "focus", "study", "anki", "party", "closet"]);
  });

  it("uses the default kit's layout on first run", () => {
    const settings = repository(defaults, { defaultKitID: "medicine" }).load();
    expect(settings.kitID).toBe("medicine");
    expect(settings.modules.equals(kitLayout(bundled("medicine"), BUILT_IN_CATALOG))).toBe(true);
    expect(settings.modules.enabled[0]).toBe("study");
  });

  it("shows the Essentials tabs on a fresh install of Tabbi", () => {
    const settings = repository(defaults, { defaultKitID: TABBI_EDITION.defaultKitID }).load();
    expect(settings.kitID).toBe("essentials");
    expect(settings.modules.enabled).toEqual(["study", "planner", "spotify", "claudeAsk", "closet"]);
    expect(new Set(settings.modules.available)).toEqual(
      new Set(BUILT_IN_CATALOG.ids.filter((id) => !settings.modules.enabled.includes(id))),
    );
  });

  it("prefers a saved layout over the kit's", () => {
    const repo = repository(defaults, { defaultKitID: "medicine" });
    repo.save(withModules(repo.load(), (layout) => layout.setEnabled("system", true)));
    const reloaded = repo.load();
    expect(reloaded.kitID).toBe("medicine");
    expect(reloaded.modules.isEnabled("system")).toBe(true);
  });

  it("has not chosen a kit on first run until one is applied", () => {
    const repo = repository(defaults, { defaultKitID: "medicine" });
    let settings = repo.load();
    expect(settings.hasChosenKit).toBe(false);
    settings = { ...settings, openOnHover: true };
    repo.save(settings);
    expect(repo.load().hasChosenKit).toBe(false);
    settings = applyKit(settings, bundled("essentials"), BUILT_IN_CATALOG);
    repo.save(settings);
    const reloaded = repo.load();
    expect(reloaded.hasChosenKit).toBe(true);
    expect(reloaded.kitID).toBe("essentials");
  });

  it("counts layouts saved before kits existed as chosen", () => {
    defaults.set("settings.modules.order", ["spotify", "system", "claudeUsage", "planner", "claudeAsk"]);
    expect(repository(defaults).load().hasChosenKit).toBe(true);
  });

  it("falls back to the default kit for an unknown saved kit", () => {
    defaults.set("settings.kit", "removed-import");
    const settings = repository(defaults).load();
    expect(settings.kitID).toBe(DEFAULT_KIT_ID);
    expect(settings.modules.equals(kitLayout(bundled(DEFAULT_KIT_ID), BUILT_IN_CATALOG))).toBe(true);
  });

  it("replaces the layout when applying a kit and keeps other preferences", () => {
    const medicine = bundled("medicine");
    let settings = withModules(testSettings({ openOnHover: true }), (layout) => layout.setEnabled("spotify", false));
    settings = applyKit(settings, medicine, BUILT_IN_CATALOG, answers({ anki: ["yes"] }));
    expect(settings.kitID).toBe("medicine");
    expect(settings.modules.equals(kitLayout(medicine, BUILT_IN_CATALOG, answers({ anki: ["yes"] })))).toBe(true);
    expect(settings.modules.isEnabled("anki")).toBe(true);
    expect(settings.modules.isEnabled("spotify")).toBe(true);
    expect(settings.openOnHover).toBe(true);
    expect(settings.hasChosenKit).toBe(true);
  });

  it("checks a reset against the saved onboarding answers", () => {
    const medicine = bundled("medicine");
    let settings = applyKit(testSettings(), medicine, BUILT_IN_CATALOG, answers({ anki: ["no"] }));
    expect(settings.kitAnswers).toEqual(answers({ anki: ["no"] }));
    expect(settings.modules.isEnabled("anki")).toBe(false);
    expect(usesKitDefaults(settings, medicine, BUILT_IN_CATALOG)).toBe(true);
    settings = withModules(settings, (layout) => layout.setEnabled("anki", true));
    expect(usesKitDefaults(settings, medicine, BUILT_IN_CATALOG)).toBe(false);
  });

  it("clears old answers when applying a kit without answers", () => {
    let settings = applyKit(testSettings(), bundled("medicine"), BUILT_IN_CATALOG, answers({ anki: ["no"] }));
    settings = applyKit(settings, bundled("essentials"), BUILT_IN_CATALOG);
    expect(settings.kitAnswers).toEqual({});
  });

  it("replaces the previews when the kit sets them", () => {
    const medicine = bundled("medicine");
    let settings = testSettings();
    settings = { ...settings, notchPreview: { ...settingPreviewKind(settings.notchPreview, "focus", false), interval: 12 } };
    settings = applyKit(settings, medicine, BUILT_IN_CATALOG);
    expect(settings.notchPreview.disabledKinds).toEqual(new Set(["claudeUsage"]));
    expect(settings.notchPreview.interval).toBe(12);
    expect(usesKitDefaults(settings, medicine, BUILT_IN_CATALOG)).toBe(true);
    settings = { ...settings, notchPreview: settingPreviewKind(settings.notchPreview, "claudeUsage", true) };
    expect(usesKitDefaults(settings, medicine, BUILT_IN_CATALOG)).toBe(false);
  });

  it("keeps the previews when the kit sets none", () => {
    const plain = kitManifest({
      id: "plain",
      name: "Plain",
      summary: "",
      symbol: "circle",
      modules: [kitModuleEntry("planner"), kitModuleEntry("spotify")],
    });
    let settings = testSettings();
    settings = { ...settings, notchPreview: settingPreviewKind(settings.notchPreview, "meeting", false) };
    settings = applyKit(settings, plain, BUILT_IN_CATALOG);
    expect(settings.notchPreview.disabledKinds).toEqual(new Set(["meeting"]));
    expect(usesKitDefaults(settings, plain, BUILT_IN_CATALOG)).toBe(true);
  });

  it("falls back from malformed preview values and keeps unknown kinds", () => {
    defaults.set("settings.preview.interval", 7);
    defaults.set("settings.preview.disabledKinds", ["focus", "hologram"]);
    defaults.set("settings.preview.enabled", "on");
    const preview = repository(defaults).load().notchPreview;
    expect(preview.interval).toBe(8);
    expect(preview.disabledKinds).toEqual(new Set(["focus", "hologram"]));
    expect(preview.isEnabled).toBe(true);
  });

  it("puts back a kit switch's preferences only", () => {
    const before = testSettings({ themeID: "neon" });
    const switched = { ...applyKit(before, bundled("medicine"), BUILT_IN_CATALOG), openOnHover: true };
    const undone = withKitState(switched, kitState(before));
    expect(undone.kitID).toBe(before.kitID);
    expect(undone.modules.equals(before.modules)).toBe(true);
    expect(undone.themeID).toBe("neon");
    expect(undone.openOnHover).toBe(true);
  });
});

describe("notch preview settings", () => {
  const every = new Set(allTickerKinds(BUILT_IN_CATALOG));
  const enabledKinds = (preview: typeof DEFAULT_NOTCH_PREVIEW) =>
    new Set([...every].filter((kind) => previewShows(preview, kind)));

  it("toggles only the kind toggled", () => {
    let preview = settingPreviewKind(DEFAULT_NOTCH_PREVIEW, "nowPlaying", false);
    expect(previewKindEnabled(preview, "nowPlaying")).toBe(false);
    expect(enabledKinds(preview)).toEqual(new Set(["meeting", "focus", "tasks", "progress", "claudeUsage", "party", "pet"]));
    preview = settingPreviewKind(preview, "nowPlaying", true);
    expect(enabledKinds(preview)).toEqual(every);
  });

  it("hides every kind with the master switch but keeps the choices", () => {
    let preview = { ...DEFAULT_NOTCH_PREVIEW, disabledKinds: new Set(["tasks"]), isEnabled: false };
    expect(enabledKinds(preview).size).toBe(0);
    expect(previewKindEnabled(preview, "tasks")).toBe(false);
    preview = { ...preview, isEnabled: true };
    expect(enabledKinds(preview)).toEqual(new Set([...every].filter((kind) => kind !== "tasks")));
  });

  it("skips kinds whose module is off", () => {
    let settings = testSettings({ notchPreview: { ...DEFAULT_NOTCH_PREVIEW, disabledKinds: new Set(["tasks"]) } });
    settings = withModules(settings, (layout) => {
      layout.setEnabled("claudeUsage", false);
      layout.setEnabled("spotify", false);
    });
    expect(previewKinds(settings)).toEqual(new Set(["meeting", "focus", "progress"]));
    settings = withModules(settings, (layout) => layout.setEnabled("planner", false));
    expect(previewKinds(settings)).toEqual(new Set(["focus", "progress"]));
    settings = { ...settings, notchPreview: { ...settings.notchPreview, isEnabled: false } };
    settings = withModules(settings, (layout) => layout.setEnabled("planner", true));
    expect(previewKinds(settings).size).toBe(0);
  });

  it("offers the Mac's intervals", () => {
    expect(TICKER_INTERVALS).toEqual([5, 8, 12]);
    expect(tickerIntervalTitle(8)).toBe("8 seconds");
  });
});

describe("section resets", () => {
  const medicine = bundled("medicine");
  const essentials = bundled("essentials");

  function customized(): AppSettings {
    const applied = applyKit(testSettings(), medicine, BUILT_IN_CATALOG);
    return {
      ...applied,
      openOnHover: true,
      hapticsEnabled: false,
      celebrationSoundEnabled: false,
      weeklyRecapEnabled: false,
      catWisdomEnabled: false,
      launchAtLogin: true,
      hotkey: { keyCode: 0, modifiers: command | option },
      preferredDisplay: { kind: "main" },
      showOnExternalDisplays: false,
      hideInFullscreen: false,
      hideFromScreenCapture: true,
      hideInMissionControl: true,
      notchMode: "hidden",
      panelSize: "compact",
      motionPace: "fast",
      notchPreview: { ...settingPreviewKind(applied.notchPreview, "focus", false), isEnabled: false, interval: 12 },
      claudePathOverride: "/opt/claude",
      themeID: "neon",
    };
  }

  it("restores General and keeps the rest", () => {
    const before = customized();
    expect(usesGeneralDefaults(before, medicine, BUILT_IN_CATALOG)).toBe(false);
    const settings = resetGeneral(before, medicine, BUILT_IN_CATALOG);
    const fresh = appSettings({ modules: settings.modules });
    expect(settings.openOnHover).toBe(fresh.openOnHover);
    expect(settings.hapticsEnabled).toBe(fresh.hapticsEnabled);
    expect(settings.celebrationSoundEnabled).toBe(fresh.celebrationSoundEnabled);
    expect(settings.weeklyRecapEnabled).toBe(fresh.weeklyRecapEnabled);
    expect(settings.catWisdomEnabled).toBe(true);
    expect(settings.hotkey).toEqual(fresh.hotkey);
    expect(settings.preferredDisplay).toEqual({ kind: "builtIn" });
    expect(settings.showOnExternalDisplays).toBe(fresh.showOnExternalDisplays);
    expect(settings.hideInFullscreen).toBe(fresh.hideInFullscreen);
    expect(settings.hideFromScreenCapture).toBe(false);
    expect(settings.hideInMissionControl).toBe(false);
    expect(settings.notchMode).toBe("always");
    expect(settings.panelSize).toBe("regular");
    expect(settings.motionPace).toBe("smooth");
    expect(settings.notchPreview.isEnabled).toBe(true);
    expect(settings.notchPreview.interval).toBe(DEFAULT_NOTCH_PREVIEW.interval);
    expect(usesGeneralDefaults(settings, medicine, BUILT_IN_CATALOG)).toBe(true);
    expect(settings.launchAtLogin).toBe(true);
    expect(settings.kitID).toBe("medicine");
    expect(settings.modules.equals(customized().modules)).toBe(true);
    expect(settings.claudePathOverride).toBe("/opt/claude");
    expect(settings.themeID).toBe("neon");
  });

  it("shows the kit's live activity items after a General reset", () => {
    let settings = resetGeneral(customized(), medicine, BUILT_IN_CATALOG);
    const shown = allTickerKinds(BUILT_IN_CATALOG).filter((kind) => previewKindEnabled(settings.notchPreview, kind));
    expect(new Set(shown)).toEqual(new Set(medicine.defaults.ticker));
    settings = resetGeneral(settings, undefined, BUILT_IN_CATALOG);
    expect(settings.notchPreview.disabledKinds.size).toBe(0);
  });

  it("finds a fresh install already on General's defaults", () => {
    let settings = applyKit(testSettings(), essentials, BUILT_IN_CATALOG);
    expect(usesGeneralDefaults(settings, essentials, BUILT_IN_CATALOG)).toBe(true);
    settings = { ...settings, launchAtLogin: true };
    expect(usesGeneralDefaults(settings, essentials, BUILT_IN_CATALOG)).toBe(true);
    settings = { ...settings, openOnHover: !settings.openOnHover };
    expect(usesGeneralDefaults(settings, essentials, BUILT_IN_CATALOG)).toBe(false);
  });

  it("keeps the user's name through a General reset", () => {
    expect(usesGeneralDefaults(testSettings({ displayName: "Ada" }), undefined, BUILT_IN_CATALOG)).toBe(true);
    expect(resetGeneral({ ...customized(), displayName: "Ada" }, medicine, BUILT_IN_CATALOG).displayName).toBe("Ada");
  });

  it("defaults Look to the kit's theme or the app's", () => {
    expect(defaultThemeForKit(medicine)).toBe("cozy");
    expect(defaultThemeForKit(essentials)).toBe("midnight");
    expect(defaultThemeForKit(undefined)).toBe(DEFAULT_THEME_ID);
  });
});

describe("SettingsSchema", () => {
  /* The catalog of an older build that has no Party module. */
  const catalogWithoutParty = new ModuleCatalog(BUILT_IN_CATALOG.descriptors.filter((d) => d.id !== "party"));

  it("records the current version on a fresh install", () => {
    repository(defaults).load();
    expect(storedSettingsVersion(defaults)).toBe(CURRENT_SETTINGS_VERSION);
    expect(CURRENT_SETTINGS_VERSION).toBe(7);
  });

  it("runs steps once, in order, from the stored version", () => {
    const steps: SettingsMigration[] = [1, 2, 3].map((version) => ({
      version,
      migrate: (store) => {
        const ran = store.get("ran");
        store.set("ran", [...(Array.isArray(ran) ? ran : []), version]);
      },
    }));
    defaults.set(SETTINGS_VERSION_KEY, 1);
    migrateSettings(defaults, steps);
    migrateSettings(defaults, steps);
    expect(defaults.get("ran")).toEqual([2, 3]);
    expect(storedSettingsVersion(defaults)).toBe(3);
  });

  it("leaves settings from a newer build alone", () => {
    defaults.set(SETTINGS_VERSION_KEY, CURRENT_SETTINGS_VERSION + 5);
    defaults.set("settings.modules.order", ["spotify", "system"]);
    const repo = repository(defaults);
    const settings = repo.load();
    expect(defaults.get("settings.kit.chosen")).toBeUndefined();
    expect(settings.hasChosenKit).toBe(false);
    repo.save(settings);
    expect(storedSettingsVersion(defaults)).toBe(CURRENT_SETTINGS_VERSION + 5);
  });

  it("migrates a version zero layout without a flag to chosen, on disk", () => {
    defaults.set("settings.modules.order", ["spotify", "system", "claudeUsage", "planner", "claudeAsk"]);
    expect(repository(defaults).load().hasChosenKit).toBe(true);
    expect(defaults.get("settings.kit.chosen")).toBe(true);
  });

  it("still asks for a kit at version zero without a layout", () => {
    defaults.set("settings.openOnHover", true);
    expect(repository(defaults).load().hasChosenKit).toBe(false);
  });

  it("gives a version two active import its namespaced id", () => {
    defaults.set(SETTINGS_VERSION_KEY, 2);
    defaults.set("settings.kit", "deep-work");
    const imported = decodeKit(`{"formatVersion": 1, "id": "deep-work", "name": "Deep Work", "modules": ["focus"]}`);
    expect(imported.ok).toBe(true);
    if (!imported.ok) return;
    const deepWork = { ...imported.kit, id: importedKitID(imported.kit.id) };
    const settings = repository(defaults, { kits: BUNDLED_KITS.withImported([deepWork]) }).load();
    expect(settings.kitID).toBe("imported.deep-work");
    expect(defaultsString(defaults, "settings.kit")).toBe("imported.deep-work");
  });

  it("keeps a version two bundled kit id", () => {
    defaults.set(SETTINGS_VERSION_KEY, 2);
    defaults.set("settings.kit", "medicine");
    expect(repository(defaults).load().kitID).toBe("medicine");
  });

  it("moves retired kits to Essentials and keeps their tabs", () => {
    for (const [retired, version] of [
      ["productivity", 3],
      ["student", 3],
      ["productivity", 2],
      ["student", 0],
    ] as const) {
      const store = new InMemoryDefaults();
      store.set(SETTINGS_VERSION_KEY, version);
      store.set("settings.kit", retired);
      store.set("settings.kit.chosen", true);
      store.set("settings.kit.answers", { level: ["college"] });
      store.set("settings.modules.order", ["spotify", "system", "claudeUsage", "planner", "claudeAsk", "anki"]);
      store.set("settings.modules.disabled", ["anki"]);
      const settings = repository(store).load();
      const label = `${retired} at version ${version}`;
      expect(settings.kitID, label).toBe("essentials");
      expect(defaultsString(store, "settings.kit")).toBe("essentials");
      expect(settings.hasChosenKit).toBe(true);
      expect(settings.kitAnswers).toEqual({});
      expect(settings.modules.enabled).toEqual(["spotify", "system", "claudeUsage", "planner", "claudeAsk"]);
      expect(settings.modules.isEnabled("anki")).toBe(false);
    }
  });

  it("keeps the regular panel for a version four install", () => {
    defaults.set(SETTINGS_VERSION_KEY, 4);
    defaults.set("settings.kit", "essentials");
    expect(repository(defaults).load().panelSize).toBe("regular");
    expect(defaults.get("settings.panelSize")).toBe("regular");
  });

  it("leaves a fresh install and a saved size alone in the panel size step", () => {
    migrateSettings(defaults);
    expect(defaults.get("settings.panelSize")).toBeUndefined();
    const saved = new InMemoryDefaults();
    saved.set(SETTINGS_VERSION_KEY, 4);
    saved.set("settings.kit", "essentials");
    saved.set("settings.panelSize", "compact");
    expect(repository(saved).load().panelSize).toBe("compact");
  });

  it("doesn't move current kits in the retired kit step", () => {
    defaults.set(SETTINGS_VERSION_KEY, 3);
    defaults.set("settings.kit", "medicine");
    defaults.set("settings.kit.answers", { anki: ["no"] });
    const settings = repository(defaults).load();
    expect(settings.kitID).toBe("medicine");
    expect(settings.kitAnswers).toEqual(answers({ anki: ["no"] }));
  });

  it("adopts the name chosen in Party at version five", () => {
    defaults.set(SETTINGS_VERSION_KEY, 5);
    defaults.set("party.settings", JSON.stringify({ serverText: "", name: "  Ada  ", invisible: false }));
    expect(repository(defaults).load().displayName).toBe("Ada");
    expect(defaults.get("settings.displayName")).toBe("Ada");
    expect(JSON.parse(defaultsString(defaults, "party.settings") ?? "{}")).toMatchObject({ name: "  Ada  " });
  });

  it("starts with no name without one in Party", () => {
    defaults.set(SETTINGS_VERSION_KEY, 5);
    defaults.set("party.settings", JSON.stringify({ name: " " }));
    expect(repository(defaults).load().displayName).toBe("");
    expect(defaults.get("settings.displayName")).toBeUndefined();
  });

  it("keeps a name already saved", () => {
    defaults.set(SETTINGS_VERSION_KEY, 5);
    defaults.set("settings.displayName", "Grace");
    defaults.set("party.settings", JSON.stringify({ name: "Ada" }));
    expect(repository(defaults).load().displayName).toBe("Grace");
  });

  it("adopts the Party name in an upgrade from before versions", () => {
    defaults.set("party.settings", JSON.stringify({ name: "Ada" }));
    expect(repository(defaults).load().displayName).toBe("Ada");
  });

  it("keeps Claude Code for someone who used Tabbi before AI providers", () => {
    defaults.set(SETTINGS_VERSION_KEY, 6);
    defaults.set("settings.kit", "essentials");
    expect(repository(defaults).load().ai.provider).toBe("claude-cli");
    const fresh = new InMemoryDefaults();
    expect(repository(fresh).load().ai.provider).toBeUndefined();
  });

  it("moves the focus timer off the planner keys without overwriting a newer one", () => {
    defaults.set("planner.focusTimer", `{"old":true}`);
    defaults.set("planner.focusSessions", `{"sessions":[]}`);
    migrateSettings(defaults);
    expect(defaults.get("planner.focusTimer")).toBeUndefined();
    expect(defaults.get("planner.focusSessions")).toBeUndefined();
    expect(defaults.get("focus.timer")).toBe(`{"old":true}`);
    expect(defaults.get("focus.sessionLog")).toBe(`{"sessions":[]}`);

    const newer = new InMemoryDefaults();
    newer.set("focus.timer", `{"current":true}`);
    newer.set("planner.focusTimer", `{"old":true}`);
    newer.set(SETTINGS_VERSION_KEY, 1);
    migrateSettings(newer);
    expect(newer.get("focus.timer")).toBe(`{"current":true}`);
    expect(newer.get("planner.focusTimer")).toBeUndefined();
  });

  it("puts unknown ids back after their predecessor", () => {
    expect(
      storedModuleOrder(["b", "a", "c"], ["x", "a", "y", "z", "b", "c"], (id) => ["a", "b", "c"].includes(id)),
    ).toEqual(["x", "b", "a", "y", "z", "c"]);
  });

  it("keeps a module an older build doesn't know", () => {
    const newer = repository(defaults);
    const layout = builtInLayout(["study", "party", "planner", "closet"], ["closet"]);
    layout.setEnabled("party", true);
    newer.save({ ...newer.load(), modules: layout });

    const older = repository(defaults, { catalog: catalogWithoutParty });
    const olderSettings = older.load();
    expect(olderSettings.modules.order).not.toContain("party");
    older.save(withModules(olderSettings, (modules) => modules.setEnabled("closet", true)));

    const reloaded = newer.load().modules;
    expect(reloaded.order.slice(0, 4)).toEqual(["study", "party", "planner", "closet"]);
    expect(reloaded.isEnabled("party")).toBe(true);
    expect(reloaded.isEnabled("closet")).toBe(true);
  });

  it("keeps an unknown module switched off in an older build", () => {
    const newer = repository(defaults);
    newer.save({ ...newer.load(), modules: builtInLayout(["planner", "party"], ["party"]) });
    const older = repository(defaults, { catalog: catalogWithoutParty });
    older.save(older.load());
    expect(newer.load().modules.isEnabled("party")).toBe(false);
    expect(newer.load().modules.order.slice(0, 2)).toEqual(["planner", "party"]);
  });

  it("starts a fresh install of an edition on its kit", () => {
    const settings = repository(defaults, { defaultKitID: "medicine" }).load();
    expect(settings.kitID).toBe("medicine");
    expect(settings.modules.equals(kitLayout(bundled("medicine"), BUILT_IN_CATALOG))).toBe(true);
  });
});
