import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import type { KitManifest } from "../../src/core/kits/kitManifest";
import { decodeKit } from "../../src/core/kits/kitValidation";
import { ModuleCatalog } from "../../src/core/modules/moduleCatalog";
import { MODULE_CATEGORIES, moduleDescriptor } from "../../src/core/modules/moduleDescriptor";
import { ModuleLayout } from "../../src/core/modules/moduleLayout";
import { ALL_ONBOARDING_EXTRAS, type OnboardingExtra } from "../../src/core/onboarding/onboardingExtra";
import { OnboardingFlow, type OnboardingStage } from "../../src/core/onboarding/onboardingFlow";
import { ONBOARDING_SETUP_STEPS, type OnboardingSetupStep } from "../../src/core/onboarding/onboardingSetupStep";
import { switchLanguage } from "../support/catalogs";
import { loadFixture } from "../support/fixtures";
import { goldenDiff } from "../support/goldenCompare";

/*
 * Replays shared/fixtures/onboarding (written by OnboardingGoldenTests on
 * the Mac): every setup step and extra, then 20 OnboardingFlow runs with the
 * flow's full state after every input.
 */

type Input =
  | { action: "choose"; kit: string }
  | { action: "startFromScratch" | "next" | "back" | "finish" }
  | { action: "answer"; answer: string }
  | { action: "setEnabled"; module: string; enabled: boolean }
  | { action: "move"; from: number[]; to: number };

interface Run {
  name: string;
  setup: {
    catalog: string;
    order: string[];
    disabled: string[];
    kit?: string;
    answers: Record<string, string[]>;
    asksName: boolean;
    extras: string[];
  };
  initial: unknown;
  steps: { input: Input; state: unknown }[];
}

interface OnboardingFile {
  schema: string;
  version: number;
  setupSteps: { id: string; rank: number }[];
  extras: { id: string; module?: string }[];
  catalogs: { name: string; modules: { id: string; setup: string[] }[]; unavailable: string[] }[];
  kits: ({ id: string; file: string } | { id: string; json: string })[];
  runs: Run[];
}

const fixture = loadFixture<OnboardingFile>("onboarding/onboarding.json");

beforeAll(() => switchLanguage("en"));

const steps: readonly OnboardingSetupStep[] = Object.values(ONBOARDING_SETUP_STEPS);

function stepNamed(id: string): OnboardingSetupStep {
  const step = steps.find((candidate) => candidate.id === id);
  if (step === undefined) throw new Error(`no setup step ${id}`);
  return step;
}

function extraNamed(id: string): OnboardingExtra {
  const extra = ALL_ONBOARDING_EXTRAS.find((candidate) => candidate.id === id);
  if (extra === undefined) throw new Error(`no extra ${id}`);
  return extra;
}

/* The fixture's catalogs: only ids and declared setup steps matter to onboarding. */
const catalogs = new Map(
  fixture.catalogs.map((catalog) => [
    catalog.name,
    new ModuleCatalog(
      catalog.modules.map((module) =>
        moduleDescriptor({
          id: module.id,
          title: module.id,
          symbol: "square",
          category: MODULE_CATEGORIES.productivity,
          accent: { red: 0.5, green: 0.5, blue: 0.5 },
          setup: module.setup.map(stepNamed),
        }),
      ),
      catalog.unavailable,
    ),
  ]),
);

const kits = new Map(
  fixture.kits.map((entry) => {
    let text: string;
    if ("file" in entry) {
      const url = new URL(`../../../Sources/TabbiKitCore/Kits/Bundled/${entry.file}`, import.meta.url);
      text = readFileSync(fileURLToPath(url), "utf8");
    } else {
      text = entry.json;
    }
    const result = decodeKit(text);
    if (!result.ok) throw new Error(`kit ${entry.id} does not load`);
    return [entry.id, result.kit];
  }),
);

