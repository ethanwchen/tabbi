/*
 * The selected module's panel inside the open island, switching tabs the
 * Mac's way (MotionTransitions.tabSwitch): the new panel slides 24 px in
 * from the direction of travel while fading in, the old one slides 24 px
 * out the other way, both on the content spring. Under Reduce Motion they
 * only crossfade. Each panel draws in the panel canvas at Regular size and
 * is scaled up as a whole at Large (PanelSize.contentScale).
 */

import { Suspense, useState, type CSSProperties } from "react";
import type { ModuleRegistry } from "../../app/registry";
import { tr } from "../../core/localization/tr";
import type { ModuleCatalog } from "../../core/modules/moduleCatalog";
import type { ModuleID } from "../../core/modules/moduleId";
import { useTheme } from "../kit/context";
import { ModulePlaceholder } from "../kit/ModulePlaceholder";
import { accentVariables } from "../kit/tokens";

export interface TabPanelsProps {
  readonly selected: ModuleID;
  /** True when the new tab is after the old one, so it slides in from the trailing side. */
  readonly forward: boolean;
  readonly registry: ModuleRegistry;
  readonly catalog: ModuleCatalog;
  /** Panel content scale: 1 at Compact and Regular, 9/8 at Large. */
  readonly scale: number;
}

interface Shown {
  readonly id: ModuleID;
  readonly forward: boolean;
}

export function TabPanels({ selected, forward, registry, catalog, scale }: TabPanelsProps) {
  const [current, setCurrent] = useState<Shown>({ id: selected, forward });
  const [leaving, setLeaving] = useState<Shown | undefined>(undefined);
  if (current.id !== selected) {
    setLeaving({ id: current.id, forward });
    setCurrent({ id: selected, forward });
  }
  return (
    <div className="panels">
      {leaving !== undefined && (
        <PanelLayer key={`out-${leaving.id}`} shown={leaving} phase="out" registry={registry} catalog={catalog} scale={scale} onDone={() => setLeaving(undefined)} />
      )}
      <PanelLayer key={current.id} shown={current} phase={leaving === undefined ? "rest" : "in"} registry={registry} catalog={catalog} scale={scale} />
    </div>
  );
}

interface PanelLayerProps {
  readonly shown: Shown;
  readonly phase: "in" | "out" | "rest";
  readonly registry: ModuleRegistry;
  readonly catalog: ModuleCatalog;
  readonly scale: number;
  readonly onDone?: () => void;
}

function PanelLayer({ shown, phase, registry, catalog, scale, onDone }: PanelLayerProps) {
  const theme = useTheme();
  const descriptor = catalog.descriptor(shown.id);
  const Panel = registry.get(shown.id)?.Panel;
  const style = {
    ...accentVariables(theme, descriptor.accent),
    "--panel-scale": String(scale),
  } as CSSProperties;
  return (
    <div
      className="panel-layer"
      data-phase={phase}
      data-forward={shown.forward}
      data-module={shown.id}
      aria-hidden={phase === "out" || undefined}
      style={style}
      onAnimationEnd={(event) => {
        if (phase === "out" && event.target === event.currentTarget) onDone?.();
      }}
    >
      <div className="panel-scaled">
        {/* A panel loads on first use; the layer stays empty for that moment. */}
        {Panel ? (
          <Suspense fallback={null}>
            <Panel />
          </Suspense>
        ) : (
          <ModulePlaceholder symbol={descriptor.symbol} detail={tr("This tab isn't available in this build.")} />
        )}
      </div>
    </div>
  );
}
