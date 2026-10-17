/*
 * The names the pet art and saves use: species, body shapes, breeds and
 * animations, in the Mac's declaration order (`allCases`), which is also the
 * order pickers, clip sets and the golden fixtures walk them in.
 */

/** Port of PetSpecies. */
export const PET_SPECIES = ["cat", "dog"] as const;
export type PetSpecies = (typeof PET_SPECIES)[number];

/** Port of PetBodyShape: the shared art a breed is drawn on. */
export const PET_BODY_SHAPES = [
  "cat",
  "roundCat",
  "sphynxCat",
  "foldCat",
  "longhairCat",
  "floppyDog",
  "fluffyDog",
  "batEaredDog",
  "pointyEaredDog",
  "longDog",
  "poodleDog",
  "shihTzuDog",
] as const;
export type PetBodyShape = (typeof PET_BODY_SHAPES)[number];

/** Port of PetBreed's cases, which are what pet saves store. */
export const PET_BREEDS = [
  "orangeTabby",
  "grayTabby",
  "blackCat",
  "whiteCat",
  "tuxedo",
  "calico",
  "siamese",
  "britishShorthair",
  "sphynx",
  "scottishFold",
  "britishLonghair",
  "goldenRetriever",
  "labrador",
  "frenchBulldog",
  "corgi",
  "dachshund",
  "beagle",
  "poodle",
  "shihTzu",
] as const;
export type PetBreed = (typeof PET_BREEDS)[number];

/** Port of PetAnimation: every animation a pet can play. */
export const PET_ANIMATIONS = [
  "idle",
  "blink",
  "sit",
  "sleep",
  "walk",
  "stretch",
  "peekIn",
  "peekOut",
  "alert",
  "celebrate",
  "yawn",
  "hop",
  "typing",
  "coffee",
  "wave",
  "groom",
  "tailSwish",
  "nap",
  "play",
] as const;
export type PetAnimation = (typeof PET_ANIMATIONS)[number];

export function isOneOf<T extends string>(list: readonly T[], value: string): value is T {
  return (list as readonly string[]).includes(value);
}
