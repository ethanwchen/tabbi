/*
 * Port of SettingsStore: the app's live preferences. Modules and the shell
 * read `settings` (and follow `kitApplied`); only Settings and onboarding
 * change them. Every change is saved through the core's SettingsRepository
 * into one preferences document (the Mac's UserDefaults domain) and posted
 * to the other windows, so a theme picked in the Settings window shows on
 * the island at once.
 *
 * Imported kits (ImportedKitStore) are not ported yet; the library holds the
 * bundled kits.
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
import type { KitAnswers } from "../core/kits/kitApplication";
import { DEFAULT_KIT_ID, type KitLibrary } from "../core/kits/kitLibrary";
import type { KitManifest } from "../core/kits/kitManifest";
import type { ModuleCatalog } from "../core/modules/moduleCatalog";
import { InMemoryDefaults, loadDefaults, saveDefaults, type Defaults } from "../core/persistence/defaults";
import { isJSONObject, type JSONObject } from "../core/persistence/json";
import type { DocumentStore } from "../core/persistence/documentStore";
import { SettingsRepository } from "../core/settings/settingsRepository";
import type { ThemeID } from "../core/themes/appTheme";
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

/** Port of SettingsStore.KitSwitchUndo: what the last kit switch replaced. */
export interface KitSwitchUndo {
  readonly kitState: KitState;
  /** The kit switched to, for the Undo button's tooltip. */
  readonly kitName: string;
}

/* What one window tells the others. */
type SettingsMessage =
  | { readonly type: "settings"; readonly entries: JSONObject }
  | { readonly type: "kitApplied"; readonly kitID: string; readonly answers: Readonly<Record<string, readonly string[]>>; readonly kind: KitApplicationKind };

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
}

export class SettingsStore {
  readonly catalog: ModuleCatalog;
  readonly kits: KitLibrary;
  private readonly repository: SettingsRepository;
  private readonly settingsValue: Observable<AppSettings>;
  private readonly islandModeValue: Observable<IslandMode>;
  private readonly lastKitSwitchValue = new Observable<KitSwitchUndo | undefined>(undefined);
  private readonly kitAppliedEmitter = new Emitter<KitApplication>();
  private readonly channel: WindowChannel;
  private readonly store: DocumentStore | undefined;
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
    this.channel = options.channel ?? quietChannel;
    this.repository = new SettingsRepository(defaults, options.catalog, options.kits, options.defaultKitID ?? DEFAULT_KIT_ID);
    this.settingsValue = new Observable(this.repository.load(), settingsEqual);
    const mode = defaults.get(ISLAND_MODE_KEY);
    this.islandModeValue = new Observable<IslandMode>(isIslandMode(mode) ? mode : DEFAULT_ISLAND_MODE);
    this.stopListening = this.channel.on((message) => this.receive(message));
  }

  /** Loads the saved preferences from `options.store` (or starts fresh in memory). */
  static async load(options: SettingsStoreOptions): Promise<SettingsStore> {
    const defaults = options.store ? await loadDefaults(options.store, SETTINGS_DOCUMENT) : new InMemoryDefaults();
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

  /** Sent after `settings` holds a kit the user just applied (switched to, reset or undone), in every window. */
  readonly kitApplied = this.kitAppliedEmitter.on;

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
    const before = kitState(this.current);
    this.apply(kit, answers, "switched");
    this.lastKitSwitchValue.set({ kitState: before, kitName: kit.name });
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

  /** Reverts the last kit switch: the kit, tabs, previews and theme as they were; modules hear the previous kit as an undo. */
  undoKitSwitch(): void {
    const undo = this.lastKitSwitchValue.get();
    if (undo === undefined) return;
    this.lastKitSwitchValue.set(undefined);
    this.update((settings) => withKitState(settings, undo.kitState));
    const kit = this.activeKit;
    if (kit !== undefined) this.announce({ kit, answers: this.current.kitAnswers, kind: "undo" });
  }

  /** True when General's settings are already how a fresh install has them. */
  get usesGeneralDefaults(): boolean {
    return usesGeneralDefaults(this.current, this.activeKit, this.catalog);
  }

  /** General's "Reset to Defaults"; keeps tabs, theme and Start with Windows. */
  resetGeneral(): void {
    this.update((settings) => resetGeneral(settings, this.activeKit, this.catalog));
    this.setIslandMode(DEFAULT_ISLAND_MODE);
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
    if (message.type === "settings" && isJSONObject(message.entries)) {
      for (const key of Object.keys(this.defaults.entries())) this.defaults.remove(key);
      for (const [key, value] of Object.entries(message.entries)) this.defaults.set(key, value);
      /* The window that changed them saves them; this one only takes them on. */
      this.settingsValue.set(this.repository.load());
      const mode = this.defaults.get(ISLAND_MODE_KEY);
      this.islandModeValue.set(isIslandMode(mode) ? mode : DEFAULT_ISLAND_MODE);
    } else if (message.type === "kitApplied") {
      const kit = this.kits.get(message.kitID);
      if (kit === undefined) return;
      const kind: KitApplicationKind = message.kind === "reset" || message.kind === "undo" ? message.kind : "switched";
      this.kitAppliedEmitter.emit({ kit, answers: decodeAnswers(message.answers), kind });
    }
  }
}
