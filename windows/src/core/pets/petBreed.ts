import { tr } from "../localization/tr";
import { petArt, type BreedDefinition } from "./petArt";
import { PET_BREEDS, type PetBodyShape, type PetBreed, type PetSpecies } from "./petKinds";
import { PetFurTone, PetPalette, type PaletteOverrides, type PetColor, type PetPaletteRole } from "./petPalette";
import { PetPattern } from "./petCanvas";

/*
 * Port of PetSpecies, PetBodyShape and PetBreed: everything about a breed
 * but its fur tones is data in `breeds.json`, which both apps draw from.
 */

export function speciesDisplayName(species: PetSpecies): string {
  return species === "cat" ? tr("Cat") : tr("Dog");
}

export function bodyShapeSpecies(shape: PetBodyShape): PetSpecies {
  return petArt("breeds").species(shape);
}

function definition(breed: PetBreed): BreedDefinition {
  return petArt("breeds").breed(breed);
}

export function breedBodyShape(breed: PetBreed): PetBodyShape {
  return definition(breed).bodyShape;
}

export function breedSpecies(breed: PetBreed): PetSpecies {
  return bodyShapeSpecies(breedBodyShape(breed));
}

/** Whether the breed shows a tail when sitting (corgis and French Bulldogs are stubby-tailed). */
export function breedHasTail(breed: PetBreed): boolean {
  return definition(breed).hasTail;
}

/** The breed's name as `breeds.json` writes it, which the Mac shows as is. */
export function breedDisplayName(breed: PetBreed): string {
  return definition(breed).name;
}

export function breedsOf(species: PetSpecies): PetBreed[] {
  return PET_BREEDS.filter((breed) => breedSpecies(breed) === species);
}

const palettes = new Map<PetBreed, PetPalette>();

/** The breed's default colors before any user recoloring. */
export function breedPalette(breed: PetBreed): PetPalette {
  let palette = palettes.get(breed);
  if (!palette) {
    palette = new PetPalette(definition(breed).palette);
    palettes.set(breed, palette);
  }
  return palette;
}

const patterns = new Map<PetBreed, PetPattern>();

/** Which zones of the shared art become which palette role. */
export function breedPattern(breed: PetBreed): PetPattern {
  let pattern = patterns.get(breed);
  if (!pattern) {
    pattern = new PetPattern(definition(breed).pattern);
    patterns.set(breed, pattern);
  }
  return pattern;
}

type FurTones = Partial<Record<PetPaletteRole, PetFurTone>>;

const { pick, marking } = PetFurTone;
const darker = (amount: number, chroma?: number) => PetFurTone.darker(amount, chroma);
const lighter = (amount: number, chroma?: number) => PetFurTone.lighter(amount, chroma);

/**
 * How each fur role follows a picked fur color. Roles left out keep the
 * breed's own color, so white bibs, muzzles and paws stay white.
 */
export function breedFurTones(breed: PetBreed): FurTones {
  switch (breed) {
    case "orangeTabby":
    case "grayTabby":
      return { furBase: pick, furShade: darker(0.18), furAccent: darker(0.34), belly: lighter(0.7, 0.45) };
    case "blackCat":
      return { furBase: pick, furShade: darker(0.2), furAccent: lighter(0.12), belly: lighter(0.12) };
    case "whiteCat":
      return { furBase: pick, furShade: darker(0.14), furAccent: darker(0.06), belly: lighter(0.6, 0.4) };
    case "tuxedo":
      return { furBase: pick, furShade: darker(0.2), furAccent: lighter(0.12) };
    case "calico":
      return { furAccent: marking, furSpot: darker(0.5, 0.8) };
    case "siamese":
      return {
        furBase: lighter(0.65, 0.35),
        furShade: lighter(0.45, 0.45),
        belly: lighter(0.8, 0.25),
        furAccent: darker(0.3, 0.8),
        furSpot: darker(0.1, 0.75),
      };
    case "britishShorthair":
      return { furBase: pick, furShade: darker(0.12), furAccent: darker(0.35) };
    case "sphynx":
      return { furBase: pick, furShade: darker(0.14), furAccent: darker(0.1), belly: lighter(0.35, 0.7) };
    case "britishLonghair":
      return { furBase: pick, furShade: darker(0.16), furAccent: lighter(0.12), belly: lighter(0.2) };
    case "scottishFold":
      return { furBase: pick, furShade: darker(0.16), furAccent: lighter(0.2), belly: lighter(0.65, 0.4) };
    case "goldenRetriever":
      return { furBase: pick, furShade: darker(0.2), furAccent: lighter(0.35, 0.8), belly: lighter(0.55, 0.6) };
    case "labrador":
      return { furBase: pick, furShade: darker(0.2), furAccent: lighter(0.1), belly: lighter(0.1) };
    case "frenchBulldog":
      return { furSpot: marking };
    case "corgi":
      return { furBase: pick, furShade: darker(0.18), furAccent: lighter(0.2) };
    case "dachshund":
      return { furBase: pick, furShade: darker(0.2), furAccent: lighter(0.1), belly: lighter(0.45, 0.8) };
    case "beagle":
      return { furBase: pick, furShade: darker(0.16), furAccent: darker(0.22), furSpot: darker(0.55, 0.6) };
    case "poodle":
      return { furBase: pick, furShade: darker(0.2), furAccent: lighter(0.35), belly: lighter(0.55, 0.6) };
    case "shihTzu":
      return { furBase: pick, furShade: darker(0.2), furAccent: lighter(0.12), belly: lighter(0.08) };
  }
}

/** Fur overrides for one picked color. */
export function breedFurTint(breed: PetBreed, color: PetColor): PaletteOverrides {
  return breedPalette(breed).furTint(color, breedFurTones(breed));
}
