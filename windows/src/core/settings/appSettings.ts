import { kitLayout, sameKitAnswers, type KitAnswers } from "../kits/kitApplication";
import { deepEqual, type KitDefaults, type KitManifest } from "../kits/kitManifest";
import { DEFAULT_KIT_ID } from "../kits/kitLibrary";
import type { ModuleCatalog } from "../modules/moduleCatalog";
import type { ModuleLayout } from "../modules/moduleLayout";
import { DEFAULT_AI_SETTINGS, type AISettings } from "./aiSettings";
import { cleanedDisplayName } from "./displayName";
import { DEFAULT_DISPLAY_PREFERENCE, type DisplayPreference } from "./displayPreference";
import { DEFAULT_HOTKEY, type Hotkey } from "./hotkey";
import { DEFAULT_MOTION_PACE, type MotionPace } from "./motionPace";
import { DEFAULT_NOTCH_MODE, type NotchMode } from "./notchMode";
import {
  DEFAULT_NOTCH_PREVIEW,
  previewShows,
  samePreviewSettings,
  type NotchPreviewSettings,
} from "./notchPreviewSettings";
import { DEFAULT_PANEL_SIZE, type PanelSize } from "./panelSize";
import { DEFAULT_THEME_ID, themeIDForKitValue, type ThemeID } from "./themeIds";
import { allTickerKinds, tickerKindModule, type TickerKind } from "./tickerKind";

/**
 * Port of AppSettings: every user preference Tabbi has, as one value. Treat
 * it as immutable: the functions below return a changed copy, and a caller
 * that changes `modules` in place clones it first.
 */
export interface AppSettings {
  /** The user's name, kept as typed so the field round-trips; blank means no name yet. */
  readonly displayName: string;
  /** The kit the user (or edition) picked. */
  readonly kitID: string;
  /** False until the user picks a kit, so the first launch can ask which kit to start from. */
  readonly hasChosenKit: boolean;
  /** The answers to the kit's onboarding questions, kept so a reset rebuilds the tabs they chose. */
  readonly kitAnswers: KitAnswers;
  readonly modules: ModuleLayout;
  /** When on, resting the pointer on the closed panel for `HOVER_OPEN_DELAY` opens it. */
  readonly openOnHover: boolean;
  readonly hapticsEnabled: boolean;
  /** A soft sound under celebrations that have none of their own. */
  readonly celebrationSoundEnabled: boolean;
  /** The weekly recap, built every Sunday evening from the activity log. */
  readonly weeklyRecapEnabled: boolean;
  /** Now and then a short line from the pet right after a focus session ends. */
  readonly catWisdomEnabled: boolean;
  /** Mirrors the user's choice; the system's startup entry is the source of truth. */
  readonly launchAtLogin: boolean;
  readonly hotkey: Hotkey;
  /** Explicit path to the `claude` binary; undefined means auto-discover. Trimmed; blank is undefined. */
  readonly claudePathOverride?: string;
  readonly preferredDisplay: DisplayPreference;
  readonly showOnExternalDisplays: boolean;
  /** When on, the panel steps aside while an app is fullscreen on its screen. */
  readonly hideInFullscreen: boolean;
  /** When on, the panel is left out of screenshots, recordings and shared screens. */
  readonly hideFromScreenCapture: boolean;
  /** A Mac preference (Mission Control), kept so the stored value round-trips. */
  readonly hideInMissionControl: boolean;
  readonly notchMode: NotchMode;
  readonly panelSize: PanelSize;
  readonly motionPace: MotionPace;
  readonly notchPreview: NotchPreviewSettings;
  /** Kept as saved even when this build lacks it; the theme port draws the default then. */
  readonly themeID: ThemeID;
  readonly ai: AISettings;
}

/** How long the pointer must rest on the closed panel before hover-to-open fires, in seconds. */
export const HOVER_OPEN_DELAY = 0.25;

export type AppSettingsInput = Partial<Omit<AppSettings, "modules">> & { modules: ModuleLayout };

