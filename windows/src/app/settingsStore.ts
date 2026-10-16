/*
 * Port of SettingsStore: the app's live preferences. Modules and the shell
 * read `settings` (and follow `kitApplied`); only Settings and onboarding
 * change them. Every change is saved through the core's SettingsRepository
 * into one preferences document (the Mac's UserDefaults domain) and posted
 * to the other windows, so a theme picked in the Settings window shows on
 * the island at once.
 *
 * The kit library holds the bundled kits plus the user's imports
 * (ImportedKitStore, in the edition's Kits folder); an import, a removal
 * and their undo move the kit files and tell the other windows to reload.
 * Start with Windows and the global hotkey go through the host (the Mac's
 * login item and GlobalHotkey), injected as `SystemIntegration` so demo,
 * snapshot and test runs never touch the real ones.
 */

import {
  applyKit,
  defaultThemeForKit,
  kitState,
  resetGeneral,
  settingsEqual,
  usesGeneralDefaults,
  usesKitDefaults,
  withKitState,
  type AppSettings,
  type KitState,
} from "../core/settings/appSettings";
import { CRASH_REPORT_CONSENT_KEY, parseCrashReportConsent, type CrashReportConsent } from "../core/feedback/crashReporting";
import type { KitAnswers } from "../core/kits/kitApplication";
import { kitChangePreview, type KitChangePreview } from "../core/kits/kitChangePreview";
import { DEFAULT_KIT_ID, isImportedKitID, type KitLibrary } from "../core/kits/kitLibrary";
import type { KitManifest } from "../core/kits/kitManifest";
import type { ImportedKitStore, KitImportCandidate, KitInspection } from "../core/kits/importedKitStore";
import { kitIssues } from "../core/kits/kitValidation";
import type { KitIssue } from "../core/kits/kitSettingsSchema";
import type { ModuleCatalog } from "../core/modules/moduleCatalog";
import { InMemoryDefaults, loadDefaults, saveDefaults, type Defaults } from "../core/persistence/defaults";
import { isJSONObject, type JSONObject } from "../core/persistence/json";
import type { DocumentStore } from "../core/persistence/documentStore";
import type { Hotkey } from "../core/settings/hotkey";
import { SettingsRepository } from "../core/settings/settingsRepository";
import type { ThemeID } from "../core/themes/appTheme";
import type { HotkeyStatus } from "../host/host";
import { hostShortcut } from "../ui/kit/hotkeyRecording";
import { NOTCH_MODES, type NotchMode as IslandMode } from "../ui/shell/machine";
import { Emitter, Observable, type Readable } from "./store";
import { quietChannel, type WindowChannel } from "./windowChannel";

export type { IslandMode };

/** The preferences document in the edition's folder. */
export const SETTINGS_DOCUMENT = "settings.json";

/**
 * Where the closed island's mode is kept. The Mac's NotchMode (core
 * settings) has no Auto, which is the Windows default (the pill only while
 * something is live), so the Windows reading has a key of its own beside
 * the Mac's.
 */
export const ISLAND_MODE_KEY = "windows.islandMode";
export const DEFAULT_ISLAND_MODE: IslandMode = "auto";

/** Reduce Motion turned on in Settings > Look; absent follows Windows' own setting. */
export const REDUCE_MOTION_KEY = "windows.reduceMotion";

/** True once onboarding showed how to pin the tray icon; it is shown once and never nags. */
export const TRAY_HINT_SHOWN_KEY = "windows.trayHintShown";

/** Why the active kit was applied. */
export type KitApplicationKind =
  /** The user picked or switched to the kit. */
  | "switched"
  /** Reset to Kit Defaults re-applied the active kit. */
  | "reset"
  /**
   * Undo put back the kit the last switch replaced. Modules restore what
   * they held before that switch and take back what it added.
   */
  | "undo";

/** Port of SettingsStore.KitApplication: a kit the user just applied. */
export interface KitApplication {
  readonly kit: KitManifest;
  /** The onboarding answers it was applied with. */
  readonly answers: KitAnswers;
  readonly kind: KitApplicationKind;
}

/** True when the user picked or switched to the kit (not a reset or an undo), so its starter tasks belong on Today. */
export function addsStarterTasks(application: KitApplication): boolean {
  return application.kind === "switched";
}

