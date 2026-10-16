import { localizedDescriptor } from "../../app/descriptor";
import { defineModule } from "../../app/module";
import { tr } from "../../core/localization/tr";
import { MODULE_CATEGORIES } from "../../core/modules/moduleDescriptor";
import { MODULE_IDS } from "../../core/modules/moduleId";
import { ONBOARDING_SETUP_STEPS } from "../../core/onboarding/onboardingSetupStep";
import { PARTY_PRODUCTION_URL } from "../../core/party/partyServer";
import { placeholderPanel } from "../placeholderPanel";

/* Port of PartyModule: studying with friends, through the Party Worker. */
export const PARTY_DESCRIPTOR = localizedDescriptor(
  {
    id: MODULE_IDS.party,
    title: "Party",
    symbol: "person.3.fill",
    category: MODULE_CATEGORIES.study,
    accent: { red: 1.0, green: 0.42, blue: 0.62 },
    network: [{ host: new URL(PARTY_PRODUCTION_URL).hostname, purpose: "your presence and parties" }],
    setup: [ONBOARDING_SETUP_STEPS.party],
  },
  {
    title: () => tr("Party"),
    summary: () => tr("Study with friends and see who is focusing now."),
  },
);

export const PartyModule = defineModule(PARTY_DESCRIPTOR, () => ({
  Panel: placeholderPanel(PARTY_DESCRIPTOR),
}));
