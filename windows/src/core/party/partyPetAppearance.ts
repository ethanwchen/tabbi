import { colorFromHex, colorHex, type PetColor, type PetPaletteRole } from "../pets/petPalette";
import { PET_ACCESSORIES, PET_OUTFITS, type PetAccessory, type PetOutfit } from "../pets/petCostume";
import { PET_BREEDS, PET_SPECIES, isOneOf, type PetBreed } from "../pets/petKinds";
import { PetProfile } from "../pets/petProfile";
import type { PartyProfile, PartyProfileUpdate } from "./partyModels";

/*
 * Port of PartyPetAppearance: translates between the local `PetProfile` and
 * the server's pet fields.
 *
 * Friends see a pet exactly as its owner dressed it in the Closet: the
 * server catalog (version 3) has an id for every outfit and accessory the
 * app draws, so the outfit rides in `costume`, every worn accessory in
 * `accessories`, and the effective colors of every recolorable role in
 * `colors`. Breeds are the one lossy part: a breed without art falls back to
 * the drawn breed with the closest body.
 *
 * Apps from before catalog version 2 carried the medical and costume hats in
 * `costume` when no outfit was worn. That fallback is still sent and still
 * read. Ids an app does not know are dropped, never an error. Only
 * appearance goes through here; nothing about cards or decks.
 */

/** The palette roles sent in `colors`, in wire order. Catalog version 1 took the first six. */
export const PARTY_COLOR_ROLES: readonly PetPaletteRole[] = [
  "furBase",
  "furShade",
  "furAccent",
  "furSpot",
  "belly",
  "costumeBase",
  "costumeShade",
  "costumeTrim",
  "accessoryBase",
  "accessoryShade",
];

/** The server id for each drawn breed. */
export function wireBreed(breed: PetBreed): string {
  switch (breed) {
    case "orangeTabby":
    case "grayTabby":
      return "tabby";
    case "blackCat":
      return "black-cat";
    case "whiteCat":
      return "domestic-shorthair";
    case "tuxedo":
      return "tuxedo";
    case "calico":
      return "calico";
    case "siamese":
      return "siamese";
    case "britishShorthair":
      return "british-shorthair";
    case "sphynx":
      return "sphynx";
    case "scottishFold":
      return "scottish-fold";
    case "britishLonghair":
      return "british-longhair";
    case "goldenRetriever":
      return "golden-retriever";
    case "labrador":
      return "labrador";
    case "frenchBulldog":
      return "french-bulldog";
    case "corgi":
      return "corgi";
    case "dachshund":
      return "dachshund";
    case "beagle":
      return "beagle";
    case "poodle":
      return "poodle";
    /* The server has no Shih Tzu; its nearest small long-coated toy breed is the Pomeranian. */
    case "shihTzu":
      return "pomeranian";
  }
}

/** Server breeds the app has no art for, mapped to the drawn breed with the most similar body. */
export const FALLBACK_BREEDS: Readonly<Record<string, PetBreed>> = {
  "domestic-longhair": "britishLonghair",
  tortoiseshell: "calico",
  persian: "britishLonghair",
  "maine-coon": "britishLonghair",
  ragdoll: "britishLonghair",
  bengal: "orangeTabby",
  "russian-blue": "grayTabby",
  abyssinian: "orangeTabby",
  "norwegian-forest": "britishLonghair",
  mixed: "beagle",
  "german-shepherd": "corgi",
  "shiba-inu": "corgi",
  husky: "corgi",
  pug: "frenchBulldog",
  "border-collie": "labrador",
  samoyed: "goldenRetriever",
  chihuahua: "frenchBulldog",
  dalmatian: "labrador",
  bernese: "goldenRetriever",
};

export function localBreed(wire: string, species: string): PetBreed {
  const drawn = PET_BREEDS.find((breed) => wireBreed(breed) === wire);
  if (drawn !== undefined) return drawn;
  if (Object.hasOwn(FALLBACK_BREEDS, wire)) {
    const fallback = FALLBACK_BREEDS[wire];
    if (fallback !== undefined) return fallback;
  }
  return PetProfile.starter(isOneOf(PET_SPECIES, species) ? species : "cat").breed;
}