/** Port of SettingsStore.KitSwitchUndo: what the last kit switch, import or removal replaced. */
export interface KitSwitchUndo {
  /** The kit, tabs and previews before the switch. Undo restores only these, so other settings changed since stay. */
  readonly kitState: KitState;
  /** The kit switched to, imported or removed, for the Undo button's tooltip. */
  readonly kitName: string;
  /** False for an import that kept the user's tabs (Add Only, Keep My Tabs), whose undo only takes the kit file back. */
  readonly switchedKit: boolean;
  /** Imported kit files the switch wrote or removed: each id with the text saved under it before (undefined when there was no file). */
  readonly kitFiles: Readonly<Record<string, string | undefined>>;
}

/**
 * The parts of Windows the store drives: Start with Windows (a per-user Run
 * value, off by default) and the one global hotkey. Snapshot, demo and test
 * runs pass none, so they never touch the real ones.
 */
export interface SystemIntegration {
  autostartEnable(): Promise<void>;
  autostartDisable(): Promise<void>;
  autostartIsEnabled(): Promise<boolean>;
  setHotkey(shortcut: string | null): Promise<HotkeyStatus>;
}

/* What one window tells the others. */
type SettingsMessage =
  | { readonly type: "settings"; readonly entries: JSONObject }
  | { readonly type: "kitApplied"; readonly kitID: string; readonly answers: Readonly<Record<string, readonly string[]>>; readonly kind: KitApplicationKind }
  /* The imported kit files changed; reload them. */
  | { readonly type: "kits" }
  | { readonly type: "hotkey"; readonly shortcut: string; readonly registered: boolean }
  /* Settings > Tabs asked the island to run first-run setup again. */
  | { readonly type: "runSetup" };

function encodeAnswers(answers: KitAnswers): Record<string, string[]> {
  return Object.fromEntries(Object.entries(answers).map(([question, picked]) => [question, [...picked].sort()]));
}

function decodeAnswers(value: unknown): KitAnswers {
  if (!isJSONObject(value)) return {};
  const answers: Record<string, ReadonlySet<string>> = {};
  for (const [question, picked] of Object.entries(value)) {
    if (Array.isArray(picked) && picked.every((id) => typeof id === "string")) answers[question] = new Set(picked as string[]);
  }
  return answers;
}

function isIslandMode(value: unknown): value is IslandMode {
  return typeof value === "string" && (NOTCH_MODES as readonly string[]).includes(value);
}

export interface SettingsStoreOptions {
  readonly catalog: ModuleCatalog;
  readonly kits: KitLibrary;
  /** The edition's kit, used before the user picks one. */
  readonly defaultKitID?: string;
  /** Where the preferences document lives; undefined keeps them in memory (demo and snapshot runs). */
  readonly store?: DocumentStore;
  readonly channel?: WindowChannel;
  /** Where imported kits live; undefined offers only the bundled kits (demo and snapshot runs). */
  readonly kitStore?: ImportedKitStore;
  readonly system?: SystemIntegration;
  /** The hotkey the host registered at launch (the default), so the store knows whether another app owns it. */
  readonly hotkeyStatus?: HotkeyStatus | null;
}

export class SettingsStore {
  readonly catalog: ModuleCatalog;
  /** The kits Settings offers: the bundled ones, then the user's imports. Follow `kitsChanged` to redraw when they change. */
  readonly kits: KitLibrary;
  private readonly repository: SettingsRepository;
  private readonly settingsValue: Observable<AppSettings>;
  private readonly islandModeValue: Observable<IslandMode>;
  private readonly reduceMotionValue: Observable<boolean>;
  private readonly crashReportsValue: Observable<CrashReportConsent>;
  private readonly lastKitSwitchValue = new Observable<KitSwitchUndo | undefined>(undefined);
  private readonly kitsChangedValue = new Observable(0);
  private readonly hotkeyStatusValue: Observable<HotkeyStatus | undefined>;
  private readonly launchAtLoginErrorValue = new Observable<string | undefined>(undefined);
  private readonly kitAppliedEmitter = new Emitter<KitApplication>();
  private readonly setupRequestedEmitter = new Emitter<void>();
  private readonly channel: WindowChannel;
  private readonly store: DocumentStore | undefined;
  private readonly kitStore: ImportedKitStore | undefined;
  private readonly system: SystemIntegration | undefined;
  private readonly defaultKitID: string;
  private saving: Promise<void> = Promise.resolve();
  private saveQueued = false;
  private readonly stopListening: () => void;

