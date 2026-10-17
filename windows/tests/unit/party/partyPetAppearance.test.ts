import { describe, expect, it } from "vitest";
import { partyProfile, type PartyProfile, type PartyProfileUpdate } from "../../../src/core/party/partyModels";
import { PARTY_COLOR_ROLES, forCatalogVersion1, localBreed, partyPet, partyPetUpdate, wireAccessory, wireOutfit } from "../../../src/core/party/partyPetAppearance";
import { breedDisplayName } from "../../../src/core/pets/petBreed";
import { PET_ACCESSORIES, PET_OUTFITS } from "../../../src/core/pets/petCostume";
import { PET_BREEDS } from "../../../src/core/pets/petKinds";
import { USER_EDITABLE_ROLES, colorFromHex, colorHex, type PetColor } from "../../../src/core/pets/petPalette";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { loadRepoJson } from "../../support/fixtures";

interface Catalog {
  species: string[];
  breeds: Record<string, string[]>;
  costumes: string[];
  accessories: string[];
  limits: Record<string, number>;
}

/* The server's catalog, read from the worker's source so a catalog change the app cannot send shows up here. */
const catalog = loadRepoJson<Catalog>("backend/shared/catalog.json");

function profileFrom(update: PartyProfileUpdate, code = "K7QW2MZD"): PartyProfile {
  return partyProfile({
    code,
    name: "Ana",
    petName: update.petName ?? "",
    species: update.species ?? "cat",
    breed: update.breed ?? "",
    colors: update.colors ?? [],
    costume: update.costume ?? "none",
    accessories: update.accessories ?? [],
  });
}

function hex(text: string): PetColor {
  const color = colorFromHex(text);
  if (color === undefined) throw new Error(text);
  return color;
}

const seenBy = (pet: PetProfile) => partyPet(profileFrom(partyPetUpdate(pet)));

