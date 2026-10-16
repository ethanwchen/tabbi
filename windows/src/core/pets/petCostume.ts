import { tr } from "../localization/tr";

/* Port of PetOutfit, PetAccessorySlot and PetAccessory: what the pet wears. */

/** What the pet wears on its body, one at a time. Declaration order matters (shop order ties). */
export const PET_OUTFITS = [
  "none",
  "scrubs",
  "whiteCoat",
  "cozyHoodie",
  "superheroCape",
  "dinosaurHoodie",
  "wizardRobe",
  "studyHoodie",
] as const;
export type PetOutfit = (typeof PET_OUTFITS)[number];

export function outfitDisplayName(outfit: PetOutfit): string {
  switch (outfit) {
    case "none":
      return tr("None");
    case "scrubs":
      return tr("Scrubs");
    case "whiteCoat":
      return tr("White Coat");
    case "cozyHoodie":
      return tr("Cozy Hoodie");
    case "superheroCape":
      return tr("Superhero Cape");
    case "dinosaurHoodie":
      return tr("Dinosaur Hoodie");
    case "wizardRobe":
      return tr("Wizard Robe");
    case "studyHoodie":
      return tr("Study Hoodie");
  }
}

/**
 * Where an accessory sits, in drawing order: at most one per slot. The back
 * slot is drawn under the whole pet and the aura floats around it.
 */
export const PET_ACCESSORY_SLOTS = ["neck", "face", "head", "back", "aura"] as const;
export type PetAccessorySlot = (typeof PET_ACCESSORY_SLOTS)[number];

export function slotOrder(slot: PetAccessorySlot): number {
  return PET_ACCESSORY_SLOTS.indexOf(slot);
}

/** Small items layered over the outfit, in the Mac's declaration order. */
export const PET_ACCESSORIES = [
  "stethoscope",
  "scarf",
  "roundGlasses",
  "surgicalCap",
  "headMirror",
  "graduationCap",
  "beanie",
  "tinyCrown",
  "partyHat",
  "chefHat",
  "wizardHat",
  "bunnyEars",
  "witchHat",
  "cowboyHat",
  "flowerCrown",
  "frogHat",
  "ninjaHeadband",
  "coolSunglasses",
  "pirateHat",
  "blindfoldedSorcerer",
  "astronautHelmet",
  "chunkyHeadphones",
  "bowTie",
  "backwardsCap",
  "flameHeadband",
  "goldenLaurel",
  "teamMedal",
  "moonlitWitchHat",
  "pumpkinHat",
  "reindeerAntlers",
  "snowScarf",
  "heartGlasses",
  "summerShades",
  "lionDanceHat",
  "sakuraSprig",
  "foundersPin",
  "angelWings",
  "kingsCape",
  "halo",
  "cherryPetals",
  "sparkleTrail",
  "rainCloud",
] as const;
export type PetAccessory = (typeof PET_ACCESSORIES)[number];

export function accessorySlot(accessory: PetAccessory): PetAccessorySlot {
  switch (accessory) {
    case "stethoscope":
    case "scarf":
    case "bowTie":
    case "teamMedal":
    case "snowScarf":
    case "foundersPin":
      return "neck";
    case "roundGlasses":
    case "coolSunglasses":
    case "heartGlasses":
    case "summerShades":
      return "face";
    case "angelWings":
    case "kingsCape":
      return "back";
    case "cherryPetals":
    case "sparkleTrail":
    case "rainCloud":
      return "aura";
    default:
      return "head";
  }
}

/** Head items that also cover an eye; they take the face slot too. */
export function coversEyes(accessory: PetAccessory): boolean {
  return accessory === "pirateHat" || accessory === "blindfoldedSorcerer";
}

export function accessoryDisplayName(accessory: PetAccessory): string {
  return tr(ACCESSORY_NAMES[accessory]);
}

/** The Mac catalog key of each accessory's name. */
const ACCESSORY_NAMES: Record<PetAccessory, string> = {
  stethoscope: "Stethoscope",
  scarf: "Cozy Scarf",
  roundGlasses: "Round Glasses",
  surgicalCap: "Surgical Cap",
  headMirror: "Head Mirror",
  graduationCap: "Graduation Cap",
  beanie: "Beanie",
  tinyCrown: "Tiny Crown",
  partyHat: "Party Hat",
  chefHat: "Chef Hat",
  wizardHat: "Wizard Hat",
  bunnyEars: "Bunny Ears",
  witchHat: "Witch Hat",
  cowboyHat: "Cowboy Hat",
  flowerCrown: "Flower Crown",
  frogHat: "Frog Hat",
  ninjaHeadband: "Ninja Headband",
  coolSunglasses: "Cool Sunglasses",
  pirateHat: "Pirate Hat",
  blindfoldedSorcerer: "Blindfolded Sorcerer",
  astronautHelmet: "Astronaut Helmet",
  chunkyHeadphones: "Chunky Headphones",
  bowTie: "Bow Tie",
  backwardsCap: "Backwards Cap",
  flameHeadband: "Flame Headband",
  goldenLaurel: "Golden Laurel",
  teamMedal: "Team Medal",
  moonlitWitchHat: "Moonlit Witch Hat",
  pumpkinHat: "Pumpkin Hat",
  reindeerAntlers: "Reindeer Antlers",
  snowScarf: "Snowy Scarf",
  heartGlasses: "Heart Glasses",
  summerShades: "Sunset Shades",
  lionDanceHat: "Lion Dance Hat",
  sakuraSprig: "Sakura Sprig",
  foundersPin: "Founder's Pin",
  angelWings: "Angel Wings",
  kingsCape: "King's Cape",
  halo: "Halo",
  cherryPetals: "Cherry Petals",
  sparkleTrail: "Sparkle Trail",
  rainCloud: "Tiny Rain Cloud",
};

function clashes(a: PetAccessory, b: PetAccessory): boolean {
  const slotA = accessorySlot(a);
  const slotB = accessorySlot(b);
  return slotA === slotB || (coversEyes(a) && slotB === "face") || (coversEyes(b) && slotA === "face");
}

/**
 * `accessories` reduced to what can be worn together: one per slot and no
 * face item under one that covers the eyes (the last one listed wins),
 * sorted in drawing order. Keeps hand-edited profiles valid.
 */
export function wearable(accessories: readonly PetAccessory[]): PetAccessory[] {
  let worn: PetAccessory[] = [];
  for (const accessory of accessories) {
    worn = worn.filter((existing) => !clashes(existing, accessory));
    worn.push(accessory);
  }
  /* A stable sort, like Swift's `sorted`, keeps equal slots in order (there is one per slot anyway). */
  return worn.map((accessory, index) => ({ accessory, index }))
    .sort((a, b) => slotOrder(accessorySlot(a.accessory)) - slotOrder(accessorySlot(b.accessory)) || a.index - b.index)
    .map(({ accessory }) => accessory);
}