/** Settings with the Mac initializer's defaults. The tab layout has no default: it comes from the module catalog. */
export function appSettings(input: AppSettingsInput): AppSettings {
  const settings: AppSettings = {
    displayName: "",
    kitID: DEFAULT_KIT_ID,
    hasChosenKit: false,
    kitAnswers: {},
    openOnHover: false,
    hapticsEnabled: true,
    celebrationSoundEnabled: true,
    weeklyRecapEnabled: true,
    catWisdomEnabled: true,
    launchAtLogin: false,
    hotkey: DEFAULT_HOTKEY,
    preferredDisplay: DEFAULT_DISPLAY_PREFERENCE,
    showOnExternalDisplays: true,
    hideInFullscreen: true,
    hideFromScreenCapture: false,
    hideInMissionControl: false,
    notchMode: DEFAULT_NOTCH_MODE,
    panelSize: DEFAULT_PANEL_SIZE,
    motionPace: DEFAULT_MOTION_PACE,
    notchPreview: DEFAULT_NOTCH_PREVIEW,
    themeID: DEFAULT_THEME_ID,
    ai: DEFAULT_AI_SETTINGS,
    ...input,
  };
  return withClaudePath(settings, input.claudePathOverride);
}

/** The settings with a new path override, trimmed; blank means no override. */
export function withClaudePath(settings: AppSettings, path: string | undefined): AppSettings {
  const trimmed = path?.trim();
  return { ...settings, claudePathOverride: trimmed ? trimmed : undefined };
}

/** The name as Party and greetings use it, or undefined when the user has not given one. */
export function settingsCleanedName(settings: AppSettings): string | undefined {
  return cleanedDisplayName(settings.displayName);
}

/**
 * Whether the closed-panel preview may show `kind`: the user's preview
 * choices, minus items whose module is off, since clicking one would open a
 * tab that isn't there.
 */
export function settingsShowsPreview(settings: AppSettings, kind: TickerKind): boolean {
  const module = tickerKindModule(kind);
  return previewShows(settings.notchPreview, kind) && (module === undefined || settings.modules.isEnabled(module));
}

/** Preview kinds to show, or undefined to keep the app default (all). Names `catalog` can't show are dropped. */
export function resolvedKitTicker(defaults: KitDefaults, catalog: ModuleCatalog): Set<TickerKind> | undefined {
  if (defaults.ticker === undefined) return undefined;
  const known = new Set(allTickerKinds(catalog));
  return new Set(defaults.ticker.filter((kind) => known.has(kind)));
}

function previewWithKitTicker(
  preview: NotchPreviewSettings,
  kit: KitManifest | undefined,
  catalog: ModuleCatalog,
): NotchPreviewSettings {
  const kinds = kit ? resolvedKitTicker(kit.defaults, catalog) : undefined;
  if (kinds === undefined) return preview;
  return { ...preview, disabledKinds: new Set(allTickerKinds(catalog).filter((kind) => !kinds.has(kind))) };
}

/**
 * Switches to `kit`: replaces the tab layout with the one it produces for
 * `answers`, the closed-panel previews with the kit's when it lists any, and
 * the theme with the kit's when it names one this build has. Other
 * preferences are kept. Either way the user has now picked a kit.
 */
export function applyKit(
  settings: AppSettings,
  kit: KitManifest,
  catalog: ModuleCatalog,
  answers: KitAnswers = {},
): AppSettings {
  const theme = kit.defaults.theme === undefined ? undefined : themeIDForKitValue(kit.defaults.theme);
  return {
    ...settings,
    kitID: kit.id,
    hasChosenKit: true,
    kitAnswers: answers,
    modules: kitLayout(kit, catalog, answers),
    notchPreview: previewWithKitTicker(settings.notchPreview, kit, catalog),
    themeID: theme ?? settings.themeID,
  };
}

/** Port of AppSettings.KitState: the preferences a kit sets, so undoing a switch puts back only these. */
export interface KitState {
  readonly kitID: string;
  readonly hasChosenKit: boolean;
  readonly kitAnswers: KitAnswers;
  readonly modules: ModuleLayout;
  readonly disabledPreviews: ReadonlySet<TickerKind>;
  readonly themeID: ThemeID;
}