describe("PartyPetAppearance", () => {
  it("sends only catalog values for every drawn pet", () => {
    for (const breed of PET_BREEDS) {
      const update = partyPetUpdate(new PetProfile("Mochi", breed, { outfit: "scrubs", accessories: PET_ACCESSORIES }));
      const species = update.species ?? "";
      expect(catalog.species, breed).toContain(species);
      expect(catalog.breeds[species], breed).toContain(update.breed);
      expect(catalog.costumes, breed).toContain(update.costume);
      for (const accessory of update.accessories ?? []) expect(catalog.accessories).toContain(accessory);
      expect(update.accessories?.length ?? 0).toBeLessThanOrEqual(catalog.limits.maxAccessories ?? 0);
      expect(update.colors?.length ?? 0).toBeLessThanOrEqual(catalog.limits.maxColors ?? 0);
      for (const color of update.colors ?? []) expect(color).toMatch(/^#[0-9A-F]{6}$/);
    }
    for (const outfit of PET_OUTFITS) {
      expect(catalog.costumes, outfit).toContain(partyPetUpdate(new PetProfile("Mochi", "calico", { outfit })).costume);
      expect(catalog.costumes).toContain(wireOutfit(outfit));
    }
    for (const accessory of PET_ACCESSORIES) expect(catalog.accessories, accessory).toContain(wireAccessory(accessory));
    expect(new Set(PET_ACCESSORIES.map(wireAccessory)).size, "two accessories share a server id").toBe(PET_ACCESSORIES.length);
  });

  it("draws a pet of the same species for every catalog breed", () => {
    for (const [species, breeds] of Object.entries(catalog.breeds)) {
      for (const breed of breeds) {
        const pet = partyPet(partyProfile({ code: "K7QW2MZD", name: "Ana", petName: "Mochi", species, breed }));
        expect(pet.species, breed).toBe(species);
      }
    }
  });

  it("shows a recolored, dressed pet to friends as it is", () => {
    const pet = new PetProfile("Pixel", "grayTabby", { outfit: "whiteCoat", accessories: ["roundGlasses", "scarf"] });
    pet.tintFur(hex("#8E6FD1"));
    pet.setColor(hex("#3366CC"), "costumeBase");
    const seen = seenBy(pet);
    expect(seen.name).toBe("Pixel");
    expect(seen.species).toBe("cat");
    expect(seen.outfit).toBe("whiteCoat");
    expect(new Set(seen.accessories)).toEqual(new Set(["roundGlasses", "scarf"]));
    for (const role of PARTY_COLOR_ROLES) expect(colorHex(seen.palette.color(role)), role).toBe(colorHex(pet.palette.color(role)));
    expect(seen.sittingCanvas()).toEqual(pet.sittingCanvas());
  });

  it("round-trips drawn breeds except the two tabbies", () => {
    for (const breed of PET_BREEDS) {
      const seen = seenBy(new PetProfile("A", breed));
      expect(seen.breed).toBe(breed === "grayTabby" ? "orangeTabby" : breed);
      expect(colorHex(seen.palette.color("furBase")), breed).toBe(colorHex(new PetProfile("A", breed).palette.color("furBase")));
    }
  });

  it("brings hats to friends with and without an outfit", () => {
    const looks = [
      new PetProfile("Luna", "siamese", { outfit: "scrubs", accessories: ["surgicalCap"] }),
      new PetProfile("Mochi", "orangeTabby", { outfit: "whiteCoat", accessories: ["graduationCap", "stethoscope"] }),
      new PetProfile("Biscuit", "goldenRetriever", { accessories: ["roundGlasses", "cowboyHat"] }),
      new PetProfile("Pepper", "blackCat", { outfit: "wizardRobe", accessories: ["wizardHat"] }),
      new PetProfile("Kit", "beagle", { outfit: "cozyHoodie", accessories: ["pirateHat", "scarf"] }),
    ];
    for (const pet of looks) {
      const seen = seenBy(pet);
      expect(seen.outfit, pet.name).toBe(pet.outfit);
      expect(seen.accessories, pet.name).toEqual(pet.accessories);
      expect(seen.sittingCanvas()).toEqual(pet.sittingCanvas());
    }
  });

  it("shows every outfit and accessory, and every slot recolored, as in the Closet", () => {
    for (const outfit of PET_OUTFITS) {
      for (const accessory of PET_ACCESSORIES) {
        const seen = seenBy(new PetProfile("Mochi", "calico", { outfit, accessories: [accessory] }));
        expect(seen.outfit, `${outfit} + ${accessory}`).toBe(outfit);
        expect(seen.accessories, `${outfit} + ${accessory}`).toEqual([accessory]);
      }
    }
    const full = new PetProfile("Nova", "corgi", {
      outfit: "studyHoodie",
      accessories: ["snowScarf", "heartGlasses", "lionDanceHat", "kingsCape", "cherryPetals"],
    });
    USER_EDITABLE_ROLES.forEach((role, index) => {
      const part = (value: number) => value.toString(16).toUpperCase().padStart(2, "0");
      full.setColor(hex(`#${part(40 + index * 20)}${part(200 - index * 15)}${part(90 + index * 9)}`), role);
    });
    const update = partyPetUpdate(full);
    expect(update.accessories?.length).toBe(5);
    const seen = partyPet(profileFrom(update));
    expect(seen.accessories).toEqual(full.accessories);
    for (const role of USER_EDITABLE_ROLES) expect(colorHex(seen.palette.color(role)), role).toBe(colorHex(full.palette.color(role)));
    expect(seen.sittingCanvas()).toEqual(full.sittingCanvas());
  });

  it("still sends and reads the hat in the costume slot for older apps", () => {
    const update = partyPetUpdate(new PetProfile("Doc", "corgi", { accessories: ["stethoscope", "beanie"] }));
    expect(update.costume).toBe("stethoscope");
    expect(update.accessories).toEqual(["stethoscope", "beanie"]);
    expect(partyPet(profileFrom(update)).accessories).toEqual(["stethoscope", "beanie"]);

    expect(partyPetUpdate(new PetProfile("Doc", "corgi", { outfit: "scrubs", accessories: ["stethoscope"] })).costume).toBe("scrubs");

    // What a 1.0 app sent for a graduation cap and glasses.
    const old = { ...profileFrom({ petName: "Mochi", species: "cat", breed: "tabby" }), costume: "graduation", accessories: ["glasses"] };
    expect(partyPet(old).accessories).toEqual(["roundGlasses", "graduationCap"]);
    // A head item the accessories name wins over the costume slot's.
    expect(partyPet({ ...old, accessories: ["glasses", "beanie"] }).accessories).toEqual(["roundGlasses", "beanie"]);
  });

  it("brings playful items to friends", () => {
    const update = partyPetUpdate(new PetProfile("Kit", "tuxedo", { accessories: ["bowTie", "coolSunglasses", "tinyCrown"] }));
    expect(update.costume).toBe("none");
    expect(update.accessories).toEqual(["bow", "sunglasses", "crown"]);
    expect(partyPet(profileFrom(update)).accessories).toEqual(["bowTie", "coolSunglasses", "tinyCrown"]);

    const pirate = partyPetUpdate(new PetProfile("Kit", "beagle", { accessories: ["partyHat", "pirateHat"] }));
    expect(pirate.costume).toBe("pirate");
    expect(pirate.accessories).toEqual(["pirate-hat"]);
    expect(partyPet(profileFrom(pirate)).accessories).toEqual(["pirateHat"]);
  });

  it("keeps only what a catalog version 1 server knows", () => {
    const pet = new PetProfile("Nova", "corgi", { outfit: "dinosaurHoodie", accessories: ["scarf", "heartGlasses", "wizardHat", "angelWings"] });
    const update = forCatalogVersion1(partyPetUpdate(pet));
    expect(update.costume).toBe("hoodie");
    expect(update.accessories).toEqual(["scarf"]);
    expect(update.colors?.length).toBe(6);
    const surgeon = partyPetUpdate(new PetProfile("Doc", "corgi", { accessories: ["surgicalCap"] }));
    expect(forCatalogVersion1(surgeon).costume).toBe("surgical-cap");
    expect(forCatalogVersion1(surgeon).accessories).toEqual([]);
  });

  it("sends the British Longhair to an older server as a longhair, and draws longhairs as one", () => {
    const update = partyPetUpdate(new PetProfile("Mocha", "britishLonghair"));
    expect(update.breed).toBe("british-longhair");
    expect(forCatalogVersion1(update).breed).toBe("domestic-longhair");
    expect(forCatalogVersion1(partyPetUpdate(new PetProfile("Nova", "corgi"))).breed).toBe("corgi");
    expect(localBreed("british-longhair", "cat")).toBe("britishLonghair");
    expect(localBreed("persian", "cat")).toBe("britishLonghair");
  });

  it("falls back on unknown server values instead of failing", () => {
    const pet = partyPet(
      partyProfile({
        code: "K7QW2MZD",
        name: "Ana",
        petName: "",
        species: "dragon",
        breed: "wyvern",
        colors: ["nope", "#123456"],
        costume: "santa",
        accessories: ["jetpack", "glasses"],
      }),
    );
    expect(pet.breed).toBe(PetProfile.starter("cat").breed);
    expect(pet.name).toBe(breedDisplayName(pet.breed));
    expect(pet.outfit).toBe("none");
    expect(pet.accessories).toEqual(["roundGlasses"]);
    expect(colorHex(pet.palette.color("furBase"))).toBe(colorHex(PetProfile.starter("cat").palette.color("furBase")));
    expect(colorHex(pet.palette.color("furShade"))).toBe("#123456");

    const dog = partyPet(partyProfile({ code: "K7QW2MZD", name: "B", petName: "Rex", species: "dog", breed: "unknown" }));
    expect(dog.species).toBe("dog");
  });
});
