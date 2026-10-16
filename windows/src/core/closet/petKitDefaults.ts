import { kitModuleSettings, type KitDefaults } from "../kits/kitManifest";
import { MODULE_IDS } from "../modules/moduleId";
import { PET_BREEDS, isOneOf } from "../pets/petKinds";
import { MAX_PET_NAME_LENGTH, PetProfile, defaultPetName } from "../pets/petProfile";

/*
 * Port of PetKitDefaults.swift: the pet a kit starts someone on, from the
 * Closet section of the kit (`moduleSettings.closet.pet`: an optional
 * `breed` and `name`), read leniently: an unknown breed is skipped, and a
 * kit name without a breed names the cat.
 */

/* The kit's `moduleSettings.closet.pet` value, whatever it holds. */
function petSection(kit: KitDefaults | undefined): unknown {
  const closet = kit === undefined ? undefined : kitModuleSettings(kit, MODULE_IDS.closet);
  return typeof closet === "object" && closet !== null && !Array.isArray(closet) ? closet.pet : undefined;
}

/** Port of PetProfile.starter(kit:): the fresh pet for someone with no save yet, the kit's breed and name, else the starter cat. */
export function starterForKit(kit: KitDefaults | undefined): PetProfile {
  const petSectionValue = petSection(kit);
  const section = typeof petSectionValue === "object" && petSectionValue !== null ? (petSectionValue as Record<string, unknown>) : {};
  const breed = typeof section.breed === "string" && isOneOf(PET_BREEDS, section.breed) ? section.breed : undefined;
  const profile = breed ? new PetProfile(defaultPetName(breed), breed) : PetProfile.starter("cat");
  if (typeof section.name === "string") profile.rename(section.name);
  return profile;
}

/** How a kit writes the pet, for kit validation: a breed from the list and a short name. */
export const PET_KIT_SETTING = {
  breed: { choice: [...PET_BREEDS] },
  name: { text: { maxLength: MAX_PET_NAME_LENGTH } },
} as const;
