import { kitLayout, type KitAnswers } from "../kits/kitApplication";
import { DEFAULT_KIT_ID, type KitLibrary } from "../kits/kitLibrary";
import type { ModuleCatalog } from "../modules/moduleCatalog";
import { ModuleLayout } from "../modules/moduleLayout";
import {
  defaultsBool,
  defaultsInteger,
  defaultsObject,
  defaultsString,
  defaultsStringArray,
  type Defaults,
} from "../persistence/defaults";
import type { JSONObject } from "../persistence/json";
import { parseAIProviderID, type AIProviderID } from "../ai/aiProviderID";
import { appSettings, type AppSettings } from "./appSettings";
import { displayPreferenceFromStorage, displayPreferenceStorageValue } from "./displayPreference";
import { decodeHotkey, encodeHotkey, isValidHotkey } from "./hotkey";
import { isMotionPace } from "../motion/motionPace";
import { isNotchMode } from "./notchMode";
import { isTickerInterval } from "./notchPreviewSettings";
import { isPanelSize } from "./panelSize";
import {
  CURRENT_SETTINGS_VERSION,
  SETTINGS_KEYS as Key,
  SETTINGS_VERSION_KEY,
  migrateSettings,
  storedModuleOrder,
  storedSettingsVersion,
} from "./settingsSchema";
import { themeIdForKitValue } from "../themes/themeCatalog";

function sorted(values: Iterable<string>): string[] {
  return [...values].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
}

/**
 * Port of SettingsRepository: loads and saves AppSettings in the
 * preferences store, under the Mac's keys. Each preference lives under its
 * own key, so a single malformed value falls back to its default instead
 * of resetting everything. With no saved tab layout (first run), the layout
 * comes from the saved or default kit. Loading first brings the stored keys
 * up to the current schema; saving keeps the position and on/off state of
 * modules this build doesn't know.
 */
export class SettingsRepository {
  constructor(
    private readonly defaults: Defaults,
    private readonly catalog: ModuleCatalog,
    private readonly kits: KitLibrary,
    private readonly defaultKitID: string = DEFAULT_KIT_ID,
  ) {}

  load(): AppSettings {
    const defaults = this.defaults;
    migrateSettings(defaults);
    const fallback = appSettings({ modules: ModuleLayout.all(this.catalog) });
    const storedHotkey = defaultsString(defaults, Key.hotkey);
    const hotkey = storedHotkey === undefined ? undefined : decodeHotkey(storedHotkey);
    /* An unknown saved id (an imported kit that was removed) falls back to the default kit. */
    const kit = this.kits.kit(defaultsString(defaults, Key.kitID) ?? this.defaultKitID);
    const savedOrder = defaultsStringArray(defaults, Key.moduleOrder);
    const modules = savedOrder
      ? new ModuleLayout(savedOrder, defaultsStringArray(defaults, Key.disabledModules) ?? [], this.catalog)
      : undefined;
    const bool = (key: string, otherwise: boolean) => defaultsBool(defaults, key) ?? otherwise;
    const preferredDisplay = defaultsString(defaults, Key.preferredDisplay);
    const notchMode = defaults.get(Key.notchMode);
    const panelSize = defaults.get(Key.panelSize);
    const motionPace = defaults.get(Key.motionPace);
    const interval = defaultsInteger(defaults, Key.previewInterval);
    const savedTheme = defaultsString(defaults, Key.theme);
    const kitTheme = kit?.defaults.theme === undefined ? undefined : themeIdForKitValue(kit.defaults.theme);
    const provider = defaults.get(Key.aiProvider);
    return appSettings({
      displayName: defaultsString(defaults, Key.displayName) ?? fallback.displayName,
      kitID: kit?.id ?? this.defaultKitID,
      hasChosenKit: bool(Key.hasChosenKit, false),
      kitAnswers: readKitAnswers(defaultsObject(defaults, Key.kitAnswers)),
      modules: modules ?? (kit ? kitLayout(kit, this.catalog) : fallback.modules),
      openOnHover: bool(Key.openOnHover, fallback.openOnHover),
      hapticsEnabled: bool(Key.hapticsEnabled, fallback.hapticsEnabled),
      celebrationSoundEnabled: bool(Key.celebrationSoundEnabled, fallback.celebrationSoundEnabled),
      weeklyRecapEnabled: bool(Key.weeklyRecapEnabled, fallback.weeklyRecapEnabled),
      catWisdomEnabled: bool(Key.catWisdomEnabled, fallback.catWisdomEnabled),
      launchAtLogin: bool(Key.launchAtLogin, fallback.launchAtLogin),
      hotkey: hotkey && isValidHotkey(hotkey) ? hotkey : fallback.hotkey,
      claudePathOverride: defaultsString(defaults, Key.claudePathOverride),
      preferredDisplay:
        (preferredDisplay === undefined ? undefined : displayPreferenceFromStorage(preferredDisplay)) ??
        fallback.preferredDisplay,
      showOnExternalDisplays: bool(Key.showOnExternalDisplays, fallback.showOnExternalDisplays),
      hideInFullscreen: bool(Key.hideInFullscreen, fallback.hideInFullscreen),
      hideFromScreenCapture: bool(Key.hideFromScreenCapture, fallback.hideFromScreenCapture),
      hideInMissionControl: bool(Key.hideInMissionControl, fallback.hideInMissionControl),
      notchMode: isNotchMode(notchMode) ? notchMode : fallback.notchMode,
      panelSize: isPanelSize(panelSize) ? panelSize : fallback.panelSize,
      motionPace: isMotionPace(motionPace) ? motionPace : fallback.motionPace,
      notchPreview: {
        isEnabled: bool(Key.previewEnabled, fallback.notchPreview.isEnabled),
        /* Unknown kinds are kept: they may be a module's highlights this build lacks. */
        disabledKinds: new Set(defaultsStringArray(defaults, Key.previewDisabledKinds) ?? []),
        interval: isTickerInterval(interval) ? interval : fallback.notchPreview.interval,
      },
      /* Before the user picks one, the kit's theme. */
      themeID: savedTheme ?? kitTheme ?? fallback.themeID,
      ai: {
        provider: parseAIProviderID(provider),
        models: readModels(defaultsObject(defaults, Key.aiModels)),
        consented: new Set((defaultsStringArray(defaults, Key.aiConsented) ?? []).flatMap((id) => parseAIProviderID(id) ?? [])),
      },
    });
  }

