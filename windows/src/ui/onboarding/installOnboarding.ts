/*
 * Hooks onboarding up to the island: on the first live launch (no kit
 * chosen yet) setup starts at once, and Settings > Tabs > Run Setup Again
 * starts it later. The store fills `app.takeover` while it runs and clears
 * it at the end; the island shows whatever the takeover holds.
 */

import type { AppServices } from "../../app/appServices";
import { OnboardingStore } from "./onboardingStore";
import { onboardingTakeover } from "./OnboardingTakeover";

export function installOnboarding(app: AppServices): OnboardingStore {
  const store = new OnboardingStore(app);
  const takeover = onboardingTakeover(store, app);
  const start = () => {
    if (store.isActive) return;
    store.start();
    app.takeover.set(takeover);
  };
  app.settings.setupRequested(start);
  if (!app.settings.current.hasChosenKit && !app.environment.runMode.isSnapshot) start();
  return store;
}
