import { breedDisplayName, breedFurTint, breedPalette, breedSpecies } from "./petBreed";
import { NO_BOND_LOOK, type PetBondLook } from "./petBond";
import type { PetCanvas } from "./petCanvas";
import { sitting } from "./petComposer";
import { PET_ACCESSORIES, PET_OUTFITS, wearable, type PetAccessory, type PetOutfit } from "./petCostume";
import { itemParts, accessoryItem, outfitItem, type PetItem } from "./petItem";
import { PET_BREEDS, isOneOf, type PetBreed, type PetSpecies } from "./petKinds";
import {
  TINTABLE_FUR_ROLES,
  USER_EDITABLE_ROLES,
  colorFromHex,
  colorHex,
  colorsEqual,
  isPetPaletteRole,
  type PaletteOverrides,
  type PetColor,
  type PetPalette,
  type PetPaletteRole,
} from "./petPalette";
import type { PetPointsLedger } from "./petUnlocks";

/*
 * Port of PetProfile: who the study buddy is (name, breed), how it is
 * colored and what it wears. Decoding is forgiving: a profile saved by a
 * newer build or edited by hand still loads, and anything invalid is
 * dropped instead of failing the whole file.
 */

/** Longest name shown under the pet; longer names are cut, not rejected. */
export const MAX_PET_NAME_LENGTH = 16;

/** The name a pet of this breed gets before the user picks one: none for cats (they go by the breed), "Biscuit" for dogs. */
export function defaultPetName(breed: PetBreed): string {
  return breedSpecies(breed) === "cat" ? "" : "Biscuit";
}

/**
 * Trims whitespace, collapses inner runs and caps the length. An empty name
 * falls back to the breed name, and a breed name is never cut.
 */
export function cleanPetName(raw: string, breed: PetBreed): string {
  const joined = raw.split(/\s+/u).filter((word) => word.length > 0).join(" ");
  if (PET_BREEDS.some((candidate) => breedDisplayName(candidate) === joined)) return joined;
  /* Cut by user-perceived characters, as Swift's `prefix` on a String does. */
  const graphemes = [...new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(joined)];
  const capped = graphemes
    .slice(0, MAX_PET_NAME_LENGTH)
    .map((part) => part.segment)
    .join("")
    .trim();
  return capped === "" ? breedDisplayName(breed) : capped;
}

/** `overrides` without the colors of `roles`. */
function withoutRoles(overrides: PaletteOverrides, roles: readonly PetPaletteRole[]): PaletteOverrides {
  return Object.fromEntries(
    Object.entries(overrides).filter(([role]) => !roles.includes(role as PetPaletteRole)),
  ) as PaletteOverrides;
}

function editableOnly(overrides: PaletteOverrides): PaletteOverrides {
  const kept: PaletteOverrides = {};
  for (const role of USER_EDITABLE_ROLES) {
    const color = overrides[role];
    if (color) kept[role] = color;
  }
  return kept;
}

export class PetProfile {
  private nameValue: string;
  private breedValue: PetBreed;
  /** User colors layered over the breed palette; only user-editable roles are kept. */
  private overrides: PaletteOverrides;
  /** The one fur color picked in the Closet, or undefined for the breed's own colors. */
  private tint: PetColor | undefined;
  outfit: PetOutfit;
  /** Always wearable: at most one per slot, in drawing order. */
  private worn: PetAccessory[];
  /** What the pet has grown into with its bond; derived from the activity log, never saved. */
  bondLook: PetBondLook = NO_BOND_LOOK;

  constructor(
    name: string,
    breed: PetBreed,
    options: {
      paletteOverrides?: PaletteOverrides;
      furTint?: PetColor;
      outfit?: PetOutfit;
      accessories?: readonly PetAccessory[];
    } = {},
  ) {
    this.nameValue = cleanPetName(name, breed);
    this.breedValue = breed;
    this.overrides = editableOnly(options.paletteOverrides ?? {});
    this.tint = options.furTint;
    this.outfit = options.outfit ?? "none";
    this.worn = wearable(options.accessories ?? []);
  }

  /** A fresh, undressed pet: the British Shorthair starter cat or the Golden Retriever. */
  static starter(species: PetSpecies): PetProfile {
    return species === "cat"
      ? new PetProfile(defaultPetName("britishShorthair"), "britishShorthair")
      : new PetProfile(defaultPetName("goldenRetriever"), "goldenRetriever");
  }

  copy(): PetProfile {
    const copy = new PetProfile(this.nameValue, this.breedValue, {
      paletteOverrides: this.overrides,
      ...(this.tint ? { furTint: this.tint } : {}),
      outfit: this.outfit,
      accessories: this.worn,
    });
    copy.nameValue = this.nameValue;
    copy.bondLook = this.bondLook;
    return copy;
  }

  get name(): string {
    return this.nameValue;
  }

  get breed(): PetBreed {
    return this.breedValue;
  }

  /** Changing the breed renames a pet still called by its old breed's name. */
  set breed(breed: PetBreed) {
    const old = this.breedValue;
    this.breedValue = breed;
    if (this.nameValue === breedDisplayName(old)) this.nameValue = breedDisplayName(breed);
  }

  get species(): PetSpecies {
    return breedSpecies(this.breedValue);
  }

  get paletteOverrides(): PaletteOverrides {
    return { ...this.overrides };
  }

  get furTint(): PetColor | undefined {
    return this.tint;
  }

  get accessories(): readonly PetAccessory[] {
    return this.worn;
  }