/** The server's costume id for each outfit. The cozy hoodie keeps the plain `hoodie` of catalog version 1. */
export function wireOutfit(outfit: PetOutfit): string {
  switch (outfit) {
    case "none":
      return "none";
    case "scrubs":
      return "scrubs";
    case "whiteCoat":
      return "white-coat";
    case "cozyHoodie":
      return "hoodie";
    case "superheroCape":
      return "superhero";
    case "dinosaurHoodie":
      return "dinosaur-hoodie";
    case "wizardRobe":
      return "wizard";
    case "studyHoodie":
      return "study-hoodie";
  }
}

function localOutfit(wire: string): PetOutfit | undefined {
  return PET_OUTFITS.find((outfit) => outfit !== "none" && wireOutfit(outfit) === wire);
}

/** The server's accessory id for each accessory. A switch, so a new accessory cannot ship without one. */
export function wireAccessory(accessory: PetAccessory): string {
  switch (accessory) {
    /* The ids catalog version 1 already had. */
    case "roundGlasses":
      return "glasses";
    case "coolSunglasses":
      return "sunglasses";
    case "chunkyHeadphones":
      return "headphones";
    case "bowTie":
      return "bow";
    case "scarf":
      return "scarf";
    case "tinyCrown":
      return "crown";
    case "flowerCrown":
      return "flower";
    case "partyHat":
      return "party-hat";
    case "beanie":
      return "beanie";
    case "halo":
      return "halo";
    /* Added in catalog version 2. */
    case "stethoscope":
      return "stethoscope";
    case "surgicalCap":
      return "surgical-cap";
    case "headMirror":
      return "head-mirror";
    case "graduationCap":
      return "graduation-cap";
    case "chefHat":
      return "chef-hat";
    case "wizardHat":
      return "wizard-hat";
    case "bunnyEars":
      return "bunny-ears";
    case "witchHat":
      return "witch-hat";
    case "cowboyHat":
      return "cowboy-hat";
    case "frogHat":
      return "frog-hat";
    case "ninjaHeadband":
      return "ninja-headband";
    case "pirateHat":
      return "pirate-hat";
    case "blindfoldedSorcerer":
      return "blindfolded-sorcerer";
    case "astronautHelmet":
      return "astronaut-helmet";
    case "backwardsCap":
      return "backwards-cap";
    case "flameHeadband":
      return "flame-headband";
    case "goldenLaurel":
      return "golden-laurel";
    case "teamMedal":
      return "team-medal";
    case "moonlitWitchHat":
      return "moonlit-witch-hat";
    case "pumpkinHat":
      return "pumpkin-hat";
    case "reindeerAntlers":
      return "reindeer-antlers";
    case "snowScarf":
      return "snow-scarf";
    case "heartGlasses":
      return "heart-glasses";
    case "summerShades":
      return "summer-shades";
    case "lionDanceHat":
      return "lion-dance-hat";
    case "sakuraSprig":
      return "sakura-sprig";
    case "foundersPin":
      return "founders-pin";
    case "angelWings":
      return "angel-wings";
    case "kingsCape":
      return "kings-cape";
    case "cherryPetals":
      return "cherry-petals";
    case "sparkleTrail":
      return "sparkle-trail";
    case "rainCloud":
      return "rain-cloud";
  }
}

const LOCAL_ACCESSORIES: ReadonlyMap<string, PetAccessory> = new Map(PET_ACCESSORIES.map((accessory) => [wireAccessory(accessory), accessory]));

/**
 * Hats catalog version 1 only had as costumes, in preference order. Apps
 * from then sent one of them in `costume` when no outfit was worn.
 */
const LEGACY_COSTUME_ACCESSORIES: readonly { accessory: PetAccessory; wire: string }[] = [
  { accessory: "stethoscope", wire: "stethoscope" },
  { accessory: "surgicalCap", wire: "surgical-cap" },
  { accessory: "graduationCap", wire: "graduation" },
  { accessory: "chefHat", wire: "chef" },
  { accessory: "pirateHat", wire: "pirate" },
  { accessory: "witchHat", wire: "witch" },
  { accessory: "astronautHelmet", wire: "astronaut" },
  { accessory: "bunnyEars", wire: "bunny" },
];