  private constructor(
    private readonly defaults: Defaults,
    options: SettingsStoreOptions,
  ) {
    this.catalog = options.catalog;
    this.kits = options.kits;
    this.store = options.store;
    this.kitStore = options.kitStore;
    this.system = options.system;
    this.defaultKitID = options.defaultKitID ?? DEFAULT_KIT_ID;
    this.channel = options.channel ?? quietChannel;
    this.repository = new SettingsRepository(defaults, options.catalog, options.kits, this.defaultKitID);
    this.settingsValue = new Observable(this.repository.load(), settingsEqual);
    this.islandModeValue = new Observable<IslandMode>(readIslandMode(defaults));
    this.reduceMotionValue = new Observable(defaults.get(REDUCE_MOTION_KEY) === true);
    this.crashReportsValue = new Observable(parseCrashReportConsent(defaults.get(CRASH_REPORT_CONSENT_KEY)));
    this.hotkeyStatusValue = new Observable(options.hotkeyStatus ?? undefined);
    this.stopListening = this.channel.on((message) => this.receive(message));
  }

  /** Loads the saved preferences from `options.store` (or starts fresh in memory) and the imported kits. */
  static async load(options: SettingsStoreOptions): Promise<SettingsStore> {
    const defaults = options.store ? await loadDefaults(options.store, SETTINGS_DOCUMENT) : new InMemoryDefaults();
    if (options.kitStore) options.kits.setImported(await options.kitStore.load());
    return new SettingsStore(defaults, options);
  }

  /** A store that starts from `entries` in memory, for tests and snapshot runs. */
  static inMemory(options: Omit<SettingsStoreOptions, "store">, entries: JSONObject = {}): SettingsStore {
    return new SettingsStore(new InMemoryDefaults(entries), options);
  }

  /** Every preference; components read it with `useStore(settings.settings)`. */
  get settings(): Readable<AppSettings> {
    return this.settingsValue;
  }

  /** The settings now. */
  get current(): AppSettings {
    return this.settingsValue.get();
  }

  /** What the closed island shows (Windows' Auto, Always, or Only on hover or hotkey). */
  get islandMode(): Readable<IslandMode> {
    return this.islandModeValue;
  }

  /** Reduce Motion as turned on in Settings > Look (false follows Windows' own setting). */
  get reduceMotion(): Readable<boolean> {
    return this.reduceMotionValue;
  }

  /** Whether crash reports may go out: ask, always, or never. Nothing is sent in this build either way. */
  get crashReportConsent(): Readable<CrashReportConsent> {
    return this.crashReportsValue;
  }

  /** Bumped each time the kit library changes (an import, a removal, their undo), so the kit picker redraws. */
  get kitsChanged(): Readable<number> {
    return this.kitsChangedValue;
  }

  /** The global hotkey as the host last registered it; undefined before the host said. */
  get hotkeyStatus(): Readable<HotkeyStatus | undefined> {
    return this.hotkeyStatusValue;
  }

  /** Why the last Start with Windows change failed, for Settings. */
  get launchAtLoginError(): Readable<string | undefined> {
    return this.launchAtLoginErrorValue;
  }

  /** Sent after `settings` holds a kit the user just applied (switched to, reset or undone), in every window. */
  readonly kitApplied = this.kitAppliedEmitter.on;

  /** Sent in the island when Settings > Tabs asks to run first-run setup again. */
  readonly setupRequested = this.setupRequestedEmitter.on;

  /** The last kit switch, until it is undone or another one replaces it. */
  get lastKitSwitch(): Readable<KitSwitchUndo | undefined> {
    return this.lastKitSwitchValue;
  }

  /** Changes the settings; saved and posted to the other windows when anything differs. */
  update(change: (settings: AppSettings) => AppSettings): void {
    const next = change(this.current);
    if (settingsEqual(next, this.current)) return;
    this.settingsValue.set(next);
    this.persist();
  }

  setIslandMode(mode: IslandMode): void {
    if (mode === this.islandModeValue.get()) return;
    this.islandModeValue.set(mode);
    this.persist();
  }

  setReduceMotion(on: boolean): void {
    if (on === this.reduceMotionValue.get()) return;
    this.reduceMotionValue.set(on);
    this.persist();
  }

  setCrashReportConsent(consent: CrashReportConsent): void {
    if (consent === this.crashReportsValue.get()) return;
    this.crashReportsValue.set(consent);
    this.persist();
  }

  /** Whether onboarding already showed how to pin the tray icon. */
  get trayHintShown(): boolean {
    return this.defaults.get(TRAY_HINT_SHOWN_KEY) === true;
  }

  markTrayHintShown(): void {
    if (this.trayHintShown) return;
    this.defaults.set(TRAY_HINT_SHOWN_KEY, true);
    this.persist();
  }

