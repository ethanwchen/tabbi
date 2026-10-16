/*
 * Port of AppServices: the composition root, created once per window. It
 * loads the settings, creates every listed module with its own context,
 * attaches the provider hub that merges what they share and, in the island,
 * the ticker. Adding a module never touches this file; list it in
 * src/modules/moduleList.ts.
 */

import { BUNDLED_KITS } from "../core/kits/bundledKits";
import { ImportedKitStore } from "../core/kits/importedKitStore";
import type { KitLibrary } from "../core/kits/kitLibrary";
import { editionCatalog, type Edition } from "../core/editions/edition";
import { TABBI_EDITION } from "../core/editions/bundledEditions";
import { ModuleCatalog } from "../core/modules/moduleCatalog";
import { DEMO_RUN_MODE, isEphemeral, type RunMode } from "../core/modules/runMode";
import type { Instant } from "../core/time";
import type { Host, Startup } from "../host/host";
import { WallClockAlarm } from "../ui/kit/clock";
import type { ActivityLog } from "./activityLog";
import { ModuleContext, type AppEnvironment, type WindowRole } from "./context";
import { EditionFolders } from "./editionStorage";
import { makeLogger, type LogSink } from "./logger";
import type { ModuleType } from "./module";
import { ProviderHub } from "./providerHub";
import { ModuleRegistry } from "./registry";
import { SettingsStore } from "./settingsStore";
import { SharedServices } from "./sharedServices";
import type { Observable } from "./store";
import { takeoverSlot, type NotchTakeover } from "./takeover";
import { TickerStore, type TickerAlarm } from "./tickerStore";
import { hostChannel, quietChannel } from "./windowChannel";

export interface AppServicesOptions {
  readonly host: Host;
  readonly startup: Startup;
  /** The modules to create, `MODULE_LIST` in the app. */
  readonly moduleTypes: readonly ModuleType[];
  readonly role: WindowRole;
  /** Live, demo or snapshot; by default demo when the host says `TABBI_DEMO=1`, live otherwise. */
  readonly runMode?: RunMode;
  readonly edition?: Edition;
  readonly kits?: KitLibrary;
  /** Settings to start from instead of the saved ones (snapshot runs pick a kit and theme this way). */
  readonly settingsEntries?: Readonly<Record<string, unknown>>;
  readonly now?: () => Instant;
  readonly timeZone?: () => string;
  /** Makes the ticker's wake-up alarm; a wall-clock alarm by default. */
  readonly alarm?: (fire: () => void) => TickerAlarm;
  readonly logSink?: LogSink;
}

const systemTimeZone = () => Intl.DateTimeFormat().resolvedOptions().timeZone;

function wallClockAlarm(fire: () => void): TickerAlarm {
  const alarm = new WallClockAlarm(fire);
  return {
    schedule: (at) => alarm.schedule(at * 1000),
    cancel: () => alarm.cancel(),
    dispose: () => alarm.dispose(),
  };
}

export class AppServices {
  readonly settings: SettingsStore;
  /** Every module this window has, created from the module list. */
  readonly modules: ModuleRegistry;
  /** What the enabled modules share. */
  readonly providers: ProviderHub;
  readonly shared: SharedServices;
  /** The closed island's preview; only the island has one. */
  readonly ticker: TickerStore | undefined;
  readonly environment: AppEnvironment;
  /** What fills the open island instead of the tabs (first-run setup, the weekly recap), or undefined for the tabs: the shared `takeoverSlot`. */
  readonly takeover: Observable<NotchTakeover | undefined>;
  private readonly stops: (() => void)[] = [];

  private constructor(environment: AppEnvironment, types: readonly ModuleType[], alarm: (fire: () => void) => TickerAlarm) {
    this.environment = environment;
    this.settings = environment.settings;
    this.providers = environment.providers;
    this.shared = environment.shared;
    this.takeover = takeoverSlot(environment.shared);
    /* Types the edition leaves out are never created, so they run no code at all. */
    const available = types.filter((type) => environment.settings.catalog.contains(type.descriptor.id));
    this.modules = new ModuleRegistry(
      available.map((type) => type.create(new ModuleContext(type.descriptor.id, environment))),
      makeLogger("app", environment.logSink),
    );
    this.providers.attach((id) => this.modules.provision(id));

    const follow = () => {
      const enabled = this.settings.current.modules.enabled;
      /* The Settings window shows panes; only the island runs modules. */
      if (environment.role === "island") this.modules.update(enabled);
      this.providers.update(enabled);
    };
    follow();
    this.stops.push(this.settings.settings.subscribe(follow));

    this.ticker =
      environment.role === "island"
        ? new TickerStore({
            settings: this.settings.settings,
            snapshot: this.providers.snapshot,
            catalog: this.settings.catalog,
            preview: new ModuleContext("app", environment).closedPreview,
            now: environment.now,
            alarm,
          })
        : undefined;
  }

  /** Loads the settings and creates every module for this window. */
  static async create(options: AppServicesOptions): Promise<AppServices> {
    const runMode = options.runMode ?? (options.startup.demo ? DEMO_RUN_MODE : { isDemo: false, isSnapshot: false });
    const edition = options.edition ?? TABBI_EDITION;
    const storage = isEphemeral(runMode) ? EditionFolders.ephemeral() : EditionFolders.live(options.host);
    const catalog = editionCatalog(edition, new ModuleCatalog(options.moduleTypes.map((type) => type.descriptor)));
    const kits = options.kits ?? BUNDLED_KITS;
    const settingsOptions = {
      catalog,
      kits,
      defaultKitID: edition.defaultKitID,
      channel: runMode.isSnapshot ? quietChannel : hostChannel(options.host, "settings"),
      hotkeyStatus: options.startup.hotkey,
    };
    /* Live runs keep imported kits beside the settings and drive Start with Windows and the hotkey through the host. */
    const live = options.settingsEntries === undefined && !isEphemeral(runMode);
    const settings = live
      ? await SettingsStore.load({ ...settingsOptions, store: storage.root(), kitStore: new ImportedKitStore(storage.root()), system: options.host })
      : SettingsStore.inMemory(settingsOptions, JSON.parse(JSON.stringify(options.settingsEntries ?? {})));
    /* The host registers the default shortcut at launch; the island puts the user's own in its place. */
    if (live && options.role === "island") void settings.registerSavedHotkey();
    const now = options.now ?? (() => Date.now() / 1000);
    const environment: AppEnvironment = {
      edition,
      settings,
      providers: new ProviderHub(now),
      shared: new SharedServices(),
      runMode,
      storage,
      host: options.host,
      startup: options.startup,
      role: options.role,
      now,
      timeZone: options.timeZone ?? systemTimeZone,
      ...(options.logSink === undefined ? {} : { logSink: options.logSink }),
    };
    return new AppServices(environment, options.moduleTypes, options.alarm ?? wallClockAlarm);
  }

  /** The one activity log, for the app's own readers (streaks, the recap). */
  get activityLog(): ActivityLog {
    return new ModuleContext("app", this.environment).activityLog;
  }

  /** Stops every module and follower, e.g. when the window closes. */
  dispose(): void {
    for (const stop of this.stops) stop();
    this.modules.stopAll();
    this.providers.detachAll();
    this.ticker?.dispose();
    this.settings.close();
  }
}
