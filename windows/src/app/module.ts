/*
 * Port of NotchModule: one tab of the island, its metadata, its panel and
 * its lifecycle. Each feature implements it in its own `src/modules/<id>/`
 * folder and is listed once in `src/modules/moduleList.ts`, so adding a
 * module never means editing a switch in shared code.
 */

import type { ComponentType } from "react";
import type { KitManifest } from "../core/kits/kitManifest";
import type { ModuleDescriptor } from "../core/modules/moduleDescriptor";
import type { ModuleID } from "../core/modules/moduleId";
import type { OnboardingSetupStep } from "../core/onboarding/onboardingSetupStep";
import type { ModuleProvision } from "../core/providers/moduleProvision";
import type { ProvidedAction } from "../core/providers/progressItem";
import type { ModuleContext } from "./context";
import type { Readable } from "./store";
import type { NotchTakeover } from "./takeover";

/** What a setup step's view gets: `done` moves first-run onboarding on. */
export interface SetupStepProps {
  readonly step: OnboardingSetupStep;
  readonly done: () => void;
}

/** The closed island's two wings while music is the live activity (the Mac's `nowPlayingLeading` and `nowPlayingTrailing`). */
export interface MusicWings {
  readonly Leading: ComponentType;
  readonly Trailing: ComponentType;
}

/**
 * A running module, made once per window by its `ModuleType.create`. Only
 * `descriptor` and `Panel` are required; every other member has the Mac's
 * default (nothing to share, nothing to start).
 */
export interface TabbiModule {
  /** The same descriptor as the type's, so code holding an instance can read it. */
  readonly descriptor: ModuleDescriptor;

  /**
   * The panel shown while this tab is selected, laid out inside the fixed
   * canvas (the panel size's canvas minus the header and insets, 496 x 180
   * at Regular). Make it once in `create`, closing over the module's store,
   * so its identity never changes.
   */
  readonly Panel: ComponentType;

  /**
   * The module's own options, which open from its Options button in
   * Settings > Tabs; undefined when it has nothing beyond its on/off switch.
   * It draws in the Settings window, where the module is created but never
   * started (`context.role` is "settings").
   */
  readonly SettingsPane?: ComponentType;

  /**
   * The view for one of `descriptor.setup`'s steps inside first-run
   * onboarding, fitted to the panel canvas; undefined shows a neutral card
   * that points to the module's tab.
   */
  setupView?(step: OnboardingSetupStep): ComponentType<SetupStepProps> | undefined;

  /**
   * Called when the module becomes enabled (at launch, or when the user or a
   * kit turns it on). Start background work the module needs while its panel
   * is closed here; panel-only work belongs in the panel's effects.
   */
  start?(): void;
  /** Called when the module is turned off or the app quits. Undo `start()`. */
  stop?(): void;

  /**
   * What this module shares with Today, the ticker and the pet, re-published
   * whenever it changes; undefined when it shares nothing. `ProviderHub`
   * merges the enabled modules' values.
   */
  readonly provision?: Readable<ModuleProvision>;

  /**
   * Whether the state this module takes from a kit's defaults still matches
   * `kit`, so Settings knows whether Reset to Kit Defaults has work to do;
   * undefined when the module keeps nothing from a kit beyond the layout.
   */
  usesKitDefaults?(kit: KitManifest): Readable<boolean> | undefined;

  /** Runs an action this module put on something it shares (a progress goal's one-click action). Unknown ids are ignored. */
  perform?(action: ProvidedAction): void;

  /**
   * A tabbi:// link the host received (an invite, a sign-in callback).
   * Returns true when this module took it; the island then opens on the
   * module's tab. Asked whether or not the module is running, since a link
   * may be what turns it on (Party's invite flow offers that).
   */
  openLink?(url: string): boolean;

  /**
   * A flow this module fills the whole open island with for a while (the
   * Mac's NotchTakeover, which Party uses for an invite's confirmation);
   * undefined while it has none. Only the first running module's shows.
   */
  readonly takeover?: Readable<NotchTakeover | undefined>;

  /** The closed island's wings while this module is playing music; undefined draws the shared music glyphs. */
  readonly musicWings?: MusicWings;

  /**
   * Puts the module's store into a named state for the snapshot harness
   * (`?snapshot=open:<id>:<state>`); every name in `ModuleType.snapshotStates`
   * must be handled. Only called in snapshot runs.
   */
  showSnapshotState?(state: string): void | Promise<void>;
}

/**
 * A module's type: its static descriptor (known before anything runs, so
 * layouts, kits and the tab bar can be built) and how to make it. The Mac's
 * `NotchModule.Type`.
 */
export interface ModuleType {
  readonly descriptor: ModuleDescriptor;
  /** Builds the module once per window. Build the store here and follow what the context offers; start work in `start()`. */
  create(context: ModuleContext): TabbiModule;
  /** Extra named states the snapshot harness renders besides the default one, such as "empty" or "running". */
  readonly snapshotStates?: readonly string[];
}

/**
 * A module type that knows the shape of its instances, so code holding the
 * type can reach the module's own members (its store) through
 * `ModuleRegistry.instance(type)`, the Mac's `modules.module(Type.self)`.
 */
export interface DefinedModule<M extends TabbiModule> extends ModuleType {
  create(context: ModuleContext): M;
}

/**
 * Declares a module type: its descriptor and how to make it.
 *
 * ```ts
 * export const LeetCodeModule = defineModule(LEETCODE_DESCRIPTOR, (context) => {
 *   const store = new LeetCodeStore(context);
 *   return { store, Panel: () => <LeetCodePanel store={store} />, provision: mapped(store, () => store.provision()) };
 * });
 * ```
 */
export function defineModule<M extends Omit<TabbiModule, "descriptor">>(
  descriptor: ModuleDescriptor,
  create: (context: ModuleContext) => M,
  options: { readonly snapshotStates?: readonly string[] } = {},
): DefinedModule<M & { readonly descriptor: ModuleDescriptor }> {
  return {
    descriptor,
    /* Assigned rather than spread, so a module written as a class keeps its prototype's methods. */
    create: (context) => Object.assign(create(context), { descriptor }),
    ...(options.snapshotStates === undefined ? {} : { snapshotStates: options.snapshotStates }),
  };
}

/** The ids of `types`, in list order. */
export function moduleIDs(types: readonly ModuleType[]): ModuleID[] {
  return types.map((type) => type.descriptor.id);
}
