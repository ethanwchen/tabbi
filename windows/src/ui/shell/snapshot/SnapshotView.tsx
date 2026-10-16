/*
 * Draws one snapshot state (snapshotPlan.ts) from demo data, still: the
 * island in a phase, the open panel of any module (turned on for the shot
 * if its kit leaves it off) in any of its named states, the pill with a
 * given preview, an onboarding step in the takeover slot (the real flow,
 * driven to that step), or a Settings section in a window-sized frame. The
 * frame it draws carries `data-snapshot-ready` once the module has settled
 * into its state, which the Playwright spec waits for.
 */

import { useEffect, useMemo, useState, type CSSProperties } from "react";
import type { AppServices } from "../../../app/appServices";
import { preloadLazyViews } from "../../../app/lazyView";
import type { NotchTakeover } from "../../../app/takeover";
import type { Host } from "../../../host/host";
import { MODULE_LIST } from "../../../modules/moduleList";
import { OnboardingFlow } from "../../../core/onboarding/onboardingFlow";
import { Island } from "../../Island";
import { OnboardingStore, WINDOWS_ONBOARDING_EXTRAS } from "../../onboarding/onboardingStore";
import { onboardingTakeover } from "../../onboarding/OnboardingTakeover";
import { initialState, type ShellState } from "../machine";
import { SettingsWindow } from "../settings/SettingsWindow";
import { setupSteps, snapshotStates, type SnapshotPlan } from "./snapshotPlan";
import { DEMO_PREVIEWS } from "./demoPreviews";

export interface SnapshotViewProps {
  readonly plan: SnapshotPlan;
  readonly app: AppServices;
  readonly host: Host;
  readonly locale: string;
  /** Opens the header's overflow list (`?more`). */
  readonly showsMore?: boolean;
}

const OPEN: ShellState = { ...initialState("alwaysVisible"), phase: "open", source: "tray", focused: true };
const PILL: ShellState = initialState("alwaysVisible");
const HIDDEN: ShellState = initialState("showOnHover");

/* The kit the onboarding shots pick: the one with questions, so every step has something to show. */
const ONBOARDING_KIT = "medicine";

/* Turns `id` on for the shot when the kit's layout leaves it off, so every module's panel can be drawn. */
function enable(app: AppServices, id: string): void {
  if (app.settings.current.modules.isEnabled(id)) return;
  app.settings.update((settings) => {
    const modules = settings.modules.clone();
    modules.add(id);
    return { ...settings, modules };
  });
}

/**
 * Puts the app into the plan's state before anything draws: the module (or
 * the modules asking for a setup step) turned on.
 */
export function prepareSnapshot(app: AppServices, plan: SnapshotPlan, options: { readonly allModules?: boolean } = {}): void {
  if (options.allModules === true) for (const type of MODULE_LIST) enable(app, type.descriptor.id);
  if (plan.kind === "open" || plan.kind === "closed") enable(app, plan.module);
  if (plan.kind === "onboarding") {
    for (const type of MODULE_LIST) if (type.descriptor.setup.some((declared) => declared.id === plan.step)) enable(app, type.descriptor.id);
  }
}

/**
 * The onboarding store driven to `step`: the flow's own steps by name, a
 * module's setup step by its id, or one of Windows' two. Nothing is
 * applied; the store only shows the flow as it stands there.
 */
function onboardingAt(app: AppServices, step: string): OnboardingStore {
  const store = new OnboardingStore(app);
  const settings = app.settings;
  const kit = settings.kits.get(ONBOARDING_KIT) ?? settings.activeKit;
  const flow = new OnboardingFlow(settings.catalog, {
    layout: settings.current.modules,
    ...(kit === undefined ? {} : { kit }),
    asksName: step === "name",
    extras: WINDOWS_ONBOARDING_EXTRAS,
  });
  const windows = step === "startWithWindows" || step === "trayIcon" ? step : undefined;
  if (step !== "name" && step !== "kit") {
    if (kit !== undefined) flow.choose(kit);
    const wanted = (stage: typeof flow.stage) =>
      step === "question" ? stage.kind === "question" : step === "modules" ? stage.kind === "modules" : step === "extras" ? stage.kind === "extras" : stage.kind === "setup" && stage.id === step;
    for (let guard = 0; guard < 40 && !wanted(flow.stage) && flow.stage.kind !== "finished"; guard++) {
      if (windows !== undefined && flow.stageIndex >= flow.stages.length - 1) break;
      flow.next();
    }
    /* A step the current choices never reach (the tray hint) shows the flow's last step behind it. */
    if (!wanted(flow.stage) && windows === undefined && setupSteps(MODULE_LIST).every((declared) => declared.id !== step)) flow.back();
  }
  store.show(flow, windows);
  return store;
}

export function SnapshotView({ plan, app, host, locale, showsMore = false }: SnapshotViewProps) {
  const named = plan.kind === "open" || plan.kind === "closed" ? plan.state : undefined;
  const [ready, setReady] = useState(named === undefined);
  /* Every lazy view is loaded first, so no frame is captured while a panel is still loading. */
  const [viewsLoaded, setViewsLoaded] = useState(false);

  useEffect(() => {
    void preloadLazyViews().then(() => setViewsLoaded(true));
  }, []);

  /* A module's named state may need a moment (a store loading demo data). */
  useEffect(() => {
    if ((plan.kind !== "open" && plan.kind !== "closed") || plan.state === undefined) return;
    const state = plan.state;
    void Promise.resolve(app.modules.get(plan.module)?.showSnapshotState?.(state)).then(() => setReady(true));
  }, [app, plan]);

  const takeover = useMemo((): NotchTakeover | undefined => {
    if (plan.kind !== "onboarding") return undefined;
    return onboardingTakeover(onboardingAt(app, plan.step), app);
  }, [app, plan]);

  if (!viewsLoaded) return null;
  switch (plan.kind) {
    case "index":
      return <pre id="snapshot-index">{JSON.stringify(snapshotStates(MODULE_LIST))}</pre>;
    case "settings":
      return (
        <div className="snapshot-frame settings-frame" data-snapshot-ready="">
          <SettingsWindow app={app} host={host} initialSection={plan.section} snapshotState={plan.state} />
        </div>
      );
    case "hidden":
    case "pill":
    case "closed":
    case "open":
    case "onboarding": {
      const initial = plan.kind === "hidden" ? HIDDEN : plan.kind === "pill" || plan.kind === "closed" ? PILL : OPEN;
      const mode = plan.kind === "hidden" ? "showOnHover" : "alwaysVisible";
      const preview = plan.kind === "pill" && plan.preview !== undefined ? DEMO_PREVIEWS[plan.preview]?.() : undefined;
      return (
        <div className="snapshot-frame" data-snapshot-ready={ready ? "" : undefined} style={{ display: "inline-block" } as CSSProperties}>
          <Island
            app={app}
            host={host}
            initial={initial}
            still
            initialTab={plan.kind === "open" ? plan.module : undefined}
            locale={locale}
            preview={preview}
            takeover={takeover}
            mode={mode}
            showsMore={showsMore}
          />
        </div>
      );
    }
  }
}