export function kitState(settings: AppSettings): KitState {
  return {
    kitID: settings.kitID,
    hasChosenKit: settings.hasChosenKit,
    kitAnswers: settings.kitAnswers,
    modules: settings.modules,
    disabledPreviews: settings.notchPreview.disabledKinds,
    themeID: settings.themeID,
  };
}

export function withKitState(settings: AppSettings, state: KitState): AppSettings {
  return {
    ...settings,
    kitID: state.kitID,
    hasChosenKit: state.hasChosenKit,
    kitAnswers: state.kitAnswers,
    modules: state.modules,
    notchPreview: { ...settings.notchPreview, disabledKinds: state.disabledPreviews },
    themeID: state.themeID,
  };
}

/**
 * True when `kit` is the active kit and the tabs, previews and theme are
 * still exactly the ones it produces for the saved answers, so "Reset to
 * Kit Defaults" would change nothing here.
 */
export function usesKitDefaults(settings: AppSettings, kit: KitManifest, catalog: ModuleCatalog): boolean {
  const reset = applyKit(settings, kit, catalog, settings.kitAnswers);
  return (
    settings.kitID === kit.id &&
    reset.modules.equals(settings.modules) &&
    samePreviewSettings(reset.notchPreview, settings.notchPreview) &&
    reset.themeID === settings.themeID
  );
}

/**
 * Puts General's settings back to how a fresh install has them, with the
 * live activity items `kit` picks (all of them without a kit or when it names
 * none). Launch at login and the user's name are kept; tabs, theme and the
 * AI provider belong to other sections.
 */
export function resetGeneral(settings: AppSettings, kit: KitManifest | undefined, catalog: ModuleCatalog): AppSettings {
  const fresh = appSettings({ modules: settings.modules });
  return {
    ...settings,
    openOnHover: fresh.openOnHover,
    hapticsEnabled: fresh.hapticsEnabled,
    celebrationSoundEnabled: fresh.celebrationSoundEnabled,
    weeklyRecapEnabled: fresh.weeklyRecapEnabled,
    catWisdomEnabled: fresh.catWisdomEnabled,
    hotkey: fresh.hotkey,
    preferredDisplay: fresh.preferredDisplay,
    showOnExternalDisplays: fresh.showOnExternalDisplays,
    hideInFullscreen: fresh.hideInFullscreen,
    hideFromScreenCapture: fresh.hideFromScreenCapture,
    hideInMissionControl: fresh.hideInMissionControl,
    notchMode: fresh.notchMode,
    panelSize: fresh.panelSize,
    motionPace: fresh.motionPace,
    notchPreview: previewWithKitTicker(fresh.notchPreview, kit, catalog),
  };
}

/** True when General's "Reset to Defaults" would change nothing. */
export function usesGeneralDefaults(settings: AppSettings, kit: KitManifest | undefined, catalog: ModuleCatalog): boolean {
  return settingsEqual(resetGeneral(settings, kit, catalog), settings);
}

/** The theme Look's "Reset to Default" picks: `kit`'s when it names one this build has, else the app's default. */
export function defaultThemeForKit(kit: KitManifest | undefined): ThemeID {
  const value = kit?.defaults.theme;
  return (value === undefined ? undefined : themeIDForKitValue(value)) ?? DEFAULT_THEME_ID;
}

/** Whether two settings values are equal, field by field. */
export function settingsEqual(a: AppSettings, b: AppSettings): boolean {
  const { modules: aModules, notchPreview: aPreview, kitAnswers: aAnswers, ...aRest } = a;
  const { modules: bModules, notchPreview: bPreview, kitAnswers: bAnswers, ...bRest } = b;
  return (
    aModules.equals(bModules) &&
    samePreviewSettings(aPreview, bPreview) &&
    sameKitAnswers(aAnswers, bAnswers) &&
    deepEqual(aRest, bRest)
  );
}
