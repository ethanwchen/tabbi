import { PET_BREEDS, isOneOf } from "../pets/petKinds";
import { MAX_PET_NAME_LENGTH, PetProfile, defaultPetName } from "../pets/petProfile";

/*
 * Port of PetKitDefaults.swift: the pet a kit starts someone on, from the
 * Closet section of the kit (`moduleSettings.closet.pet`: an optional
 * `breed` and `name`). The kit port owns reading a kit; this takes the
 * `pet` value as the kit JSON holds it.
 */

/** The fresh pet for someone with no save yet: the kit's breed and name, else the starter cat. */
export function starterForKit(petSection: unknown): PetProfile {
  const section = typeof petSection === "object" && petSection !== null ? (petSection as Record<string, unknown>) : {};
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
