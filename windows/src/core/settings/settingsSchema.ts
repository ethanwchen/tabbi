import { isBundledKit } from "../kits/bundledKits";
import { importedKitID, RETIRED_KIT_IDS } from "../kits/kitLibrary";
import { defaultsInteger, defaultsString, type Defaults } from "../persistence/defaults";
import { isJSONObject } from "../persistence/json";
import { cleanedDisplayName } from "./displayName";

/** The stored keys, exactly as the Mac's SettingsRepository names them. */
export const SETTINGS_KEYS = {
  displayName: "settings.displayName",
  kitID: "settings.kit",
  hasChosenKit: "settings.kit.chosen",
  kitAnswers: "settings.kit.answers",
  moduleOrder: "settings.modules.order",
  disabledModules: "settings.modules.disabled",
  openOnHover: "settings.openOnHover",
  hapticsEnabled: "settings.hapticsEnabled",
  celebrationSoundEnabled: "settings.celebrationSoundEnabled",
  weeklyRecapEnabled: "settings.weeklyRecapEnabled",
  catWisdomEnabled: "settings.catWisdomEnabled",
  launchAtLogin: "settings.launchAtLogin",
  hotkey: "settings.hotkey",
  claudePathOverride: "settings.claudePathOverride",
  preferredDisplay: "settings.preferredDisplay",
  showOnExternalDisplays: "settings.showOnExternalDisplays",
  hideInFullscreen: "settings.hideInFullscreen",
  hideFromScreenCapture: "settings.hideFromScreenCapture",
  hideInMissionControl: "settings.hideInMissionControl",
  notchMode: "settings.notchMode",
  panelSize: "settings.panelSize",
  motionPace: "settings.motionPace",
  previewEnabled: "settings.preview.enabled",
  previewDisabledKinds: "settings.preview.disabledKinds",
  previewInterval: "settings.preview.interval",
  theme: "settings.theme",
  aiProvider: "settings.ai.provider",
  aiModels: "settings.ai.models",
  aiConsented: "settings.ai.consented",
} as const;

/** One step: upgrades settings stored at `version - 1` to `version`. */
export interface SettingsMigration {
  readonly version: number;
  readonly migrate: (defaults: Defaults) => void;
}

/* Keys other areas own that a step moves or reads; their meaning is the Mac's. */
const FOCUS_TIMER_KEY = "focus.timer";
const FOCUS_SESSION_LOG_KEY = "focus.sessionLog";
const LEGACY_FOCUS_TIMER_KEY = "planner.focusTimer";
const LEGACY_FOCUS_SESSION_LOG_KEY = "planner.focusSessions";
const PARTY_SETTINGS_KEY = "party.settings";

function hasSettings(defaults: Defaults): boolean {
  return defaults.get(SETTINGS_KEYS.kitID) !== undefined || defaults.get(SETTINGS_KEYS.moduleOrder) !== undefined;
}

/** The name saved in Party's own settings (a JSON document), cleaned, if any. */
function partyName(defaults: Defaults): string | undefined {
  const text = defaultsString(defaults, PARTY_SETTINGS_KEY);
  if (text === undefined) return undefined;
  try {
    const json: unknown = JSON.parse(text);
    if (!isJSONObject(json)) return undefined;
    return typeof json.name === "string" ? cleanedDisplayName(json.name) : undefined;
  } catch {
    return undefined;
  }
}

/**
 * Port of SettingsSchema: the version of the stored settings and the
 * ordered steps that bring older settings up to it. To change how a
 * preference is stored, append a step; never edit one that has shipped.
 * Settings from a newer build (a stored version above `current`) are left
 * untouched.
 */
