/*
 * Port of onboarding's SetupFallback: what a setup step shows when no
 * module draws a view for it, a card with the step's glyph in its owner's
 * accent that says where to set it up later. Onboarding uses it through
 * `setupStepView`, so a module without a setup view still gets a calm step.
 */

import type { ComponentType, CSSProperties } from "react";
import type { SetupStepProps } from "../../app/module";
import type { ModuleRegistry } from "../../app/registry";
import { tr } from "../../core/localization/tr";
import type { ModuleCatalog } from "../../core/modules/moduleCatalog";
import type { ModuleDescriptor } from "../../core/modules/moduleDescriptor";
import type { ModuleID } from "../../core/modules/moduleId";
import type { OnboardingSetupStep } from "../../core/onboarding/onboardingSetupStep";
import { Card } from "../kit/Card";
import { useTheme } from "../kit/context";
import { Icon } from "../kit/Icon";
import { accentVariables } from "../kit/tokens";

export function SetupFallback({ step, owner }: { step: OnboardingSetupStep; owner: ModuleDescriptor | undefined }) {
  const theme = useTheme();
  const style = (owner === undefined ? { "--accent": "var(--primary-text)", "--accent-soft": "var(--surface-hover)" } : accentVariables(theme, owner.accent)) as CSSProperties;
  return (
    <Card className="setup-fallback">
      <div className="setup-fallback-row" style={style}>
        <span className="setup-fallback-badge">
          <Icon id={step.symbol} size={20} />
        </span>
        <span className="setup-fallback-text">
          <span className="kit-title">{step.title}</span>
          <span className="kit-body setup-fallback-detail">
            {owner === undefined ? tr("You can set this up any time in Settings.") : tr("You can set this up any time in the %@ tab.", owner.title)}
          </span>
        </span>
      </div>
    </Card>
  );
}

/**
 * The view for one setup step: the first enabled module (in tab order) that
 * declares the step and draws one, or the fallback card naming that module.
 */
export function setupStepView(
  step: OnboardingSetupStep,
  enabled: readonly ModuleID[],
  registry: ModuleRegistry,
  catalog: ModuleCatalog,
): ComponentType<SetupStepProps> {
  const view = registry.setupView(step, enabled);
  if (view !== undefined) return view;
  const owner = enabled.map((id) => catalog.descriptor(id)).find((descriptor) => descriptor.setup.some((declared) => declared.id === step.id));
  function Fallback() {
    return <SetupFallback step={step} owner={owner} />;
  }
  return Fallback;
}
