import { kitLayout, selectingAnswer, type KitAnswers } from "../kits/kitApplication";
import { deepEqual, type KitManifest, type KitQuestion } from "../kits/kitManifest";
import type { ModuleCatalog } from "../modules/moduleCatalog";
import type { ModuleID } from "../modules/moduleId";
import { ModuleLayout } from "../modules/moduleLayout";
import type { OnboardingExtra } from "./onboardingExtra";
import type { OnboardingSetupStep } from "./onboardingSetupStep";

/** Where the flow is. */
export type OnboardingStage =
  /** Say what to call the user; the caller saves the name as it is typed. */
  | { readonly kind: "name" }
  /** Pick a kit or start from scratch. */
  | { readonly kind: "kit" }
  /** One of the chosen kit's onboarding questions, by id. */
  | { readonly kind: "question"; readonly id: string }
  /** Turn tabs on or off and reorder them. */
  | { readonly kind: "modules" }
  /** A module's just-in-time setup step, by id. */
  | { readonly kind: "setup"; readonly id: string }
  /** One screen that mentions the optional extras, last. */
  | { readonly kind: "extras" }
  /** Done; the caller applies `kit`, `answers` and `layout`. */
  | { readonly kind: "finished" };

export function sameStage(a: OnboardingStage, b: OnboardingStage): boolean {
  if (a.kind !== b.kind) return false;
  if ((a.kind === "question" || a.kind === "setup") && (b.kind === "question" || b.kind === "setup")) return a.id === b.id;
  return true;
}

export interface OnboardingFlowOptions {
  /** The tabs to start from (the current ones when re-running). */
  readonly layout: ModuleLayout;
  /** The kit to preselect, such as the edition's or the active one. */
  readonly kit?: KitManifest;
  /** The answers to preselect when re-running with that kit. */
  readonly answers?: KitAnswers;
  /** Open on the name step before the kit step. */
  readonly asksName?: boolean;
  /** The optional extras to mention on the last screen. */
  readonly extras?: readonly OnboardingExtra[];
}

/**
 * Port of OnboardingFlow: the steps of first-run onboarding as plain state,
 * so the order and the skipping rules are testable without a window. The
 * user says what to call them, picks a kit (or starts from scratch), answers
 * the kit's questions, turns tabs on or off, then sees only the setup steps
 * the enabled modules declare, each asked once, and then one screen of
 * extras when any apply. Every step can be skipped and `finish()` ends the
 * flow from anywhere.
 */
export class OnboardingFlow {
  readonly catalog: ModuleCatalog;
  readonly asksName: boolean;
  readonly extras: readonly OnboardingExtra[];
  private stageValue: OnboardingStage;
  private kitValue: KitManifest | undefined;
  private answersValue: Record<string, ReadonlySet<string>>;
  private layoutValue: ModuleLayout;
  private scratch = false;

  constructor(catalog: ModuleCatalog, options: OnboardingFlowOptions) {
    this.catalog = catalog;
    this.layoutValue = options.layout.clone();
    this.kitValue = options.kit;
    this.answersValue = { ...(options.answers ?? {}) };
    this.asksName = options.asksName ?? false;
    this.extras = options.extras ?? [];
    this.stageValue = this.asksName ? { kind: "name" } : { kind: "kit" };
  }

  get stage(): OnboardingStage {
    return this.stageValue;
  }

  /** The chosen kit; undefined before the first step and after Start from Scratch. */
  get kit(): KitManifest | undefined {
    return this.kitValue;
  }

  /** The answers to the chosen kit's questions. */
  get answers(): KitAnswers {
    return this.answersValue;
  }

  /** The tabs onboarding will turn on, in tab bar order (a copy; change them through the flow). */
  get layout(): ModuleLayout {
    return this.layoutValue.clone();
  }

  /** True once the user picked Start from Scratch on the kit step. */
  get startedFromScratch(): boolean {
    return this.scratch;
  }

  /** Every stage the flow will go through for the current choices, so progress dots count what is left. */
  get stages(): OnboardingStage[] {
    return [
      ...(this.asksName ? [{ kind: "name" } as const] : []),
      { kind: "kit" },
      ...(this.kitValue?.onboarding.map((question) => ({ kind: "question", id: question.id }) as const) ?? []),
      { kind: "modules" },
      ...this.setupSteps.map((step) => ({ kind: "setup", id: step.id }) as const),
      ...(this.currentExtras.length === 0 ? [] : [{ kind: "extras" } as const]),
    ];
  }

