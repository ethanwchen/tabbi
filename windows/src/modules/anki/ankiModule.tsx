import { localizedDescriptor } from "../../app/descriptor";
import { defineModule } from "../../app/module";
import { ANKI_CONNECT_ENDPOINT } from "../../core/anki/ankiConnectClient";
import { tr } from "../../core/localization/tr";
import { MODULE_CATEGORIES } from "../../core/modules/moduleDescriptor";
import { MODULE_IDS } from "../../core/modules/moduleId";
import { ONBOARDING_SETUP_STEPS } from "../../core/onboarding/onboardingSetupStep";
import { placeholderPanel } from "../placeholderPanel";

/* Port of AnkiModule: cards due today and the review streak, from AnkiConnect on this PC. */
export const ANKI_DESCRIPTOR = localizedDescriptor(
  {
    id: MODULE_IDS.anki,
    /* A product name, the same in every language. */
    title: "Anki",
    symbol: "rectangle.stack.fill",
    category: MODULE_CATEGORIES.study,
    accent: { red: 0.36, green: 0.62, blue: 1.0 },
    network: [{ host: new URL(ANKI_CONNECT_ENDPOINT).hostname, purpose: "your decks through AnkiConnect" }],
    setup: [ONBOARDING_SETUP_STEPS.anki],
  },
  {
    summary: () => tr("Cards due today and your daily review streak."),
  },
);

export const AnkiModule = defineModule(ANKI_DESCRIPTOR, () => ({
  Panel: placeholderPanel(ANKI_DESCRIPTOR),
}));
