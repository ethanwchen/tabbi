/*
 * Draws one snapshot state (snapshotPlan.ts) from demo data, still: the
 * island in a phase, the open panel of any module (turned on for the shot
 * if its kit leaves it off) in any of its named states, the pill with a
 * given preview, an onboarding setup step in the takeover slot, or a
 * Settings section in a window-sized frame. The frame it draws carries
 * `data-snapshot-ready` once the module has settled into its state, which
 * the Playwright spec waits for.
 */

import { useEffect, useMemo, useState, type CSSProperties } from "react";
import type { AppServices } from "../../../app/appServices";
import type { NotchTakeover } from "../../../app/takeover";
import type { Host } from "../../../host/host";
import { MODULE_LIST } from "../../../modules/moduleList";
import { Icon } from "../../kit/Icon";
import { Island } from "../../Island";
import { initialState, type ShellState } from "../machine";
import { SettingsWindow } from "../settings/SettingsWindow";
import { setupStepView } from "../SetupFallback";
import { DEMO_PREVIEWS } from "./demoPreviews";
import { setupSteps, snapshotStates, type SnapshotPlan } from "./snapshotPlan";

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
  if (plan.kind === "open") enable(app, plan.module);
  if (plan.kind === "onboarding") {
    for (const type of MODULE_LIST) if (type.descriptor.setup.some((declared) => declared.id === plan.step)) enable(app, type.descriptor.id);
  }
}

export function SnapshotView({ plan, app, host, locale, showsMore = false }: SnapshotViewProps) {
  const [ready, setReady] = useState(plan.kind !== "open" || plan.state === undefined);

  /* A module's named state may need a moment (a store loading demo data). */
  useEffect(() => {
    if (plan.kind !== "open" || plan.state === undefined) return;
    const state = plan.state;
    void Promise.resolve(app.modules.get(plan.module)?.showSnapshotState?.(state)).then(() => setReady(true));
  }, [app, plan]);

  const takeover = useMemo((): NotchTakeover | undefined => {
    if (plan.kind !== "onboarding") return undefined;
    const step = setupSteps(MODULE_LIST).find((candidate) => candidate.id === plan.step);
    if (step === undefined) return undefined;
    const View = setupStepView(step, app.settings.current.modules.enabled, app.modules, app.settings.catalog);
    return {
      Leading: () => (
        <span className="takeover-step">
          <Icon id={step.symbol} size={14} />
          <span>{step.title}</span>
        </span>
      ),
      Trailing: () => null,
      Body: () => <View step={step} done={() => {}} />,
    };
  }, [app, plan]);

  switch (plan.kind) {
    case "index":
      return <pre id="snapshot-index">{JSON.stringify(snapshotStates(MODULE_LIST))}</pre>;
    case "settings":
      return (
        <div className="snapshot-frame settings-frame" data-snapshot-ready="">
          <SettingsWindow app={app} host={host} initialSection={plan.section} />
        </div>
      );
    case "hidden":
    case "pill":
    case "open":
    case "onboarding": {
      const initial = plan.kind === "hidden" ? HIDDEN : plan.kind === "pill" ? PILL : OPEN;
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
