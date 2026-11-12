import { tr } from "../localization/tr";
import { isLimited } from "../closet/petLimited";
import { itemParts, outfitItem, type PetItem } from "./petItem";
import { SHOP_ITEMS } from "./petUnlocks";

/*
 * Port of PetItemTheme: the shelves of the Closet wardrobe, and each item's
 * catalog release for the "New" badge. The Heirloom shelf comes last and
 * holds every Heirloom tier item, so the wardrobe lists cheaper tiers first.
 */

export const PET_ITEM_THEMES = ["study", "cozy", "fantasy", "seasonal", "silly", "heirloom"] as const;
export type PetItemTheme = (typeof PET_ITEM_THEMES)[number];

export function themeDisplayName(theme: PetItemTheme): string {
  switch (theme) {
    case "study":
      return tr("Study");
    case "cozy":
      return tr("Cozy");
    case "fantasy":
      return tr("Fantasy");
    case "seasonal":
      return tr("Seasonal");
    case "silly":
      return tr("Silly");
    case "heirloom":
      return tr("Heirloom");
  }
}

export function itemTheme(item: PetItem): PetItemTheme {
  const parts = itemParts(item);
  if (parts.kind === "outfit") {
    switch (parts.outfit) {
      case "none":
      case "scrubs":
      case "whiteCoat":
        return "study";
      case "cozyHoodie":
        return "cozy";
      case "superheroCape":
      case "wizardRobe":
        return "fantasy";
      case "dinosaurHoodie":
        return "silly";
      case "studyHoodie":
        return "seasonal";
      case "apprenticeRobe":
      case "scholarsRobe":
      case "sagesRobe":
        return "study";
      case "cozyPajamas":
      case "bakersApron":
        return "cozy";
      case "astronautSuit":
      case "starryCloak":
        return "fantasy";
      case "librarianCardigan":
      case "varsityJacket":
        return "study";
      case "keepersPeacoat":
      case "rainSlicker":
      case "koiYukata":
      case "sushiChef":
      case "snowDayPuffer":
        return "heirloom";
    }
  }
  switch (parts.accessory) {
    case "stethoscope":
    case "roundGlasses":
    case "surgicalCap":
    case "headMirror":
    case "graduationCap":
    case "chunkyHeadphones":
    case "goldenLaurel":
    case "foundersPin":
    case "owlSpectacles":
      return "study";
    case "scarf":
    case "beanie":
    case "chefHat":
    case "backwardsCap":
    case "nightcap":
    case "friendshipBandana":
    case "littleSprout":
    case "blossomSprout":
    case "tinyLantern":
    case "strawberryCap":
      return "cozy";
    case "tinyCrown":
    case "wizardHat":
    case "pirateHat":
    case "blindfoldedSorcerer":
    case "astronautHelmet":
    case "ninjaHeadband":
    case "angelWings":
    case "kingsCape":
    case "halo":
    case "sparkleTrail":
    case "explorersHat":
    case "aviatorCap":
      return "fantasy";
    case "frogHat":
    case "cowboyHat":
    case "bowTie":
    case "flameHeadband":
    case "teamMedal":
    case "rainCloud":
    case "beeAntennae":
    case "sportySweatband":
    case "cactusPot":
      return "silly";
    case "fireflies":
      return "heirloom";
    default:
      return "seasonal";
  }
}

/** The theme's shop items, cheapest first. Limited edition items have their own shelf. */
export function themeItems(theme: PetItemTheme): PetItem[] {
  return SHOP_ITEMS.filter((item) => item !== outfitItem("none") && itemTheme(item) === theme);
}

/** The catalog release that added the item. */
export function itemRelease(item: PetItem): number {
  const parts = itemParts(item);
  if (parts.kind === "outfit") {
    switch (parts.outfit) {
      case "none":
      case "scrubs":
      case "whiteCoat":
        return 1;
      case "studyHoodie":
        return 4;
      case "astronautSuit":
      case "starryCloak":
      case "apprenticeRobe":
      case "scholarsRobe":
      case "sagesRobe":
      case "cozyPajamas":
      case "bakersApron":
        return 6;
      case "librarianCardigan":
      case "varsityJacket":
      case "keepersPeacoat":
      case "rainSlicker":
      case "koiYukata":
      case "sushiChef":
      case "snowDayPuffer":
        return 7;
      default:
        return 2;
    }
  }
  switch (parts.accessory) {
    case "stethoscope":
    case "scarf":
    case "roundGlasses":
    case "surgicalCap":
    case "headMirror":
    case "graduationCap":
    case "beanie":
      return 1;
    case "backwardsCap":
    case "flameHeadband":
    case "goldenLaurel":
    case "teamMedal":
    case "angelWings":
    case "kingsCape":
    case "halo":
    case "cherryPetals":
    case "sparkleTrail":
    case "rainCloud":
      return 3;
    case "moonlitWitchHat":
    case "pumpkinHat":
    case "reindeerAntlers":
    case "snowScarf":
    case "heartGlasses":
    case "summerShades":
    case "lionDanceHat":
    case "sakuraSprig":
      return 4;
    case "foundersPin":
      return 5;
    case "littleSprout":
    case "blossomSprout":
    case "nightcap":
    case "explorersHat":
    case "beeAntennae":
    case "sportySweatband":
    case "owlSpectacles":
    case "friendshipBandana":
    case "tinyLantern":
      return 6;
    case "daisyChain":
    case "sailorCollar":
    case "strawberryCap":
    case "mushroomCap":
    case "cactusPot":
    case "sunHat":
    case "aviatorCap":
    case "fireflies":
      return 7;
    default:
      return 2;
  }
}

/** Items from this release wear a "New" badge until owned. */
export const LATEST_RELEASE = 7;

/** Limited edition items never wear it: their shelf has its own badge. */
export function itemIsNew(item: PetItem): boolean {
  return itemRelease(item) === LATEST_RELEASE && !isLimited(item);
}