  // Start with Windows

  /**
   * Turns Start with Windows on or off through the host first and records
   * the preference only once Windows accepted it, so the switch never lies.
   */
  async setLaunchAtLogin(enabled: boolean): Promise<void> {
    const system = this.system;
    if (system === undefined) {
      this.update((settings) => ({ ...settings, launchAtLogin: enabled }));
      return;
    }
    try {
      if (enabled) await system.autostartEnable();
      else await system.autostartDisable();
      this.launchAtLoginErrorValue.set(undefined);
    } catch (error) {
      this.launchAtLoginErrorValue.set(error instanceof Error ? error.message : String(error));
    }
    await this.refreshLaunchAtLogin();
  }

  /** Reads Start with Windows back from the system, since the user may have changed it in Windows' own settings. */
  async refreshLaunchAtLogin(): Promise<void> {
    const system = this.system;
    if (system === undefined) return;
    try {
      const enabled = await system.autostartIsEnabled();
      this.update((settings) => (settings.launchAtLogin === enabled ? settings : { ...settings, launchAtLogin: enabled }));
    } catch {
      /* The switch keeps showing the saved preference. */
    }
  }

  // The hotkey

  /** Records `hotkey` and registers it with the host, which says whether another app owns it. */
  async setHotkey(hotkey: Hotkey): Promise<HotkeyStatus | undefined> {
    this.update((settings) => ({ ...settings, hotkey }));
    return this.registerHotkey(hotkey);
  }

  /** Registers the saved hotkey when it isn't the one the host registered at launch. */
  async registerSavedHotkey(): Promise<void> {
    const wanted = hostShortcut(this.current.hotkey);
    const registered = this.hotkeyStatusValue.get();
    if (wanted === undefined || registered?.shortcut.toLowerCase() === wanted.toLowerCase()) return;
    await this.registerHotkey(this.current.hotkey);
  }

  /** Keeps no hotkey registered while the recorder listens, so pressing the current one is recorded instead of opening the island. */
  async suspendHotkey(suspended: boolean): Promise<void> {
    if (this.system === undefined) return;
    if (suspended) await this.system.setHotkey(null).catch(() => undefined);
    else await this.registerHotkey(this.current.hotkey);
  }

  private async registerHotkey(hotkey: Hotkey): Promise<HotkeyStatus | undefined> {
    const shortcut = hostShortcut(hotkey);
    if (this.system === undefined || shortcut === undefined) return undefined;
    let status: HotkeyStatus;
    try {
      status = await this.system.setHotkey(shortcut);
    } catch {
      status = { shortcut, registered: false };
    }
    this.hotkeyStatusValue.set(status);
    this.channel.post({ type: "hotkey", shortcut: status.shortcut, registered: status.registered });
    return status;
  }

  // Kits

  /** The kit the user picked (the default kit if it has gone missing). */
  get activeKit(): KitManifest | undefined {
    return this.kits.kit(this.current.kitID);
  }

  /** True when the tabs, previews and theme already match the active kit, so Reset to Kit Defaults is a no-op. */
  get usesKitDefaults(): boolean {
    const kit = this.activeKit;
    return kit === undefined ? true : usesKitDefaults(this.current, kit, this.catalog);
  }

  /** Switches to a kit with the user's answers to its questions; `undoKitSwitch` reverts it. */
  switchKit(id: string, answers: KitAnswers = {}): void {
    const kit = this.kits.get(id);
    if (kit === undefined) return;
    this.switchTo(kit, answers, {});
  }

  /** The first-run pick: applies `id`'s tabs for the user's answers even when it is already the default kit. */
  chooseKit(id: string, answers: KitAnswers = {}): void {
    const kit = this.kits.get(id) ?? this.activeKit;
    if (kit === undefined) return;
    this.apply(kit, kit.id === id ? answers : {}, "switched");
  }

  /** Puts the active kit's tabs back the way the kit sets them up for the answers the user gave. */
  resetToKitDefaults(): void {
    const kit = this.activeKit;
    if (kit === undefined) return;
    this.apply(kit, this.current.kitAnswers, "reset");
  }

  /** What switching to `kit` with `answers` would change, for the sheet Settings shows before applying an imported kit. */
  preview(kit: KitManifest, answers: KitAnswers = {}): KitChangePreview {
    return kitChangePreview(kit, this.current, this.catalog, answers);
  }

