import { describe, expect, it } from "vitest";
import { BUNDLED_KITS } from "../../../src/core/kits/bundledKits";
import { kitLayout } from "../../../src/core/kits/kitApplication";
import type { KitManifest } from "../../../src/core/kits/kitManifest";
import { ModuleCatalog } from "../../../src/core/modules/moduleCatalog";
import { MODULE_CATEGORIES, moduleDescriptor } from "../../../src/core/modules/moduleDescriptor";
import { ModuleLayout } from "../../../src/core/modules/moduleLayout";
import { ALL_ONBOARDING_EXTRAS, ONBOARDING_EXTRAS, onboardingExtra } from "../../../src/core/onboarding/onboardingExtra";
import { OnboardingFlow, type OnboardingStage } from "../../../src/core/onboarding/onboardingFlow";
import { ONBOARDING_SETUP_STEPS, onboardingSetupStep } from "../../../src/core/onboarding/onboardingSetupStep";
import { BUILT_IN_CATALOG } from "../../support/builtInCatalog";

const catalog = BUILT_IN_CATALOG;

function bundled(id: string): KitManifest {
  const kit = BUNDLED_KITS.get(id);
  if (!kit) throw new Error(`no bundled kit ${id}`);
  return kit;
}

const medicine = bundled("medicine");
const essentials = bundled("essentials");

function flow(options: { asksName?: boolean; extras?: typeof ALL_ONBOARDING_EXTRAS } = {}): OnboardingFlow {
  return new OnboardingFlow(catalog, { layout: ModuleLayout.all(catalog), ...options });
}

const kit: OnboardingStage = { kind: "kit" };
const modules: OnboardingStage = { kind: "modules" };
const question = (id: string): OnboardingStage => ({ kind: "question", id });
const setup = (id: string): OnboardingStage => ({ kind: "setup", id });
const ids = (steps: readonly { id: string }[]) => steps.map((step) => step.id);