export const SETTINGS_MIGRATIONS: readonly SettingsMigration[] = [
  /*
   * 0 -> 1: installs from before kits saved a tab layout but no "kit
   * chosen" flag. Those users already set Tabbi up, so record that they chose.
   */
  {
    version: 1,
    migrate: (defaults) => {
      if (defaults.get(SETTINGS_KEYS.hasChosenKit) === undefined && defaults.get(SETTINGS_KEYS.moduleOrder) !== undefined) {
        defaults.set(SETTINGS_KEYS.hasChosenKit, true);
      }
    },
  },
  /* 1 -> 2: the shared focus timer and its session log move from `planner.*` keys to `focus.*` keys. */
  {
    version: 2,
    migrate: (defaults) => {
      for (const [old, next] of [
        [LEGACY_FOCUS_TIMER_KEY, FOCUS_TIMER_KEY],
        [LEGACY_FOCUS_SESSION_LOG_KEY, FOCUS_SESSION_LOG_KEY],
      ] as const) {
        const value = defaults.get(old);
        if (value === undefined) continue;
        if (defaults.get(next) === undefined) defaults.set(next, value);
        defaults.remove(old);
      }
    },
  },
  /*
   * 2 -> 3: imported kits go by their imported id, so a kit a later Tabbi
   * ships can't shadow one the user imported. An active id that isn't a
   * bundled (or retired bundled) kit was an import.
   */
  {
    version: 3,
    migrate: (defaults) => {
      const id = defaultsString(defaults, SETTINGS_KEYS.kitID);
      if (id !== undefined && !isBundledKit(id) && RETIRED_KIT_IDS[id] === undefined) {
        defaults.set(SETTINGS_KEYS.kitID, importedKitID(id));
      }
    },
  },
  /*
   * 3 -> 4: Productivity and Student fold into Essentials. The saved layout
   * is left alone; answers to the old kit's questions go.
   */
  {
    version: 4,
    migrate: (defaults) => {
      const id = defaultsString(defaults, SETTINGS_KEYS.kitID);
      const replacement = id === undefined ? undefined : RETIRED_KIT_IDS[id];
      if (replacement !== undefined) {
        defaults.set(SETTINGS_KEYS.kitID, replacement);
        defaults.remove(SETTINGS_KEYS.kitAnswers);
      }
    },
  },
  /* 4 -> 5: the open panel gets a size setting; everyone who already uses Tabbi keeps Regular. */
  {
    version: 5,
    migrate: (defaults) => {
      if (hasSettings(defaults) && defaults.get(SETTINGS_KEYS.panelSize) === undefined) {
        defaults.set(SETTINGS_KEYS.panelSize, "regular");
      }
    },
  },
  /* 5 -> 6: the user's name becomes one app-wide setting; a name chosen in Party is adopted. */
  {
    version: 6,
    migrate: (defaults) => {
      if (defaults.get(SETTINGS_KEYS.displayName) !== undefined) return;
      const name = partyName(defaults);
      if (name !== undefined) defaults.set(SETTINGS_KEYS.displayName, name);
    },
  },
  /*
   * 6 -> 7: AI features get a provider choice. Until now they all ran the
   * local claude command, so someone who already uses Tabbi keeps Claude Code.
   */
  {
    version: 7,
    migrate: (defaults) => {
      if (hasSettings(defaults) && defaults.get(SETTINGS_KEYS.aiProvider) === undefined) {
        defaults.set(SETTINGS_KEYS.aiProvider, "claude-cli");
      }
    },
  },
];

export const SETTINGS_VERSION_KEY = "settings.schemaVersion";

/** The version this build writes. */
export const CURRENT_SETTINGS_VERSION = SETTINGS_MIGRATIONS[SETTINGS_MIGRATIONS.length - 1]?.version ?? 0;

/** The version of the stored settings (0 when none is recorded). */
export function storedSettingsVersion(defaults: Defaults): number {
  return defaultsInteger(defaults, SETTINGS_VERSION_KEY) ?? 0;
}

/** Runs the steps `defaults` hasn't had yet and records the last step's version. */
export function migrateSettings(defaults: Defaults, steps: readonly SettingsMigration[] = SETTINGS_MIGRATIONS): void {
  const stored = storedSettingsVersion(defaults);
  const target = steps[steps.length - 1]?.version ?? 0;
  if (stored >= target) return;
  for (const step of steps) if (step.version > stored) step.migrate(defaults);
  defaults.set(SETTINGS_VERSION_KEY, target);
}

/**
 * The tab order to store: `live` (the modules this build knows, in the
 * user's order) with every id from `stored` this build doesn't know put back
 * right after the id it followed before, so running a build without a
 * module doesn't lose that module's place.
 */
export function storedModuleOrder(
  live: readonly string[],
  stored: readonly string[],
  isKnown: (id: string) => boolean,
): string[] {
  const result = [...live];
  let previous: string | undefined;
  for (const id of stored) {
    if (!isKnown(id) && !result.includes(id)) {
      const index = previous === undefined ? -1 : result.indexOf(previous);
      result.splice(index >= 0 ? index + 1 : 0, 0, id);
    }
    previous = id;
  }
  return result;
}