  save(settings: AppSettings): void {
    const defaults = this.defaults;
    /* Never lower it: a newer build that wrote these settings must not run its steps again. */
    defaults.set(SETTINGS_VERSION_KEY, Math.max(CURRENT_SETTINGS_VERSION, storedSettingsVersion(defaults)));
    defaults.set(Key.displayName, settings.displayName);
    defaults.set(Key.kitID, settings.kitID);
    defaults.set(Key.hasChosenKit, settings.hasChosenKit);
    /* Sorted so the stored value is stable across saves. */
    const answers: JSONObject = {};
    for (const [question, picked] of Object.entries(settings.kitAnswers)) answers[question] = sorted(picked);
    defaults.set(Key.kitAnswers, answers);
    const isKnown = (id: string) => this.catalog.contains(id);
    const storedOrder = defaultsStringArray(defaults, Key.moduleOrder) ?? [];
    const unknownDisabled = (defaultsStringArray(defaults, Key.disabledModules) ?? []).filter((id) => !isKnown(id));
    const order = storedModuleOrder(settings.modules.order, storedOrder, isKnown);
    const disabled = new Set([...settings.modules.disabled, ...unknownDisabled]);
    defaults.set(Key.moduleOrder, order);
    defaults.set(
      Key.disabledModules,
      order.filter((id) => disabled.has(id)),
    );
    defaults.set(Key.openOnHover, settings.openOnHover);
    defaults.set(Key.hapticsEnabled, settings.hapticsEnabled);
    defaults.set(Key.celebrationSoundEnabled, settings.celebrationSoundEnabled);
    defaults.set(Key.weeklyRecapEnabled, settings.weeklyRecapEnabled);
    defaults.set(Key.catWisdomEnabled, settings.catWisdomEnabled);
    defaults.set(Key.launchAtLogin, settings.launchAtLogin);
    defaults.set(Key.hotkey, encodeHotkey(settings.hotkey));
    if (settings.claudePathOverride !== undefined) defaults.set(Key.claudePathOverride, settings.claudePathOverride);
    else defaults.remove(Key.claudePathOverride);
    defaults.set(Key.preferredDisplay, displayPreferenceStorageValue(settings.preferredDisplay));
    defaults.set(Key.showOnExternalDisplays, settings.showOnExternalDisplays);
    defaults.set(Key.hideInFullscreen, settings.hideInFullscreen);
    defaults.set(Key.hideFromScreenCapture, settings.hideFromScreenCapture);
    defaults.set(Key.hideInMissionControl, settings.hideInMissionControl);
    defaults.set(Key.notchMode, settings.notchMode);
    defaults.set(Key.panelSize, settings.panelSize);
    defaults.set(Key.motionPace, settings.motionPace);
    defaults.set(Key.previewEnabled, settings.notchPreview.isEnabled);
    defaults.set(Key.previewDisabledKinds, sorted(settings.notchPreview.disabledKinds));
    defaults.set(Key.previewInterval, settings.notchPreview.interval);
    defaults.set(Key.theme, settings.themeID);
    if (settings.ai.provider !== undefined) defaults.set(Key.aiProvider, settings.ai.provider);
    else defaults.remove(Key.aiProvider);
    const models: JSONObject = {};
    for (const [provider, model] of Object.entries(settings.ai.models)) {
      if (model !== undefined) models[provider] = model;
    }
    defaults.set(Key.aiModels, models);
    defaults.set(Key.aiConsented, sorted(settings.ai.consented));
  }
}

/** Answers as stored (question id to a list of answer ids), or none when any value isn't such a list. */
function readKitAnswers(stored: JSONObject | undefined): KitAnswers {
  if (!stored) return {};
  const answers: Record<string, ReadonlySet<string>> = {};
  for (const [question, picked] of Object.entries(stored)) {
    if (!Array.isArray(picked) || !picked.every((id) => typeof id === "string")) return {};
    answers[question] = new Set(picked as string[]);
  }
  return answers;
}

/** Models per provider; entries for providers this build doesn't know are dropped, and all when any isn't text. */
function readModels(stored: JSONObject | undefined): Partial<Record<AIProviderID, string>> {
  if (!stored) return {};
  const models: Partial<Record<AIProviderID, string>> = {};
  for (const [provider, model] of Object.entries(stored)) {
    if (typeof model !== "string") return {};
    const id = parseAIProviderID(provider);
    if (id !== undefined) models[id] = model;
  }
  return models;
}
