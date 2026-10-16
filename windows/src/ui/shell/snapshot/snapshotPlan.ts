/*
 * The snapshot harness's states, the browser's stand-in for the Mac's
 * `--snapshot` run: `?snapshot=<state>` draws one island, pill, onboarding
 * step or Settings section from demo data, still, for a Playwright run to
 * save as PNG. `?snapshot=index` lists every state, so the spec finds the
 * modules' own states without knowing any module.
 *
 * States: `hidden`, `pill` (plain), `pill:<preview>` (DEMO_PREVIEWS),
 * `open:<module>` and `open:<module>:<state>` (a module's `snapshotStates`),
 * `closed:<module>:<state>` (a module's `closedSnapshotStates`, drawn on the
 * pill with the demo preview), `onboarding:<step>` (each setup step a module declares) and
 * `settings:<section>`. The query can add `theme`, `lang`, `size`
 * (compact, regular, large), `kit` and `reduce`.
 */

import type { ModuleType } from "../../../app/module";
import type { ModuleID } from "../../../core/modules/moduleId";
import type { OnboardingSetupStep } from "../../../core/onboarding/onboardingSetupStep";
import { SETTINGS_SECTIONS } from "../settings/sections";
import { DEMO_PREVIEWS } from "./demoPreviews";

export type SnapshotPlan =
  | { readonly kind: "index" }
  | { readonly kind: "hidden" }
  | { readonly kind: "pill"; readonly preview: string | undefined }
  | { readonly kind: "open"; readonly module: ModuleID; readonly state: string | undefined }
  /** The pill with the ticker's demo preview, with a module put into one of its closed states (the coach's bubbles). */
  | { readonly kind: "closed"; readonly module: ModuleID; readonly state: string }
  | { readonly kind: "onboarding"; readonly step: string }
  | { readonly kind: "settings"; readonly section: string };

/** The setup steps the listed modules declare, once each, in onboarding's order. */
export function setupSteps(types: readonly ModuleType[]): OnboardingSetupStep[] {
  const steps = new Map<string, OnboardingSetupStep>();
  for (const type of types) for (const step of type.descriptor.setup) if (!steps.has(step.id)) steps.set(step.id, step);
  return [...steps.values()].sort((a, b) => a.rank - b.rank);
}

/** Every state the harness draws for `types`. */
export function snapshotStates(types: readonly ModuleType[]): string[] {
  return [
    "hidden",
    "pill",
    ...Object.keys(DEMO_PREVIEWS).map((preview) => `pill:${preview}`),
    ...types.flatMap((type) => [`open:${type.descriptor.id}`, ...(type.snapshotStates ?? []).map((state) => `open:${type.descriptor.id}:${state}`)]),
    ...types.flatMap((type) => (type.closedSnapshotStates ?? []).map((state) => `closed:${type.descriptor.id}:${state}`)),
    ...setupSteps(types).map((step) => `onboarding:${step.id}`),
    ...SETTINGS_SECTIONS.map((section) => `settings:${section.id}`),
  ];
}

/** The plan for a `snapshot` query value, or undefined for one the harness doesn't know. */
export function parseSnapshot(value: string): SnapshotPlan | undefined {
  const [kind = "", first, second] = value.split(":");
  switch (kind) {
    case "index":
      return { kind: "index" };
    case "hidden":
      return { kind: "hidden" };
    case "pill":
      return first === undefined || first in DEMO_PREVIEWS ? { kind: "pill", preview: first } : undefined;
    case "open":
      return first === undefined ? undefined : { kind: "open", module: first, state: second };
    case "closed":
      return first === undefined || second === undefined ? undefined : { kind: "closed", module: first, state: second };
    case "onboarding":
      return first === undefined ? undefined : { kind: "onboarding", step: first };
    case "settings":
      return { kind: "settings", section: first ?? "general" };
    default:
      return undefined;
  }
}