  /** What `kit` uses that this build skips, so the user can be told. */
  issues(kit: KitManifest): KitIssue[] {
    return kitIssues(kit, this.catalog);
  }

  /** True when kits can be imported in this run (not in demo or snapshot runs). */
  get canImportKits(): boolean {
    return this.kitStore !== undefined;
  }

  /** Reads and validates a kit file's text without saving or switching, so Settings can show what it changes first. */
  async inspectKit(text: string, fileName: string): Promise<KitInspection> {
    const kitStore = this.kitStore;
    if (kitStore === undefined) return { ok: false, error: { kind: "malformed", reason: "importing is off in this mode" } };
    const reserved = new Set(this.kits.ids.filter((id) => !isImportedKitID(id)));
    return kitStore.inspect(text, fileName, this.catalog, reserved);
  }

  /**
   * Saves an inspected kit into the user's kits, replacing an earlier
   * import with its id, and switches to it with `answers` unless they are
   * undefined. Undo removes the file again (or puts the replaced one back).
   */
  async installKit(candidate: KitImportCandidate, answers: KitAnswers | undefined): Promise<void> {
    const kitStore = this.kitStore;
    if (kitStore === undefined) throw new Error("importing is off in this mode");
    const id = candidate.kit.id;
    const previous = { [id]: await kitStore.savedText(id) };
    await kitStore.install(candidate);
    await this.reloadImportedKits();
    const kit = this.kits.get(id);
    if (answers !== undefined && kit !== undefined) {
      this.switchTo(kit, answers, previous);
    } else {
      /* Replaces any earlier switch's undo, so Undo never reverts that switch and deletes the file just imported. */
      this.lastKitSwitchValue.set({ kitState: kitState(this.current), kitName: candidate.kit.name, switchedKit: false, kitFiles: previous });
    }
  }

  /** True when the active kit was imported, so it can be removed. */
  get canRemoveActiveKit(): boolean {
    return this.kitStore !== undefined && isImportedKitID(this.current.kitID) && this.kits.get(this.current.kitID) !== undefined;
  }

  /** Deletes the active imported kit and falls back to the default kit. Undo puts the file and the tabs back. */
  async removeActiveKit(): Promise<void> {
    const kitStore = this.kitStore;
    const removed = this.activeKit;
    if (!this.canRemoveActiveKit || kitStore === undefined || removed === undefined) return;
    const previous = { [removed.id]: await kitStore.savedText(removed.id) };
    await kitStore.remove(removed.id);
    await this.reloadImportedKits();
    const fallback = this.kits.kit(this.defaultKitID);
    if (fallback !== undefined) this.switchTo(fallback, {}, previous, removed.name);
  }

  /**
   * Reverts the last kit switch, import or removal: the kit files it wrote
   * or deleted, then the kit, tabs and previews as they were, and modules
   * hear the previous kit again as an undo so they restore their own state.
   * An import that kept the tabs only takes its file back.
   */
  async undoKitSwitch(): Promise<void> {
    const undo = this.lastKitSwitchValue.get();
    if (undo === undefined) return;
    this.lastKitSwitchValue.set(undefined);
    const kitStore = this.kitStore;
    if (kitStore !== undefined && Object.keys(undo.kitFiles).length > 0) {
      for (const [id, text] of Object.entries(undo.kitFiles)) await kitStore.restore(text, id).catch(() => undefined);
      await this.reloadImportedKits();
    }
    if (!undo.switchedKit) return;
    this.update((settings) => withKitState(settings, undo.kitState));
    const kit = this.activeKit;
    if (kit !== undefined) this.announce({ kit, answers: this.current.kitAnswers, kind: "undo" });
  }

  /** Reads the imported kits again (after this or another window changed the files). */
  async reloadImportedKits(announce = true): Promise<void> {
    const kitStore = this.kitStore;
    if (kitStore === undefined) return;
    this.kits.setImported(await kitStore.load());
    this.kitsChangedValue.set(this.kitsChangedValue.get() + 1);
    /* The active kit may have gone, in which case the layout falls back to the default kit's. */
    this.settingsValue.set(this.repository.load());
    if (announce) this.channel.post({ type: "kits" });
  }

  /** Asks the island to run first-run setup again (Settings > Tabs > Run Setup Again). */
  requestSetup(): void {
    this.setupRequestedEmitter.emit();
    this.channel.post({ type: "runSetup" });
  }

  /** True when General's settings are already how a fresh install has them. */
  get usesGeneralDefaults(): boolean {
    return usesGeneralDefaults(this.current, this.activeKit, this.catalog);
  }

