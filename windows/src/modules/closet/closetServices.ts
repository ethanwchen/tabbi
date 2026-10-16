/*
 * The pet service, declared here because the Closet owns the pet's save
 * (the Mac's `context.studyPet`, a ClosetStore): Study and Party follow its
 * profile, so every module draws the same pet in the same outfit. Until the
 * Closet port loads and saves the PetSave, it holds the kit's starter pet.
 */

import type { ModuleContext } from "../../app/context";
import { serviceKey } from "../../app/sharedServices";
import { Store } from "../../app/store";
import { starterForKit } from "../../core/closet/petKitDefaults";
import type { PetProfile } from "../../core/pets/petProfile";

export class StudyPetService extends Store<{ readonly profile: PetProfile }> {
  constructor(profile: PetProfile) {
    super({ profile });
  }

  /** Replaces the pet everyone draws. */
  setProfile(profile: PetProfile): void {
    this.changed({ profile });
  }
}

const STUDY_PET = serviceKey<StudyPetService>("closet.studyPet");

/** The one pet. */
export function studyPet(context: ModuleContext): StudyPetService {
  return context.shared.resolve(STUDY_PET, () => new StudyPetService(starterForKit(context.activeKit?.defaults)));
}