describe("OnboardingFlow", () => {
  it("starts on the kit step", () => {
    const onboarding = flow();
    expect(onboarding.stage).toEqual(kit);
    expect(onboarding.canGoBack).toBe(false);
    expect(onboarding.stageIndex).toBe(0);
  });

  it("asks Med School's questions, then tabs, then only its modules' setup", () => {
    const onboarding = flow();
    onboarding.choose(medicine);
    expect(onboarding.stages).toEqual([
      kit,
      question("stage"),
      question("anki"),
      modules,
      setup("pet"),
      setup("anki"),
      setup("calendar"),
      setup("studyMethod"),
    ]);
    expect(onboarding.stage).toEqual(question("stage"));
    expect(onboarding.layout.equals(kitLayout(medicine, catalog))).toBe(true);
  });

  it("walks Essentials through its setup steps when skipping", () => {
    const onboarding = flow();
    onboarding.choose(essentials);
    expect(onboarding.stage).toEqual(question("day"));
    onboarding.next();
    expect(onboarding.stage).toEqual(modules);
    expect(ids(onboarding.setupSteps)).toEqual(["pet", "calendar", "studyMethod"]);
    onboarding.next();
    expect(onboarding.currentSetupStep?.id).toBe("pet");
    onboarding.next();
    expect(onboarding.currentSetupStep?.id).toBe("calendar");
    onboarding.next();
    expect(onboarding.currentSetupStep?.id).toBe("studyMethod");
    onboarding.next();
    expect(onboarding.stage).toEqual({ kind: "finished" });
    expect(onboarding.stageIndex).toBe(onboarding.stages.length);
  });

  it("takes one tap for a single-choice answer, which can turn a tab off", () => {
    const onboarding = flow();
    onboarding.choose(medicine);
    onboarding.answer("preclinical");
    expect(onboarding.stage).toEqual(question("anki"));
    onboarding.answer("no");
    expect(onboarding.stage).toEqual(modules);
    expect(onboarding.answers).toEqual({ stage: new Set(["preclinical"]), anki: new Set(["no"]) });
    expect(onboarding.layout.isEnabled("anki")).toBe(false);
    expect(ids(onboarding.setupSteps)).not.toContain("anki");
  });

  it("adds a tab's setup step just in time, ranked", () => {
    const onboarding = flow();
    onboarding.choose(essentials);
    expect(onboarding.stages).not.toContainEqual(setup("anki"));
    onboarding.setEnabled("anki", true);
    expect(ids(onboarding.setupSteps)).toEqual(["pet", "anki", "calendar", "studyMethod"]);
    onboarding.setEnabled("planner", false);
    expect(ids(onboarding.setupSteps)).toEqual(["pet", "anki", "studyMethod"]);
  });

  it("asks a step two modules need once", () => {
    const shared = onboardingSetupStep("shared", "Shared", "star");
    const own = new ModuleCatalog([
      moduleDescriptor({
        id: "a",
        title: "A",
        symbol: "a.circle",
        category: MODULE_CATEGORIES.fun,
        accent: { red: 1, green: 0, blue: 0 },
        setup: [shared, ONBOARDING_SETUP_STEPS.pet],
      }),
      moduleDescriptor({
        id: "b",
        title: "B",
        symbol: "b.circle",
        category: MODULE_CATEGORIES.fun,
        accent: { red: 0, green: 1, blue: 0 },
        setup: [shared],
      }),
    ]);
    const onboarding = new OnboardingFlow(own, { layout: ModuleLayout.all(own) });
    expect(ids(onboarding.setupSteps)).toEqual(["pet", "shared"]);
  });

  it("starts from scratch with one tab and no questions", () => {
    const onboarding = flow();
    onboarding.startFromScratch();
    expect(onboarding.kit).toBeUndefined();
    expect(onboarding.startedFromScratch).toBe(true);
    expect(onboarding.stage).toEqual(modules);
    expect(onboarding.layout.enabled).toEqual([catalog.ids[0]]);
    expect(onboarding.layout.order).toEqual(catalog.ids);
  });

  it("keeps tab changes when going back and picking the same kit", () => {
    const onboarding = flow();
    onboarding.choose(essentials);
    onboarding.setEnabled("spotify", false);
    onboarding.move([3], 0);
    const tweaked = onboarding.layout;
    onboarding.back();
    expect(onboarding.stage).toEqual(kit);
    onboarding.choose(essentials);
    expect(onboarding.layout.equals(tweaked)).toBe(true);
  });

  it("starts over from another kit's tabs", () => {
    const onboarding = flow();
    onboarding.choose(medicine);
    onboarding.answer("clinical");
    onboarding.back();
    onboarding.back();
    onboarding.choose(essentials);
    expect(onboarding.answers).toEqual({});
    expect(onboarding.layout.equals(kitLayout(essentials, catalog))).toBe(true);
  });

  it("never turns the last tab off", () => {
    const onboarding = flow();
    onboarding.startFromScratch();
    const first = catalog.ids[0] ?? "";
    expect(onboarding.setEnabled(first, false)).toBe(false);
    expect(onboarding.layout.enabled).toEqual([first]);
  });

  it("finishes from anywhere", () => {
    const onboarding = flow();
    onboarding.choose(medicine);
    onboarding.finish();
    expect(onboarding.stage).toEqual({ kind: "finished" });
    expect(onboarding.canGoBack).toBe(false);
    onboarding.back();
    expect(onboarding.stage).toEqual({ kind: "finished" });
  });

  it("preselects the active kit and answers when re-run", () => {
    const answers = { stage: new Set(["clinical"]) };
    const onboarding = new OnboardingFlow(catalog, {
      layout: kitLayout(medicine, catalog, answers),
      kit: medicine,
      answers,
    });
    expect(onboarding.stage).toEqual(kit);
    onboarding.choose(medicine);
    expect(onboarding.answers).toEqual(answers);
  });

  it("opens on the name step before the kit when asked", () => {
    const onboarding = flow({ asksName: true });
    expect(onboarding.stage).toEqual({ kind: "name" });
    expect(onboarding.stages.slice(0, 2)).toEqual([{ kind: "name" }, kit]);
    expect(onboarding.stageIndex).toBe(0);
    expect(onboarding.canGoBack).toBe(false);
    onboarding.next();
    expect(onboarding.stage).toEqual(kit);
    expect(onboarding.canGoBack).toBe(true);
    onboarding.back();
    expect(onboarding.stage).toEqual({ kind: "name" });
    onboarding.next();
    onboarding.choose(essentials);
    expect(onboarding.stage).toEqual(question("day"));
    expect(onboarding.stages[0]).toEqual({ kind: "name" });
  });

  it("answers the kit step when a kit is picked from the name step", () => {
    const onboarding = flow({ asksName: true });
    onboarding.choose(essentials);
    expect(onboarding.stage).toEqual(question("day"));
    const scratch = flow({ asksName: true });
    scratch.startFromScratch();
    expect(scratch.stage).toEqual(modules);
  });

  it("starts on the kit without the name step", () => {
    const onboarding = flow();
    expect(onboarding.stages).not.toContainEqual({ kind: "name" });
    expect(onboarding.stage).toEqual(kit);
  });

  it("matches the fixture's modules with setup steps", () => {
    expect(ids(catalog.descriptor("closet").setup)).toEqual(["pet"]);
    expect(catalog.descriptor("system").setup).toEqual([]);
  });

  it("puts the extras last on one screen, only those whose tab is on", () => {
    const onboarding = flow({ extras: ALL_ONBOARDING_EXTRAS });
    onboarding.choose(medicine);
    expect(onboarding.stages[onboarding.stages.length - 1]).toEqual({ kind: "extras" });
    expect(onboarding.stages.filter((stage) => stage.kind === "extras").length).toBe(1);
    expect(onboarding.layout.isEnabled("party")).toBe(false);
    expect(ids(onboarding.currentExtras)).toEqual(["widget", "reminder", "sync"]);
    onboarding.setEnabled("party", true);
    expect(ids(onboarding.currentExtras)).toEqual(["widget", "reminder", "invites", "sync"]);
  });

  it("finishes after Done on the extras", () => {
    const onboarding = flow({ extras: ALL_ONBOARDING_EXTRAS });
    onboarding.choose(essentials);
    while (onboarding.stage.kind !== "extras") onboarding.next();
    expect(onboarding.canGoBack).toBe(true);
    onboarding.next();
    expect(onboarding.stage).toEqual({ kind: "finished" });
  });

  it("shows no extras screen without extras that apply", () => {
    const extra = onboardingExtra("party-only", "Party", "Only with Party.", "link", "party");
    const onboarding = flow({ extras: [extra] });
    onboarding.choose(medicine);
    expect(onboarding.stages).not.toContainEqual({ kind: "extras" });
  });

  it("hands out copies of its layout", () => {
    const onboarding = flow();
    onboarding.layout.setEnabled("system", false);
    expect(onboarding.layout.isEnabled("system")).toBe(true);
    expect(ONBOARDING_EXTRAS.reminder.module).toBe("closet");
    expect(ONBOARDING_EXTRAS.widget.title).toBe("Desktop widget");
  });
});
