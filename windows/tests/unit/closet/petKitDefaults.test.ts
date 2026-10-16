import { describe, expect, it } from "vitest";
import { starterForKit } from "../../../src/core/closet/petKitDefaults";
import { kitDefaults, readKitManifest, type KitDefaults } from "../../../src/core/kits/kitManifest";
import type { JSONValue } from "../../../src/core/persistence/json";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { loadRepoJson } from "../../support/fixtures";

// Port of PetKitDefaultsTests: the pet comes from a kit's
// `moduleSettings.closet.pet`, read leniently.
const petKit = (pet: JSONValue) => kitDefaults({ moduleSettings: { closet: { pet } } });

function bundledKit(id: string): KitDefaults {
  return readKitManifest(loadRepoJson(`Sources/TabbiKitCore/Kits/Bundled/${id}.json`)).defaults;
}

describe("starterForKit", () => {
  it("a kit without a pet starts on the starter cat", () => {
    expect(starterForKit(undefined).equals(PetProfile.starter("cat"))).toBe(true);
    expect(starterForKit(kitDefaults()).equals(PetProfile.starter("cat"))).toBe(true);
  });

  it("the kit's breed gets its species' starter name", () => {
    const corgi = starterForKit(petKit({ breed: "corgi" }));
    expect(corgi.breed).toBe("corgi");
    expect(corgi.name).toBe(PetProfile.starter("dog").name);
  });

  it("the kit's name is cleaned and an unknown breed is skipped", () => {
    const pet = starterForKit(petKit({ breed: "dragon", name: "  Sir   Whiskers the Magnificent  " }));
    expect(pet.breed).toBe(PetProfile.starter("cat").breed);
    expect(pet.name).toBe("Sir Whiskers the");
  });

  it("Med School starts on its own pet and Essentials on the default", () => {
    expect(starterForKit(bundledKit("medicine")).breed).toBe("orangeTabby");
    expect(starterForKit(bundledKit("essentials")).breed).toBe(starterForKit(undefined).breed);
  });
});