  /** General's "Reset to Defaults"; keeps tabs, theme and Start with Windows. */
  resetGeneral(): void {
    const hotkeyChanges = this.current.hotkey !== resetGeneral(this.current, this.activeKit, this.catalog).hotkey;
    this.update((settings) => resetGeneral(settings, this.activeKit, this.catalog));
    this.setIslandMode(DEFAULT_ISLAND_MODE);
    if (hotkeyChanges) void this.registerHotkey(this.current.hotkey);
  }

  /** The theme Look's "Reset to Default" picks: the active kit's. */
  get defaultTheme(): ThemeID {
    return defaultThemeForKit(this.activeKit);
  }

  /** Resolves once every change so far is on disk, for tests and before the window closes. */
  async flush(): Promise<void> {
    while (this.saveQueued) await this.saving;
    await this.saving;
  }

  /** Stops hearing the other windows. */
  close(): void {
    this.stopListening();
  }

  /** Applies `kit` as a switch and remembers what it replaced, so Undo can put it back. */
  private switchTo(kit: KitManifest, answers: KitAnswers, kitFiles: Readonly<Record<string, string | undefined>>, undoName?: string): void {
    const before = kitState(this.current);
    this.apply(kit, answers, "switched");
    this.lastKitSwitchValue.set({ kitState: before, kitName: undoName ?? kit.name, switchedKit: true, kitFiles });
  }

  private apply(kit: KitManifest, answers: KitAnswers, kind: KitApplicationKind): void {
    this.update((settings) => applyKit(settings, kit, this.catalog, answers));
    this.announce({ kit, answers, kind });
  }

  private announce(application: KitApplication): void {
    this.kitAppliedEmitter.emit(application);
    this.channel.post({
      type: "kitApplied",
      kitID: application.kit.id,
      answers: encodeAnswers(application.answers),
      kind: application.kind,
    });
  }

  /** Writes the preferences document, one write at a time, the last one carrying every change. */
  private persist(): void {
    this.repository.save(this.current);
    this.defaults.set(ISLAND_MODE_KEY, this.islandModeValue.get());
    this.defaults.set(REDUCE_MOTION_KEY, this.reduceMotionValue.get());
    this.defaults.set(CRASH_REPORT_CONSENT_KEY, this.crashReportsValue.get());
    const entries = this.defaults.entries();
    this.channel.post({ type: "settings", entries });
    const store = this.store;
    if (store === undefined || this.saveQueued) return;
    this.saveQueued = true;
    this.saving = this.saving
      .then(() => {
        this.saveQueued = false;
        return saveDefaults(store, SETTINGS_DOCUMENT, this.defaults);
      })
      .catch((error: unknown) => console.error("tabbi settings: could not save", error));
  }

  private receive(raw: unknown): void {
    if (!isJSONObject(raw)) return;
    const message = raw as unknown as SettingsMessage;
    switch (message.type) {
      case "settings":
        if (!isJSONObject(message.entries)) return;
        for (const key of Object.keys(this.defaults.entries())) this.defaults.remove(key);
        for (const [key, value] of Object.entries(message.entries)) this.defaults.set(key, value);
        /* The window that changed them saves them; this one only takes them on. */
        this.settingsValue.set(this.repository.load());
        this.islandModeValue.set(readIslandMode(this.defaults));
        this.reduceMotionValue.set(this.defaults.get(REDUCE_MOTION_KEY) === true);
        this.crashReportsValue.set(parseCrashReportConsent(this.defaults.get(CRASH_REPORT_CONSENT_KEY)));
        return;
      case "kitApplied": {
        const kit = this.kits.get(message.kitID);
        if (kit === undefined) return;
        const kind: KitApplicationKind = message.kind === "reset" || message.kind === "undo" ? message.kind : "switched";
        this.kitAppliedEmitter.emit({ kit, answers: decodeAnswers(message.answers), kind });
        return;
      }
      case "kits":
        void this.reloadImportedKits(false);
        return;
      case "hotkey":
        if (typeof message.shortcut === "string" && typeof message.registered === "boolean") {
          this.hotkeyStatusValue.set({ shortcut: message.shortcut, registered: message.registered });
        }
        return;
      case "runSetup":
        this.setupRequestedEmitter.emit();
        return;
      default:
        return;
    }
  }
}

function readIslandMode(defaults: Defaults): IslandMode {
  const mode = defaults.get(ISLAND_MODE_KEY);
  return isIslandMode(mode) ? mode : DEFAULT_ISLAND_MODE;
}
