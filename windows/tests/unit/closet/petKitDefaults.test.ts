import { describe, expect, it } from "vitest";
import { starterForKit } from "../../../src/core/closet/petKitDefaults";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { loadRepoJson } from "../../support/fixtures";

// Port of PetKitDefaultsTests. The kit port owns reading kits; here the
// `moduleSettings.closet.pet` value is handed over as the kit JSON holds it.
interface KitFile {
  defaults?: { moduleSettings?: { closet?: { pet?: unknown } } };
}

function bundledPet(id: string): unknown {
  return loadRepoJson<KitFile>(`Sources/TabbiKitCore/Kits/Bundled/${id}.json`).defaults?.moduleSettings?.closet?.pet;
}

describe("starterForKit", () => {
  it("a kit without a pet starts on the starter cat", () => {
    expect(starterForKit(undefined).equals(PetProfile.starter("cat"))).toBe(true);
    expect(starterForKit({}).equals(PetProfile.starter("cat"))).toBe(true);
  });

  it("the kit's breed gets its species' starter name", () => {
    const corgi = starterForKit({ breed: "corgi" });
    expect(corgi.breed).toBe("corgi");
    expect(corgi.name).toBe(PetProfile.starter("dog").name);
  });

  it("the kit's name is cleaned and an unknown breed is skipped", () => {
    const pet = starterForKit({ breed: "dragon", name: "  Sir   Whiskers the Magnificent  " });
    expect(pet.breed).toBe(PetProfile.starter("cat").breed);
    expect(pet.name).toBe("Sir Whiskers the");
  });

  it("Med School starts on its own pet and Essentials on the default", () => {
    expect(starterForKit(bundledPet("medicine")).breed).toBe("orangeTabby");
    expect(starterForKit(bundledPet("essentials")).breed).toBe(starterForKit(undefined).breed);
  });
});
