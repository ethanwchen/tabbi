/*
 * Port of ClosetModule.descriptor: the Closet's identity (the pet's page,
 * opened from the paw at the far right of the header or P), its kit settings
 * (the pet coach's lines and the starter pet) and its accent, kept apart
 * from the module so the store and the views can read them without a cycle.
 */

import { localizedDescriptor } from "../../app/descriptor";
import { PET_COACH_KIT_SETTING_TYPE } from "../../core/coach/petCoachMessages";
import { KitSettingsSchema, kitSetting } from "../../core/kits/kitSettingsSchema";
import { tr } from "../../core/localization/tr";
import { MODULE_CATEGORIES } from "../../core/modules/moduleDescriptor";
import { MODULE_IDS } from "../../core/modules/moduleId";
import { ONBOARDING_SETUP_STEPS } from "../../core/onboarding/onboardingSetupStep";
import { PET_BREEDS } from "../../core/pets/petKinds";
import { MAX_PET_NAME_LENGTH } from "../../core/pets/petProfile";
import type { ModuleAccent } from "../../core/themes/themeColor";

/** The Closet's warm amber, which the recap card shares (RecapCard.accent). */
export const CLOSET_ACCENT: ModuleAccent = { red: 0.98, green: 0.8, blue: 0.3 };

/* The Closet's kit settings: the pet coach's lines (PetCoachMessages.kitSettingType) and the starter pet (PetProfile.kitSettingType). */
export const CLOSET_KIT_SCHEMA = new KitSettingsSchema({
  coachLines: PET_COACH_KIT_SETTING_TYPE,
  pet: kitSetting.object({ breed: kitSetting.choice(PET_BREEDS), name: kitSetting.text(MAX_PET_NAME_LENGTH) }),
});

export const CLOSET_DESCRIPTOR = localizedDescriptor(
  {
    id: MODULE_IDS.closet,
    title: "Closet",
    symbol: "pawprint.fill",
    category: MODULE_CATEGORIES.fun,
    accent: CLOSET_ACCENT,
    kitSettings: CLOSET_KIT_SCHEMA,
    setup: [ONBOARDING_SETUP_STEPS.pet],
    headerShortcut: { label: "Your pet", key: "p" },
  },
  {
    title: () => tr("Closet"),
    summary: () => tr("Name your pet and dress it in items you earn."),
    shortcutLabel: () => tr("Your pet"),
  },
);
