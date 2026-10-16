/*
 * Port of OnboardingStore: runs first-run setup inside the island. It holds
 * the core's OnboardingFlow (kit, questions, tabs, each enabled module's
 * setup step, the extras) while it runs and applies what the user picked to
 * the settings store as soon as the flow leaves the tab step, so the setup
 * steps after it build on the picked kit rather than being replaced by its
 * defaults at the end.
 *
 * Windows adds two steps of its own after the flow's, kept out of the core
 * so the fixture-tested flow stays the Mac's: "Start with Windows" (an
 * opt-in switch, off until the user turns it on) and "Pin the tray icon"
 * (how to drag the icon out of the overflow, shown once and never again).
 */

import type { AppServices } from "../../app/appServices";
import { Store } from "../../app/store";
import { sameKitAnswers } from "../../core/kits/kitApplication";
import { settingsCleanedName } from "../../core/settings/appSettings";
import { ALL_ONBOARDING_EXTRAS, ONBOARDING_EXTRAS, type OnboardingExtra } from "../../core/onboarding/onboardingExtra";
import { OnboardingFlow, sameStage, type OnboardingStage } from "../../core/onboarding/onboardingFlow";

/** A step only Windows asks, after the flow's own. */
export type WindowsOnboardingStage = { readonly kind: "startWithWindows" } | { readonly kind: "trayIcon" };

/** Any step of the Windows onboarding: the core flow's, or one of Windows' own. */
export type OnboardingStep = OnboardingStage | WindowsOnboardingStage;

/**
 * The Mac's extras that apply on Windows: the daily reminder and invite
 * links. The desktop widget and Apple Account sync don't exist here yet.
 */
export const WINDOWS_ONBOARDING_EXTRAS: readonly OnboardingExtra[] = ALL_ONBOARDING_EXTRAS.filter(
  (extra) => extra === ONBOARDING_EXTRAS.reminder || extra === ONBOARDING_EXTRAS.invites,
);

export interface OnboardingState {
  /** The running flow; undefined while onboarding is not showing. */
  readonly flow: OnboardingFlow | undefined;
  /** The Windows steps this run asks, after the flow's. */
  readonly windowsSteps: readonly WindowsOnboardingStage[];
  /** Which Windows step is showing; undefined while the flow's own steps are. */
  readonly windowsIndex: number | undefined;
}

export function sameStep(a: OnboardingStep, b: OnboardingStep): boolean {
  if (isWindowsStage(a) || isWindowsStage(b)) return a.kind === b.kind;
  return sameStage(a, b);
}

export function isWindowsStage(step: OnboardingStep): step is WindowsOnboardingStage {
  return step.kind === "startWithWindows" || step.kind === "trayIcon";
}

/** Past the kit, questions and tabs: what was picked should be in place. */
function appliesChoices(stage: OnboardingStage): boolean {
  return stage.kind === "setup" || stage.kind === "extras" || stage.kind === "finished";
}

export class OnboardingStore extends Store<OnboardingState> {
  constructor(private readonly app: AppServices) {
    super({ flow: undefined, windowsSteps: [], windowsIndex: undefined });
  }

  get isActive(): boolean {
    return this.state.flow !== undefined;
  }

  /**
   * Starts the flow from the current tabs and kit, so re-running it from
   * Settings begins where the user is now. It opens on the name step on the
   * first run, and on a re-run only while no name is set. The tray hint is
   * asked once; Start with Windows every run, since it is one switch.
   */
  start(): void {
    const settings = this.app.settings;
    const current = settings.current;
    const flow = new OnboardingFlow(settings.catalog, {
      layout: current.modules,
      ...(settings.activeKit === undefined ? {} : { kit: settings.activeKit }),
      answers: current.hasChosenKit ? current.kitAnswers : {},
      asksName: !current.hasChosenKit || settingsCleanedName(current) === undefined,
      extras: WINDOWS_ONBOARDING_EXTRAS,
    });
    const windowsSteps: WindowsOnboardingStage[] = [{ kind: "startWithWindows" }];
    if (!settings.trayHintShown) windowsSteps.push({ kind: "trayIcon" });
    this.changed({ flow, windowsSteps, windowsIndex: undefined });
  }

  /** Shows `flow` at a given step as it is, without applying anything; for snapshots. */
  show(flow: OnboardingFlow | undefined, windowsStep?: WindowsOnboardingStage["kind"]): void {
    const windowsSteps: WindowsOnboardingStage[] = [{ kind: "startWithWindows" }, { kind: "trayIcon" }];
    const windowsIndex = windowsStep === undefined ? undefined : windowsSteps.findIndex((step) => step.kind === windowsStep);
    this.changed({ flow, windowsSteps, windowsIndex: windowsIndex === undefined || windowsIndex < 0 ? undefined : windowsIndex });
  }

