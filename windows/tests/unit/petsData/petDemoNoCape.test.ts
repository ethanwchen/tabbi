import { readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { PetCloset } from "../../../src/core/closet/petCloset";
import { starterForKit } from "../../../src/core/closet/petKitDefaults";
import { readKitManifest } from "../../../src/core/kits/kitManifest";
import { PetMilestoneProgress } from "../../../src/core/closet/petLimited";
import { PetJournal } from "../../../src/core/pets/petAdventure";
import { accessoryItem, outfitItem } from "../../../src/core/pets/petItem";
import { PET_SPECIES } from "../../../src/core/pets/petKinds";
import { PetProfile } from "../../../src/core/pets/petProfile";
import type { DayCalendar } from "../../../src/core/streaks/dayCalendar";
import { loadRepoJson } from "../../support/fixtures";

// Product rule: demo and snapshot art never dress the pet in a cape (the
// Superhero Cape or the King's Cape), though both exist in the Closet.

const capes = [outfitItem("superheroCape"), accessoryItem("kingsCape")];

function expectNoCape(profile: PetProfile, name: string): void {
  for (const cape of capes) expect(profile.isWearing(cape), `${name} wears ${cape}`).toBe(false);
}

describe("demo and snapshot pets", () => {
  it("dress the demo closet without a cape and own none", () => {
    const closet = PetCloset.demo();
    expectNoCape(closet.profile, "the demo closet");
    for (const cape of capes) expect(closet.save.ledger.owns(cape)).toBe(false);
  });

  it("start every species bare", () => {
    for (const species of PET_SPECIES) expectNoCape(PetProfile.starter(species), species);
  });

  it("start every bundled kit's pet without a cape", () => {
    const folder = fileURLToPath(new URL("../../../../Sources/TabbiKitCore/Kits/Bundled/", import.meta.url));
    const kits = readdirSync(folder).filter((file) => file.endsWith(".json"));
    expect(kits.length).toBeGreaterThan(0);
    for (const file of kits) {
      const kit = readKitManifest(loadRepoJson(`Sources/TabbiKitCore/Kits/Bundled/${file}`));
      expectNoCape(starterForKit(kit.defaults), file);
    }
  });

  it("keep the demo journal and milestone progress free of capes", () => {
    const calendar: DayCalendar = { timeZone: "America/New_York", firstWeekday: 1 };
    const now = 1_792_000_000;
    const journal = PetJournal.demo(now);
    expect(JSON.stringify(journal.toJSON())).not.toMatch(/cape/i);
    const closet = PetCloset.demo();
    const granted = closet.unlockMilestones(PetMilestoneProgress.demo(now, calendar));
    for (const cape of capes) expect(granted).not.toContain(cape);
    expectNoCape(closet.profile, "the demo closet after its milestones");
  });
});
