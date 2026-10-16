import { tr } from "../localization/tr";

/**
 * Port of OnboardingSetupStep: a just-in-time question first-run onboarding
 * asks only when a module that needs it is on (naming the pet, connecting
 * Anki, calendar access). Open like ModuleCategory: a new module can declare
 * a step of its own. Two steps are the same step when their ids are equal.
 */
export interface OnboardingSetupStep {
  readonly id: string;
  /** What the step sets up, such as "Your pet". */
  readonly title: string;
  /** SF Symbol name for the step's header. */
  readonly symbol: string;
  /** Where the step sits among the setup steps; lower runs first, ties keep module order. */
  readonly rank: number;
}

/** A step of a module's own; `rank` defaults to 100, after the built-in ones. */
export function onboardingSetupStep(id: string, title: string, symbol: string, rank = 100): OnboardingSetupStep {
  return { id, title, symbol, rank };
}

/** A built-in step, whose title is read from the catalog each time so it follows the language. */
function builtInStep(id: string, key: string, symbol: string, rank: number): OnboardingSetupStep {
  return {
    id,
    get title() {
      return tr(key);
    },
    symbol,
    rank,
  };
}

export const ONBOARDING_SETUP_STEPS = {
  /** The fun one first: pick a cat or a dog, its breed and its name. */
  pet: builtInStep("pet", "Your pet", "pawprint.fill", 10),
  /** Check that Anki and AnkiConnect answer on this machine. */
  anki: builtInStep("anki", "Connect Anki", "rectangle.stack.fill", 20),
  /** Ask for calendar access, so Today can plan around events. */
  calendar: builtInStep("calendar", "Calendar access", "calendar", 30),
  /** Pick the study rhythm the Study timer starts with. */
  studyMethod: builtInStep("studyMethod", "Your timer", "timer", 40),
  /** Pick a display name and the server study parties meet on. */
  party: builtInStep("party", "Study parties", "person.3.fill", 50),
} as const;