function kitNamed(id: string): KitManifest {
  const kit = kits.get(id);
  if (kit === undefined) throw new Error(`no kit ${id}`);
  return kit;
}

function sorted(values: Iterable<string>): string[] {
  return [...values].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
}

function stageOutput(stage: OnboardingStage): Record<string, unknown> {
  return stage.kind === "question" || stage.kind === "setup" ? { kind: stage.kind, id: stage.id } : { kind: stage.kind };
}

function stateOf(flow: OnboardingFlow, result?: boolean): Record<string, unknown> {
  const layout = flow.layout;
  return {
    stage: stageOutput(flow.stage),
    stages: flow.stages.map(stageOutput),
    stageIndex: flow.stageIndex,
    canGoBack: flow.canGoBack,
    kit: flow.kit?.id,
    startedFromScratch: flow.startedFromScratch,
    answers: Object.fromEntries(Object.entries(flow.answers).map(([question, ids]) => [question, sorted(ids)])),
    order: layout.order,
    enabled: layout.enabled,
    setupSteps: flow.setupSteps.map((step) => step.id),
    currentExtras: flow.currentExtras.map((extra) => extra.id),
    currentQuestion: flow.currentQuestion?.id,
    currentSetupStep: flow.currentSetupStep?.id,
    result,
  };
}

/* Runs one input, returning what `setEnabled` said (the only input with a result). */
function perform(flow: OnboardingFlow, input: Input): boolean | undefined {
  switch (input.action) {
    case "choose":
      flow.choose(kitNamed(input.kit));
      return undefined;
    case "startFromScratch":
      flow.startFromScratch();
      return undefined;
    case "answer":
      flow.answer(input.answer);
      return undefined;
    case "setEnabled":
      return flow.setEnabled(input.module, input.enabled);
    case "move":
      flow.move(input.from, input.to);
      return undefined;
    case "next":
      flow.next();
      return undefined;
    case "back":
      flow.back();
      return undefined;
    case "finish":
      flow.finish();
      return undefined;
  }
}

function expectGolden(actual: unknown, expected: unknown, label: string): void {
  expect(goldenDiff(actual, expected), label).toBeUndefined();
}

describe("onboarding golden fixture", () => {
  it("is the version this suite reads", () => {
    expect(fixture.schema).toBe("tabbi.onboarding.golden");
    expect(fixture.version).toBe(1);
  });

  it("has the same setup steps and ranks", () => {
    expectGolden(
      steps.map((step) => ({ id: step.id, rank: step.rank })),
      fixture.setupSteps,
      "setupSteps",
    );
  });

  it("lists the same extras in the same order", () => {
    expectGolden(
      ALL_ONBOARDING_EXTRAS.map((extra) => ({ id: extra.id, module: extra.module })),
      fixture.extras,
      "extras",
    );
  });

  it("covers every run", () => {
    expect(fixture.runs.length).toBe(20);
  });

  for (const run of fixture.runs) {
    it(`replays ${run.name}`, () => {
      const catalog = catalogs.get(run.setup.catalog);
      if (catalog === undefined) throw new Error(`no catalog ${run.setup.catalog}`);
      const flow = new OnboardingFlow(catalog, {
        layout: new ModuleLayout(run.setup.order, run.setup.disabled, catalog),
        kit: run.setup.kit === undefined ? undefined : kitNamed(run.setup.kit),
        answers: Object.fromEntries(Object.entries(run.setup.answers).map(([question, ids]) => [question, new Set(ids)])),
        asksName: run.setup.asksName,
        extras: run.setup.extras.map(extraNamed),
      });
      expectGolden(stateOf(flow), run.initial, `${run.name} initial`);
      run.steps.forEach((step, index) => {
        const result = perform(flow, step.input);
        expectGolden(stateOf(flow, result), step.state, `${run.name} step ${index} ${JSON.stringify(step.input)}`);
      });
    });
  }
});
