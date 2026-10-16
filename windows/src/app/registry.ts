/*
 * Port of ModuleRegistry: the modules this window runs, in canonical order,
 * keyed by id. It keeps each module's `start()` and `stop()` in step with
 * the enabled tabs through the core's ModuleLifecycle.
 */

import type { KitManifest } from "../core/kits/kitManifest";
import { ModuleCatalog } from "../core/modules/moduleCatalog";
import type { ModuleID } from "../core/modules/moduleId";
import { ModuleLifecycle, type ModuleLifecycleChanges } from "../core/modules/moduleLifecycle";
import type { OnboardingSetupStep } from "../core/onboarding/onboardingSetupStep";
import type { ModuleProvision } from "../core/providers/moduleProvision";
import type { ProvidedAction } from "../core/providers/progressItem";
import type { ComponentType } from "react";
import type { Logger } from "./logger";
import type { DefinedModule, SetupStepProps, TabbiModule } from "./module";
import { constant, derived, type Readable } from "./store";
import type { NotchTakeover } from "./takeover";

export class ModuleRegistry {
  /** Registered modules, in canonical order; a later duplicate id is left out. */
  readonly modules: readonly TabbiModule[];
  /** The registered modules' descriptors, for layouts, kit validation and the tab bar. */
  readonly catalog: ModuleCatalog;
  private readonly index: ReadonlyMap<ModuleID, TabbiModule>;
  private readonly lifecycle = new ModuleLifecycle();

  constructor(
    modules: readonly TabbiModule[],
    private readonly logger?: Logger,
  ) {
    const index = new Map<ModuleID, TabbiModule>();
    const unique: TabbiModule[] = [];
    for (const module of modules) {
      if (index.has(module.descriptor.id)) continue;
      index.set(module.descriptor.id, module);
      unique.push(module);
    }
    this.modules = unique;
    this.index = index;
    this.catalog = new ModuleCatalog(unique.map((module) => module.descriptor));
    const duplicates = new ModuleCatalog(modules.map((module) => module.descriptor)).duplicateIDs;
    /* Two modules claiming one id means one of them silently disappears: a module list mistake to fix, not to hide. */
    if (duplicates.length > 0) logger?.error(`Two modules share an id: ${duplicates.join(", ")}`);
    this.takeover = this.makeTakeover();
  }

  get(id: ModuleID): TabbiModule | undefined {
    return this.index.get(id);
  }

  /** The registered module made by `type`, with its own members, if this build has it. */
  instance<M extends TabbiModule>(type: DefinedModule<M>): M | undefined {
    return this.index.get(type.descriptor.id) as M | undefined;
  }

  /** The module's shared values, or undefined when it shares nothing. */
  provision(id: ModuleID): Readable<ModuleProvision> | undefined {
    return this.index.get(id)?.provision;
  }

  /**
   * The setup view for `step` from the first module in `ids` (tab order)
   * that declares the step and draws one, so a step two modules share is set
   * up once.
   */
  setupView(step: OnboardingSetupStep, ids: readonly ModuleID[]): ComponentType<SetupStepProps> | undefined {
    for (const id of ids) {
      const module = this.index.get(id);
      if (module === undefined || !module.descriptor.setup.some((declared) => declared.id === step.id)) continue;
      const view = module.setupView?.(step);
      if (view !== undefined) return view;
    }
    return undefined;
  }

  /** Hands `action` to the module that offered it; ignored unless that module is running, so a stale preview never wakes a module the user turned off. */
  perform(action: ProvidedAction, id: ModuleID): void {
    if (!this.running.includes(id)) return;
    this.index.get(id)?.perform?.(action);
  }

  /**
   * Hands a `tabbi://` link to the first module (in canonical order) that
   * takes it, and names that module, so the island can open on its tab;
   * undefined when none does. Every module is asked, running or not, since
   * a link may be what turns a module on.
   */
  openLink(url: string): ModuleID | undefined {
    for (const module of this.modules) {
      try {
        if (module.openLink?.(url) === true) return module.descriptor.id;
      } catch (error) {
        this.logger?.error(`${module.descriptor.id} failed to open a link`, error);
      }
    }
    return undefined;
  }

  /**
   * The flow filling the open island, from the first module that has one
   * (in canonical order); undefined while none does. It follows every
   * module's own takeover, so an invite shows the moment Party raises it.
   */
  readonly takeover: Readable<NotchTakeover | undefined>;

  private makeTakeover(): Readable<NotchTakeover | undefined> {
    const sources = this.modules.flatMap((module) => (module.takeover === undefined ? [] : [module.takeover]));
    if (sources.length === 0) return constant(undefined);
    return derived(sources, () => sources.map((source) => source.get()).find((takeover) => takeover !== undefined));
  }

  /** True while every module's kit-derived state matches `kit`, enabled or not. */
  usesKitDefaults(kit: KitManifest): Readable<boolean> {
    const parts = this.modules.flatMap((module) => {
      const part = module.usesKitDefaults?.(kit);
      return part === undefined ? [] : [part];
    });
    if (parts.length === 0) return constant(true);
    return derived(parts, () => parts.every((part) => part.get()));
  }

  /** Ids of the modules currently started, in the order they started. */
  get running(): readonly ModuleID[] {
    return this.lifecycle.running;
  }

  /** Starts newly enabled modules and stops disabled ones. Ids with no registered module are ignored. */
  update(enabled: readonly ModuleID[]): void {
    this.apply(this.lifecycle.update(enabled.filter((id) => this.index.has(id))));
  }

  /** Stops every running module, e.g. when the app quits. */
  stopAll(): void {
    this.apply(this.lifecycle.stopAll());
  }

  private apply(changes: ModuleLifecycleChanges): void {
    for (const id of changes.stop) this.call(id, "stop");
    for (const id of changes.start) this.call(id, "start");
  }

  /* One module failing to start or stop must not keep the others from running. */
  private call(id: ModuleID, phase: "start" | "stop"): void {
    try {
      this.index.get(id)?.[phase]?.();
    } catch (error) {
      this.logger?.error(`${id} failed to ${phase}`, error);
    }
  }
}
