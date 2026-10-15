import {
  PET_ACCESSORIES,
  PET_OUTFITS,
  accessoryDisplayName,
  outfitDisplayName,
  type PetAccessory,
  type PetOutfit,
} from "./petCostume";
import { isOneOf } from "./petKinds";

/*
 * Port of PetItem: anything the pet can wear, as one unlockable thing. An
 * item is its stable string id (`"outfit.scrubs"`, `"accessory.beanie"`),
 * the very form saved ledgers and the server's grants use.
 */

export type PetItem = `outfit.${PetOutfit}` | `accessory.${PetAccessory}`;

export function outfitItem(outfit: PetOutfit): PetItem {
  return `outfit.${outfit}`;
}

export function accessoryItem(accessory: PetAccessory): PetItem {
  return `accessory.${accessory}`;
}

/** The item a stable id names, or undefined for an id this build does not know. */
export function itemFromID(id: string): PetItem | undefined {
  const dot = id.indexOf(".");
  if (dot < 0) return undefined;
  const kind = id.slice(0, dot);
  const name = id.slice(dot + 1);
  if (kind === "outfit" && isOneOf(PET_OUTFITS, name)) return outfitItem(name);
  if (kind === "accessory" && isOneOf(PET_ACCESSORIES, name)) return accessoryItem(name);
  return undefined;
}

/** What an item is: an outfit or an accessory. */
export function itemParts(
  item: PetItem,
): { readonly kind: "outfit"; readonly outfit: PetOutfit } | { readonly kind: "accessory"; readonly accessory: PetAccessory } {
  const name = item.slice(item.indexOf(".") + 1);
  if (item.startsWith("outfit.")) return { kind: "outfit", outfit: name as PetOutfit };
  return { kind: "accessory", accessory: name as PetAccessory };
}

export function itemDisplayName(item: PetItem): string {
  const parts = itemParts(item);
  return parts.kind === "outfit" ? outfitDisplayName(parts.outfit) : accessoryDisplayName(parts.accessory);
}

/** Every outfit, then every accessory, in declaration order. */
export const ALL_ITEMS_IN_DECLARATION_ORDER: readonly PetItem[] = [
  ...PET_OUTFITS.map(outfitItem),
  ...PET_ACCESSORIES.map(accessoryItem),
];