  /** Whether the name is one the app gave (a breed name, a starter name, or "Mochi") rather than one the user chose. */
  get hasDefaultName(): boolean {
    return (
      this.nameValue === "Mochi" ||
      PET_BREEDS.some((breed) => this.nameValue === breedDisplayName(breed) || this.nameValue === defaultPetName(breed))
    );
  }

  rename(name: string): void {
    this.nameValue = cleanPetName(name, this.breedValue);
  }

  /** Recolors one user-editable role, or clears it with undefined. */
  setColor(color: PetColor | undefined, role: PetPaletteRole): void {
    if (!USER_EDITABLE_ROLES.includes(role)) return;
    if (color) this.overrides[role] = color;
    else this.overrides = withoutRoles(this.overrides, [role]);
  }

  /** Recolors the fur from one picked color, or returns to the breed colors; single fur role colors are cleared. */
  tintFur(color: PetColor | undefined): void {
    this.tint = color;
    this.overrides = withoutRoles(this.overrides, TINTABLE_FUR_ROLES);
  }

  resetColors(): void {
    this.overrides = {};
    this.tint = undefined;
  }

  /** Puts an accessory on, replacing whatever was in the same slot. */
  wear(accessory: PetAccessory): void {
    this.worn = wearable([...this.worn, accessory]);
  }

  takeOff(accessory: PetAccessory): void {
    this.worn = this.worn.filter((worn) => worn !== accessory);
  }

  isWearing(item: PetItem): boolean {
    const parts = itemParts(item);
    return parts.kind === "outfit" ? this.outfit === parts.outfit : this.worn.includes(parts.accessory);
  }

  /** The colors to render with: breed defaults, the fur tint, then user overrides (the renderer lights dark edges). */
  get palette(): PetPalette {
    const tint = this.tint ? breedFurTint(this.breedValue, this.tint) : {};
    return breedPalette(this.breedValue).applying(tint).applying(this.overrides);
  }

  /** The pet sitting in its current outfit and accessories. */
  sittingCanvas(): PetCanvas {
    return sitting(this.breedValue, { outfit: this.outfit, accessories: this.worn, bond: this.bondLook });
  }

  /** A copy with anything the ledger does not own taken off. */
  restricted(ledger: PetPointsLedger): PetProfile {
    const copy = this.copy();
    if (!ledger.owns(outfitItem(this.outfit))) copy.outfit = "none";
    copy.worn = this.worn.filter((accessory) => ledger.owns(accessoryItem(accessory)));
    return copy;
  }

  equals(other: PetProfile): boolean {
    const sameColors = (a: PaletteOverrides, b: PaletteOverrides) => {
      const keys = new Set([...Object.keys(a), ...Object.keys(b)]) as Set<PetPaletteRole>;
      return [...keys].every((key) => {
        const x = a[key];
        const y = b[key];
        return x !== undefined && y !== undefined ? colorsEqual(x, y) : x === y;
      });
    };
    return (
      this.nameValue === other.nameValue &&
      this.breedValue === other.breedValue &&
      sameColors(this.overrides, other.overrides) &&
      (this.tint && other.tint ? colorsEqual(this.tint, other.tint) : this.tint === other.tint) &&
      this.outfit === other.outfit &&
      this.worn.length === other.worn.length &&
      this.worn.every((accessory, index) => other.worn[index] === accessory)
    );
  }

  /** The Mac's JSON form; `furTint` is written even when empty, so a missing key always means an older save. */
  toJSON(): Record<string, unknown> {
    const overrides: Record<string, string> = {};
    for (const [role, color] of Object.entries(this.overrides)) if (color) overrides[role] = colorHex(color);
    return {
      name: this.nameValue,
      breed: this.breedValue,
      paletteOverrides: overrides,
      furTint: this.tint ? colorHex(this.tint) : null,
      outfit: this.outfit,
      accessories: [...this.worn],
    };
  }

  /**
   * Reads a saved profile. The breed is the one field that cannot be
   * guessed; everything else falls back to a default. Saves from before
   * `furTint` stored a pick as the fur base: the pick is kept and the stale
   * shades dropped.
   */
  static fromJSON(raw: unknown): PetProfile {
    if (typeof raw !== "object" || raw === null) throw new Error("A pet profile must be an object");
    const object = raw as Record<string, unknown>;
    const breed = object.breed;
    if (typeof breed !== "string" || !isOneOf(PET_BREEDS, breed)) throw new Error(`Unknown breed ${String(breed)}`);
    const name = typeof object.name === "string" ? object.name : "";
    const overrides: PaletteOverrides = {};
    if (typeof object.paletteOverrides === "object" && object.paletteOverrides !== null) {
      for (const [key, hex] of Object.entries(object.paletteOverrides)) {
        const color = typeof hex === "string" ? colorFromHex(hex) : undefined;
        if (color && isPetPaletteRole(key)) overrides[key] = color;
      }
    }
    let furTint = typeof object.furTint === "string" ? colorFromHex(object.furTint) : undefined;
    let kept = overrides;
    const legacy = overrides.furBase;
    if (!("furTint" in object) && legacy) {
      furTint = legacy;
      kept = withoutRoles(overrides, TINTABLE_FUR_ROLES);
    }
    const outfit = typeof object.outfit === "string" && isOneOf(PET_OUTFITS, object.outfit) ? object.outfit : "none";
    const accessories = Array.isArray(object.accessories)
      ? object.accessories.filter((value): value is PetAccessory => typeof value === "string" && isOneOf(PET_ACCESSORIES, value))
      : [];
    return new PetProfile(name, breed, {
      paletteOverrides: kept,
      ...(furTint ? { furTint } : {}),
      outfit,
      accessories,
    });
  }
}
