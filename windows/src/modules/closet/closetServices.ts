/*
 * The pet services, declared here because the Closet owns the pet's save
 * (the Mac's `context.studyPet`, a ClosetStore, and `context.surpriseGifts`):
 * Study and Party follow the store's `profile`, so every module draws the
 * same pet in the same outfit, and the coach hands out the gifts. Every
 * module asking gets the one instance, already following the shared focus
 * clock, the activity log, kit switches and the island opening and closing.
 */

import type { ModuleContext } from "../../app/context";
import { serviceKey } from "../../app/sharedServices";
import { ClosetStore } from "./closetStore";
import { SurpriseGiftKeeper } from "./surpriseGiftKeeper";

const STUDY_PET = serviceKey<ClosetStore>("closet.studyPet");
const SURPRISE_GIFTS = serviceKey<SurpriseGiftKeeper>("closet.surpriseGifts");

/** The one study pet: its look, points and save; read `state.profile` for the pet as shown everywhere. */
export function studyPet(context: ModuleContext): ClosetStore {
  return context.shared.resolve(STUDY_PET, () => {
    const store = new ClosetStore(context);
    store.followFocus();
    void store.followActivity();
    store.followKits();
    store.followIslandToggles();
    return store;
  });
}

/** The one surprise gift keeper, beside the pet it gives to. */
export function surpriseGifts(context: ModuleContext): SurpriseGiftKeeper {
  return context.shared.resolve(SURPRISE_GIFTS, () => new SurpriseGiftKeeper(context, studyPet(context)));
}