  /** The step showing now. */
  get step(): OnboardingStep {
    const { flow, windowsSteps, windowsIndex } = this.state;
    if (flow === undefined) return { kind: "finished" };
    if (windowsIndex !== undefined) return windowsSteps[windowsIndex] ?? { kind: "finished" };
    return flow.stage;
  }

  /** Every step this run goes through for the current choices, so progress dots count what is left. */
  get steps(): OnboardingStep[] {
    const { flow, windowsSteps } = this.state;
    if (flow === undefined) return [];
    return [...flow.stages, ...windowsSteps];
  }

  get stepIndex(): number {
    const { flow, windowsIndex } = this.state;
    if (flow === undefined) return 0;
    if (windowsIndex !== undefined) return flow.stages.length + windowsIndex;
    return flow.stageIndex;
  }

  get canGoBack(): boolean {
    const { flow, windowsIndex } = this.state;
    if (flow === undefined) return false;
    return windowsIndex !== undefined || flow.canGoBack;
  }

  get isLastStep(): boolean {
    return this.stepIndex === this.steps.length - 1;
  }

  /**
   * Changes the flow (a pick, a toggle) and applies the choices once it
   * reaches a setup step or the end.
   */
  update(change: (flow: OnboardingFlow) => void): void {
    const flow = this.state.flow;
    if (flow === undefined) return;
    const before = flow.stage;
    change(flow);
    this.settle(flow, before);
  }

  /** Moves on: to the flow's next step, then through Windows' own, then ends. */
  next(): void {
    const { flow, windowsSteps, windowsIndex } = this.state;
    if (flow === undefined) return;
    if (windowsIndex !== undefined) {
      if (windowsIndex + 1 < windowsSteps.length) this.changed({ ...this.state, windowsIndex: windowsIndex + 1 });
      else this.finish();
      return;
    }
    const before = flow.stage;
    if (flow.stageIndex >= flow.stages.length - 1 && windowsSteps.length > 0) {
      /* The flow's last step is done; the kit and tabs are in place before Windows' own steps. */
      this.applyIfNeeded(flow, before, true);
      this.changed({ ...this.state, windowsIndex: 0 });
      return;
    }
    flow.next();
    this.settle(flow, before);
  }

  /** Goes back one step: from the first Windows step back into the flow's last, which it never left. */
  back(): void {
    const { flow, windowsIndex } = this.state;
    if (flow === undefined) return;
    if (windowsIndex !== undefined) {
      this.changed({ ...this.state, windowsIndex: windowsIndex > 0 ? windowsIndex - 1 : undefined });
      return;
    }
    const before = flow.stage;
    flow.back();
    this.settle(flow, before);
  }

  /** Ends onboarding with what has been picked so far. */
  finish(): void {
    const { flow, windowsSteps, windowsIndex } = this.state;
    if (flow === undefined) return;
    const before = flow.stage;
    flow.finish();
    this.applyIfNeeded(flow, before, windowsIndex !== undefined);
    /* The tray hint counts as shown only once the user reached it. */
    const reached = windowsIndex === undefined ? -1 : windowsIndex;
    if (windowsSteps.slice(0, reached + 1).some((step) => step.kind === "trayIcon")) this.app.settings.markTrayHintShown();
    this.changed({ flow: undefined, windowsSteps: [], windowsIndex: undefined });
    this.app.takeover.set(undefined);
  }

  private settle(flow: OnboardingFlow, before: OnboardingStage): void {
    this.applyIfNeeded(flow, before, false);
    if (flow.stage.kind === "finished") {
      if (this.state.windowsSteps.length > 0) this.changed({ ...this.state, windowsIndex: 0 });
      else this.finish();
      return;
    }
    this.changed({ ...this.state });
  }

  /** Applies the choices the first time the flow passes the tab step (or ends before it with Windows' steps ahead). */
  private applyIfNeeded(flow: OnboardingFlow, before: OnboardingStage, leavingFlow: boolean): void {
    const past = appliesChoices(flow.stage) || leavingFlow;
    const wasPast = appliesChoices(before) || this.state.windowsIndex !== undefined;
    if (past && !wasPast) this.apply(flow);
  }

  /**
   * Records the kit, its answers and the tabs. The first run always records
   * a kit (the preselected one after Start from Scratch), so onboarding does
   * not come back; a re-run switches kits only when the pick changed, so
   * going back and forth never adds starter tasks twice.
   */
  private apply(flow: OnboardingFlow): void {
    const settings = this.app.settings;
    const current = settings.current;
    const kit = flow.kit;
    if (!current.hasChosenKit) {
      settings.chooseKit(kit?.id ?? current.kitID, kit === undefined ? {} : flow.answers);
    } else if (kit !== undefined && (kit.id !== current.kitID || !sameKitAnswers(flow.answers, current.kitAnswers))) {
      settings.switchKit(kit.id, flow.answers);
    }
    const layout = flow.layout;
    settings.update((value) => ({ ...value, modules: layout }));
  }
}