  /** The extras that apply to the tabs that are on: app-wide ones always, a tab's own only while it is on. */
  get currentExtras(): OnboardingExtra[] {
    const enabled = new Set(this.layoutValue.enabled);
    return this.extras.filter((extra) => extra.module === undefined || enabled.has(extra.module));
  }

  /** The setup steps the enabled tabs need: each once, by rank, ties in tab order. */
  get setupSteps(): OnboardingSetupStep[] {
    const seen = new Set<string>();
    const steps: OnboardingSetupStep[] = [];
    for (const id of this.layoutValue.enabled) {
      for (const step of this.catalog.descriptor(id).setup) {
        if (seen.has(step.id)) continue;
        seen.add(step.id);
        steps.push(step);
      }
    }
    /* Array sort is stable, so equal ranks keep tab order. */
    return steps.sort((a, b) => a.rank - b.rank);
  }

  /** The question the flow is on, if it is on one. */
  get currentQuestion(): KitQuestion | undefined {
    const stage = this.stageValue;
    if (stage.kind !== "question") return undefined;
    return this.kitValue?.onboarding.find((question) => question.id === stage.id);
  }

  /** The setup step the flow is on, if it is on one. */
  get currentSetupStep(): OnboardingSetupStep | undefined {
    const stage = this.stageValue;
    if (stage.kind !== "setup") return undefined;
    return this.setupSteps.find((step) => step.id === stage.id);
  }

  /** The current stage's position in `stages` (0-based), for progress dots. */
  get stageIndex(): number {
    const stages = this.stages;
    if (this.stageValue.kind === "finished") return stages.length;
    const index = stages.findIndex((stage) => sameStage(stage, this.stageValue));
    return index < 0 ? 0 : index;
  }

  get canGoBack(): boolean {
    const first = this.stages[0];
    return (first === undefined || !sameStage(this.stageValue, first)) && this.stageValue.kind !== "finished";
  }

  /**
   * Picks `kit` and moves on. A different kit than before starts over from
   * its tabs and clears earlier answers; the same one keeps what the user
   * already changed. It answers the kit step, even from the name step.
   */
  choose(kit: KitManifest): void {
    if (!deepEqual(kit, this.kitValue) || this.scratch) {
      this.kitValue = kit;
      this.answersValue = {};
      this.layoutValue = kitLayout(kit, this.catalog);
    }
    this.scratch = false;
    this.stageValue = { kind: "kit" };
    this.next();
  }

  /** Skips the kits: the next step starts with only the first tab on. */
  startFromScratch(): void {
    if (!this.scratch) {
      this.kitValue = undefined;
      this.answersValue = {};
      const ids = this.catalog.ids;
      this.layoutValue = new ModuleLayout(ids, ids.slice(1), this.catalog);
    }
    this.scratch = true;
    this.stageValue = { kind: "kit" };
    this.next();
  }

  /**
   * Picks `answerID` for the current question; the kit's answers decide
   * which tabs are on, so this replaces tab changes made since. A
   * single-choice question moves on once answered.
   */
  answer(answerID: string): void {
    const kit = this.kitValue;
    const question = this.currentQuestion;
    if (!kit || !question) return;
    const picked = selectingAnswer(question, answerID, this.answersValue[question.id] ?? new Set());
    this.answersValue = { ...this.answersValue, [question.id]: picked };
    this.layoutValue = kitLayout(kit, this.catalog, this.answersValue);
    if (!question.allowsMultiple && picked.size > 0) this.next();
  }

  /** Turns a tab on or off; refuses to turn off the last one. */
  setEnabled(module: ModuleID, isEnabled: boolean): boolean {
    return this.layoutValue.setEnabled(module, isEnabled);
  }

  /** Reorders tabs, with onMove semantics over `layout.order`. */
  move(source: Iterable<number>, destination: number): void {
    this.layoutValue.move(source, destination);
  }

  /** Moves on to the next stage, or finishes after the last one. Skipping a step is the same move. */
  next(): void {
    const all = this.stages;
    const index = all.findIndex((stage) => sameStage(stage, this.stageValue));
    const following = index < 0 ? undefined : all[index + 1];
    this.stageValue = following ?? { kind: "finished" };
  }

  /** Goes back one stage; does nothing on the first one or once finished. */
  back(): void {
    if (!this.canGoBack) return;
    const all = this.stages;
    const index = all.findIndex((stage) => sameStage(stage, this.stageValue));
    const previous = index > 0 ? all[index - 1] : undefined;
    if (previous) this.stageValue = previous;
  }

  /** Ends onboarding with what has been chosen so far. */
  finish(): void {
    this.stageValue = { kind: "finished" };
  }
}
