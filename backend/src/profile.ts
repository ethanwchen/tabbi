// Profile model: the pet and the few public numbers a user shares with friends.
import {
  BREEDS, COSTUMES, DEFAULT_NAME, DEFAULT_PET_NAME, HttpError, MAX_NAME, MAX_PET_NAME, MAX_STUDY_LEVEL, NAMEPLATES, Obj,
  SPECIES, clampedInt, cleanText, int, oneOf, parseAccessories, parseColors,
} from "./lib";
import { isNameAllowed } from "./names";

/** What friends and party members see of a user. */
export interface Profile {
  code: string;
  name: string;
  petName: string;
  species: string;
  breed: string;
  colors: string[];
  costume: string;
  accessories: string[];
  points: number;
  level: number;
  /**
   * The Study Level (protocol 3, from 0), clamped to 0...MAX_STUDY_LEVEL. Only shown to friends; the
   * server derives nothing from it. Absent for users whose apps never sent one.
   */
  studyLevel?: number;
  /** The nameplate color id beside the Study Level (`catalog.nameplates`), absent until sent. */
  nameplate?: string;
}

/** Body fields accepted by `POST /v1/register` and `PATCH /v1/me`. */
export const PROFILE_FIELDS = [
  "name", "petName", "species", "breed", "colors", "costume", "accessories", "points", "level",
  // Protocol 3. Older apps never send them; a server from before refuses them as unknown fields.
  "studyLevel", "nameplate",
] as const;

export type ProfilePatch = Partial<Omit<Profile, "code">>;

export function defaultProfile(code: string): Profile {
  return {
    code,
    name: DEFAULT_NAME,
    petName: DEFAULT_PET_NAME,
    species: "cat",
    breed: BREEDS.cat[0],
    colors: [],
    costume: "none",
    accessories: [],
    points: 0,
    level: 1,
  };
}

/** Validates the profile fields present in `body`; absent (or null/empty-text) fields stay undefined. */
export function parseProfilePatch(body: Obj): ProfilePatch {
  const p: ProfilePatch = {};
  const name = cleanText(body.name, "name", MAX_NAME);
  if (name !== undefined) {
    if (!isNameAllowed(name)) throw new HttpError(400, "name_not_allowed", "That name isn't allowed. Please pick another.");
    p.name = name;
  }
  const petName = cleanText(body.petName, "petName", MAX_PET_NAME);
  if (petName !== undefined) {
    if (!isNameAllowed(petName)) throw new HttpError(400, "pet_name_not_allowed", "That pet name isn't allowed. Please pick another.");
    p.petName = petName;
  }
  if (body.species !== undefined) p.species = oneOf(body.species, SPECIES, "species");
  if (body.breed !== undefined) {
    // Checked against the species after merging, see `applyProfilePatch`.
    if (typeof body.breed !== "string") throw new HttpError(400, "invalid_field", "invalid breed");
    p.breed = body.breed;
  }
  if (body.colors !== undefined) p.colors = parseColors(body.colors);
  if (body.costume !== undefined) p.costume = oneOf(body.costume, COSTUMES, "costume");
  if (body.accessories !== undefined) p.accessories = parseAccessories(body.accessories);
  if (body.points !== undefined) p.points = int(body.points, "points", 0, 100_000_000);
  if (body.level !== undefined) p.level = int(body.level, "level", 1, 999);
  if (body.studyLevel !== undefined && body.studyLevel !== null) {
    p.studyLevel = clampedInt(body.studyLevel, "studyLevel", 0, MAX_STUDY_LEVEL);
  }
  if (body.nameplate !== undefined && body.nameplate !== null) p.nameplate = oneOf(body.nameplate, NAMEPLATES, "nameplate");
  return p;
}

/**
 * Returns `profile` with `patch` applied. Switching species without naming a breed picks that species'
 * first breed, so a cat never ends up with a dog breed; an explicit breed must belong to the species.
 */
export function applyProfilePatch(profile: Profile, patch: ProfilePatch): Profile {
  const next: Profile = { ...profile, ...patch };
  const breeds = BREEDS[next.species];
  if (patch.breed === undefined && !breeds.includes(next.breed)) next.breed = breeds[0];
  if (!breeds.includes(next.breed)) throw new HttpError(400, "invalid_field", "invalid breed");
  return next;
}

export function sameProfile(a: Profile, b: Profile): boolean {
  return JSON.stringify(a) === JSON.stringify(b);
}
