import {
  auraFrameCount,
  backFrameCount,
  bodyFrameCount,
  faceFrameCount,
  headFrameCount,
  petArt,
  type CostumeAuraItem,
  type CostumeBackItem,
  type CostumeBodyItem,
  type CostumeFaceItem,
  type CostumeHeadItem,
} from "./petArt";
import type { PetAccessory, PetOutfit } from "./petCostume";

/*
 * Port of CostumeArt and the composer's item tables: which drawing in
 * `costume.json` each outfit, accessory and bond collar wears.
 */

/** What an accessory draws, and where. */
export type AccessoryArt =
  | { readonly kind: "body"; readonly item: CostumeBodyItem }
  | { readonly kind: "face"; readonly item: CostumeFaceItem }
  | { readonly kind: "head"; readonly item: CostumeHeadItem }
  /** A head item worn with a face piece, such as a hat and an eyepatch. */
  | { readonly kind: "mask"; readonly head: CostumeHeadItem; readonly face: CostumeFaceItem }
  /** Drawn on the layer behind the pet. */
  | { readonly kind: "back"; readonly item: CostumeBackItem }
  /** In the air around the pet. */
  | { readonly kind: "aura"; readonly item: CostumeAuraItem };

const costume = () => petArt("costume");

/** The outfit's drawing, or undefined for no outfit. */
export function outfitArt(outfit: PetOutfit): CostumeBodyItem | undefined {
  return outfit === "none" ? undefined : costume().bodyItem(outfit);
}

/** The head part of an outfit, drawn like a hat that moves with the head. */
export function outfitHood(outfit: PetOutfit): CostumeHeadItem | undefined {
  return outfit === "dinosaurHoodie" ? costume().headItem("dinosaurHood") : undefined;
}

const artCache = new Map<PetAccessory, AccessoryArt>();

export function accessoryArt(accessory: PetAccessory): AccessoryArt {
  let art = artCache.get(accessory);
  if (!art) {
    art = makeAccessoryArt(accessory);
    artCache.set(accessory, art);
  }
  return art;
}

function makeAccessoryArt(accessory: PetAccessory): AccessoryArt {
  const file = costume();
  switch (accessory) {
    case "stethoscope":
    case "scarf":
    case "bowTie":
    case "teamMedal":
    case "foundersPin":
    case "snowScarf":
      return { kind: "body", item: file.bodyItem(accessory) };
    case "roundGlasses":
    case "coolSunglasses":
    case "heartGlasses":
    case "summerShades":
      return { kind: "face", item: file.faceItem(accessory) };
    case "pirateHat":
      return { kind: "mask", head: file.headItem("pirateHat"), face: file.faceItem("eyepatch") };
    case "blindfoldedSorcerer":
      return { kind: "mask", head: file.headItem("spikyHair"), face: file.faceItem("blindfold") };
    case "angelWings":
    case "kingsCape":
      return { kind: "back", item: file.backItem(accessory) };
    case "cherryPetals":
    case "sparkleTrail":
    case "rainCloud":
      return { kind: "aura", item: file.auraItem(accessory) };
    default:
      return { kind: "head", item: file.headItem(accessory) };
  }
}

/** Frames in the loop of what an accessory draws (the longest part for a mask). */
export function accessoryFrameCounts(art: AccessoryArt): number[] {
  switch (art.kind) {
    case "body":
      return [bodyFrameCount(art.item)];
    case "face":
      return [faceFrameCount(art.item)];
    case "head":
      return [headFrameCount(art.item)];
    case "mask":
      return [headFrameCount(art.head), faceFrameCount(art.face)];
    case "back":
      return [backFrameCount(art.item)];
    case "aura":
      return [auraFrameCount(art.item)];
  }
}

/** The collar a pet grows into with its bond. Port of PetCollar. */
export const PET_COLLARS = ["none", "plain", "bell", "star", "gold"] as const;
export type PetCollar = (typeof PET_COLLARS)[number];

/** The bond collar's drawing, or undefined for none. */
export function bondCollarArt(collar: PetCollar): CostumeBodyItem | undefined {
  switch (collar) {
    case "none":
      return undefined;
    case "plain":
      return costume().bodyItem("bondCollarPlain");
    case "bell":
      return costume().bodyItem("bondCollarBell");
    case "star":
      return costume().bodyItem("bondCollarStar");
    case "gold":
      return costume().bodyItem("bondCollarGold");
  }
}

/** The soft white glints around a pet with a very deep bond. */
export function bondSparkleArt(): CostumeAuraItem {
  return costume().auraItem("bondSparkle");
}
