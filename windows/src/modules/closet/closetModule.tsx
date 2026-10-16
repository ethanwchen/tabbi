import { localizedDescriptor } from "../../app/descriptor";
import { defineModule } from "../../app/module";
import { KitSettingsSchema, kitSetting } from "../../core/kits/kitSettingsSchema";
import { tr } from "../../core/localization/tr";
import { MODULE_CATEGORIES } from "../../core/modules/moduleDescriptor";
import { MODULE_IDS } from "../../core/modules/moduleId";
import { ONBOARDING_SETUP_STEPS } from "../../core/onboarding/onboardingSetupStep";
import { PET_BREEDS } from "../../core/pets/petKinds";
import { MAX_PET_NAME_LENGTH } from "../../core/pets/petProfile";
import { placeholderPanel } from "../placeholderPanel";

/*
 * Port of PetCoachMessages.kitSettingType: per nudge kind, a line or a list
 * of lines that fit a speech bubble. The coach is not ported yet, so its
 * kinds and limits are written out here as the Swift declares them.
 */
const COACH_NUDGE_KINDS = ["distraction", "offerPause", "idleCheck", "autoPause"] as const;
const COACH_LINE_MAX_LENGTH = 64;
const COACH_LINES_PER_KIND = 20;

/* The Closet's kit settings: the pet coach's lines and the starter pet (PetProfile.kitSettingType). */
export const CLOSET_KIT_SCHEMA = new KitSettingsSchema({
  coachLines: kitSetting.object(
    Object.fromEntries(COACH_NUDGE_KINDS.map((kind) => [kind, kitSetting.lines(COACH_LINE_MAX_LENGTH, COACH_LINES_PER_KIND)])),
  ),
  pet: kitSetting.object({ breed: kitSetting.choice(PET_BREEDS), name: kitSetting.text(MAX_PET_NAME_LENGTH) }),
});

/* Port of ClosetModule: name the pet and dress it in what it earned. It opens from the paw at the far right of the header (key P). */
export const CLOSET_DESCRIPTOR = localizedDescriptor(
  {
    id: MODULE_IDS.closet,
    title: "Closet",
    symbol: "pawprint.fill",
    category: MODULE_CATEGORIES.fun,
    accent: { red: 0.98, green: 0.8, blue: 0.3 },
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

export const ClosetModule = defineModule(CLOSET_DESCRIPTOR, () => ({
  Panel: placeholderPanel(CLOSET_DESCRIPTOR),
}));