function legacyCostume(accessories: readonly PetAccessory[]): string {
  return LEGACY_COSTUME_ACCESSORIES.find((entry) => accessories.includes(entry.accessory))?.wire ?? "none";
}

/** The server takes `#RRGGBB` only. */
function opaqueHex(color: PetColor): string {
  return colorHex(color).slice(0, 7);
}

/** The pet fields of a profile update for `pet`. */
export function partyPetUpdate(pet: PetProfile): PartyProfileUpdate {
  const palette = pet.palette;
  return {
    petName: pet.name,
    species: pet.species,
    breed: wireBreed(pet.breed),
    colors: PARTY_COLOR_ROLES.map((role) => opaqueHex(palette.color(role))),
    costume: pet.outfit === "none" ? legacyCostume(pet.accessories) : wireOutfit(pet.outfit),
    accessories: pet.accessories.map(wireAccessory),
  };
}

/** The pet to draw for someone's server profile. Never fails: unknown ids fall back or are dropped. */
export function partyPet(profile: PartyProfile): PetProfile {
  const breed = localBreed(profile.breed, profile.species);
  const accessories = profile.accessories.flatMap((id) => LOCAL_ACCESSORIES.get(id) ?? []);
  let outfit: PetOutfit = "none";
  const local = localOutfit(profile.costume);
  if (local !== undefined) {
    outfit = local;
  } else {
    /* An older app's hat in the costume slot. Listed first, so an item the accessories name for the same slot wins. */
    const hat = LEGACY_COSTUME_ACCESSORIES.find((entry) => entry.wire === profile.costume)?.accessory;
    if (hat !== undefined) accessories.unshift(hat);
  }
  const pet = new PetProfile(profile.petName, breed, { outfit, accessories });
  PARTY_COLOR_ROLES.forEach((role, index) => {
    const hex = profile.colors[index];
    const color = hex === undefined ? undefined : colorFromHex(hex);
    if (color !== undefined) pet.setColor(color, role);
  });
  return pet;
}

/* MARK: Older servers */

/** The ids, limits and colors a catalog version 1 server takes. */
export const VERSION1_ACCESSORIES: ReadonlySet<string> = new Set([
  "glasses",
  "sunglasses",
  "headphones",
  "bow",
  "scarf",
  "crown",
  "flower",
  "party-hat",
  "beanie",
  "halo",
]);
export const VERSION1_COSTUMES: ReadonlySet<string> = new Set([
  "none",
  "scrubs",
  "white-coat",
  "hoodie",
  "superhero",
  "wizard",
  "stethoscope",
  "surgical-cap",
  "graduation",
  "chef",
  "pirate",
  "witch",
  "astronaut",
  "bunny",
]);
export const VERSION1_MAX_COLORS = 6;
export const VERSION1_MAX_ACCESSORIES = 4;
/**
 * Breeds added after catalog version 2, sent to an older server as the breed
 * it has with the closest body (which older apps draw as a British Shorthair).
 */
export const OLDER_CATALOG_BREEDS: Readonly<Record<string, string>> = { "british-longhair": "domestic-longhair" };

/**
 * This update as a server on catalog version 1 or 2 takes it: accessories it
 * has no id for left out, the newer hoodies sent as the plain hoodie, newer
 * breeds as their closest older one, and only the first six colors. Port of
 * PartyProfileUpdate.forCatalogVersion1.
 */
export function forCatalogVersion1(update: PartyProfileUpdate): PartyProfileUpdate {
  const { breed, colors, accessories, costume } = update;
  return {
    ...update,
    ...(breed === undefined ? {} : { breed: Object.hasOwn(OLDER_CATALOG_BREEDS, breed) ? OLDER_CATALOG_BREEDS[breed] : breed }),
    ...(colors === undefined ? {} : { colors: colors.slice(0, VERSION1_MAX_COLORS) }),
    ...(accessories === undefined
      ? {}
      : { accessories: accessories.filter((id) => VERSION1_ACCESSORIES.has(id)).slice(0, VERSION1_MAX_ACCESSORIES) }),
    ...(costume === undefined
      ? {}
      : { costume: VERSION1_COSTUMES.has(costume) ? costume : costume.endsWith("hoodie") ? "hoodie" : "none" }),
  };
}
