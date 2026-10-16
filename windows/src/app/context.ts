/*
 * Port of ModuleContext: everything a module may use from the app, handed
 * to `create(context)`. Modules build and own their stores from it, so
 * adding a module never means editing the composition root. It gives read
 * access to settings and the active kit, the merged provider snapshot, the
 * activity log, shared services, the edition's storage, the host and a
 * logger, and nothing that reaches into another module.
 */

import { ActivityLogRepository } from "../core/activity/activityLogRepository";
import type { Edition } from "../core/editions/edition";
import { kitModuleSettings, type KitManifest } from "../core/kits/kitManifest";
import type { ModuleID } from "../core/modules/moduleId";
import { isEphemeral, type RunMode } from "../core/modules/runMode";
import type { JSONValue } from "../core/persistence/json";
import type { ProviderSnapshot } from "../core/providers/providerSnapshot";
import type { Instant } from "../core/time";
import type { Host, Startup } from "../host/host";
import { ActivityLog } from "./activityLog";
import type { EditionFolders } from "./editionStorage";
import { makeLogger, type LogSink, type Logger } from "./logger";
import type { ProviderHub } from "./providerHub";
import { serviceKey, type SharedServices } from "./sharedServices";
import type { KitApplication, SettingsStore } from "./settingsStore";
import type { Readable } from "./store";
import { hostChannel, quietChannel, type WindowChannel } from "./windowChannel";
import { ClosedPreview } from "./closedPreview";

/**
 * Which window the module runs in. The island runs and starts modules; the
 * Settings window creates them too, so their settings panes have a store to
 * read, but never starts them.
 */
export type WindowRole = "island" | "settings";

/** What every module's context shares: one per window, made by AppServices. */
export interface AppEnvironment {
  readonly edition: Edition;
  readonly settings: SettingsStore;
  readonly providers: ProviderHub;
  readonly shared: SharedServices;
  readonly runMode: RunMode;
  readonly storage: EditionFolders;
  readonly host: Host;
  readonly startup: Startup;
  readonly role: WindowRole;
  /** The clock, in seconds since 1970; snapshot runs pin it. */
  readonly now: () => Instant;
  /** The user's IANA time zone, read on every call so a zone change takes effect. */
  readonly timeZone: () => string;
  readonly logSink?: LogSink;
}

const ACTIVITY_LOG = serviceKey<ActivityLog>("app.activityLog");
const CLOSED_PREVIEW = serviceKey<ClosedPreview>("app.closedPreview");

export class ModuleContext {
  /** Logs under this module's id. */
  readonly logger: Logger;

  constructor(
    /** The module this context was made for. */
    readonly id: ModuleID,
    private readonly environment: AppEnvironment,
  ) {
    this.logger = makeLogger(id, environment.logSink);
  }

  /** The edition this app runs as. */
  get edition(): Edition {
    return this.environment.edition;
  }

  /** App settings and the kit library. Read them (and follow `kitApplied`); only Settings and onboarding change them. */
  get settings(): SettingsStore {
    return this.environment.settings;
  }

  /** What the enabled modules share, merged. Read it instead of another module's store. */
  get providers(): ProviderHub {
    return this.environment.providers;
  }

  /** The merged snapshot of what the enabled modules share; follow it with `useStore` or `subscribe`. */
  get snapshot(): Readable<ProviderSnapshot> {
    return this.environment.providers.snapshot;
  }

  /** App-wide services several modules use, created on first use (see sharedServices.ts). */
  get shared(): SharedServices {
    return this.environment.shared;
  }

  /** Live, demo data or snapshot rendering. Hand it to your store; never read `TABBI_DEMO` yourself. */
  get runMode(): RunMode {
    return this.environment.runMode;
  }

  /** Demo data: show realistic samples and touch no network, calendar, media session or CLI. */
  get isDemo(): boolean {
    return this.environment.runMode.isDemo;
  }

  /** A snapshot render: play no sound and save nothing. */
  get isSnapshot(): boolean {
    return this.environment.runMode.isSnapshot;
  }

  /**
   * Where this edition keeps its files. Put a module's files in a folder of
   * it (`storage.folder("Planner")`), never anywhere else; demo and snapshot
   * runs get storage that lives in memory.
   */
  get storage(): EditionFolders {
    return this.environment.storage;
  }

  /** The Windows host (storage, credentials, toasts, media, HTTP to allow-listed services). */
  get host(): Host {
    return this.environment.host;
  }

  /** What the host said at launch, such as a development Party server. */
  get startup(): Startup {
    return this.environment.startup;
  }

  /** The island (where modules run) or the Settings window (where only their settings panes draw). */
  get role(): WindowRole {
    return this.environment.role;
  }

  /** Now, in seconds since 1970. Read the clock here, never `Date.now()`, so snapshot runs can pin it. */
  now(): Instant {
    return this.environment.now();
  }

  /** The user's IANA time zone. */
  timeZone(): string {
    return this.environment.timeZone();
  }

  /** The kit the user has active now. */
  get activeKit(): KitManifest | undefined {
    return this.environment.settings.activeKit;
  }

  /** This module's `moduleSettings` section of the active kit; read it leniently, a value that doesn't fit keeps your default. */
  kitSettings(kit: KitManifest | undefined = this.activeKit): JSONValue | undefined {
    return kit === undefined ? undefined : kitModuleSettings(kit.defaults, this.id);
  }

  /**
   * Calls `listener` each time the user applies a kit, including
   * re-applying the active one, so the module can take on the kit's defaults
   * (on "undo", put back what the undone switch changed). Returns the
   * function that stops it.
   */
  kitApplied(listener: (application: KitApplication) => void): () => void {
    return this.environment.settings.kitApplied(listener);
  }

  /**
   * The one activity log. Log what this module did with records whose
   * `source` is `id`; read anyone's records by day.
   */
  get activityLog(): ActivityLog {
    const environment = this.environment;
    return environment.shared.resolve(ACTIVITY_LOG, () => {
      const repository = isEphemeral(environment.runMode)
        ? undefined
        : new ActivityLogRepository(environment.storage.root(), environment.timeZone());
      return new ActivityLog(repository, environment.timeZone);
    });
  }

  /**
   * Which closed-island previews can show right now, for a module that only
   * refreshes while someone can see it (Today reloads the calendar while the
   * meeting preview can show).
   */
  get closedPreview(): ClosedPreview {
    return this.environment.shared.resolve(CLOSED_PREVIEW, () => new ClosedPreview());
  }

  /**
   * A message channel to this module's twin in the other windows, on its own
   * topic. The Settings window's pane posts what it changed; the island's
   * store hears it and reloads.
   */
  channel(topic: string): WindowChannel {
    if (this.isSnapshot) return quietChannel;
    return hostChannel(this.environment.host, `module/${this.id}/${topic}`);
  }
}
